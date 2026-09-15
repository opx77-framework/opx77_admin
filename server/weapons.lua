--- Weapon commands. A weapon is an opx77_inventory item: a unit in a bag carrying a serial and its
--- rounds, which the player draws by using it. Ammunition is an item of its own, a stack the
--- player spends on the drawn weapon that takes it. So a give adds an empty weapon item, and its
--- ammunition, when asked for, as a separate stack; a refill adds ammunition items; a removal
--- takes the weapon item; a read lists the weapon items and which one is drawn -- all through the
--- inventory's server exports (server/inventory.lua), never by putting a record in a game slot or
--- rounds on an item. The inventory takes off, every WEAPONS.SCAN_MS, any weapon a bag does not
--- back, so a weapon handed over any other way would not last, and would not be recorded.
---
--- One thing stays on `Open77.weapons`, the platform's relay to the target client's
--- open77_weapons half, because the inventory has no export for it and it changes no item:
--- holstering. A relay step answers in two halves: `open77:weapons:completed` carries the
--- client's verdict.

local Server = OpxAdmin.Server
local Inventory = OpxAdmin.Inventory
local Text = OpxAdmin.Text

local answer, refuse, audit, tell = Server.answer, Server.refuse, Server.audit, Server.tell

--- tostring(requestId) -> the holster a completion answers.
local pending = {}

--- A relay that never answers is a timeout on the platform's side; this bounds the table in
--- case the completion never reaches this VM at all.
local PENDING_MS = 30000

---@return boolean
local function available()
	local weapons = Open77.weapons
	return type(weapons) == 'table' and type(weapons.holster) == 'function'
end

--- A typed count of ammunition items: nil when omitted, false when it is not a whole number in
--- `least`..INVENTORY.MAX_COUNT.
---@param token any
---@param least integer  0 for a give, where 0 means none; 1 elsewhere
---@return integer|false|nil
local function typedCount(token, least)
	if token == nil then return nil end
	local count = Text.integer(token)
	if count == nil or count < least or count > Inventory.MAX_COUNT then return false end
	return count
end

--- The ammunition item that loads a weapon item, or nil for a melee weapon.
---@param catalog table
---@param entry table  a weapon item of the inventory's catalogue
---@return table|nil
local function ammoOf(catalog, entry)
	local name = entry.weapon and entry.weapon.ammo
	local ammo = name and catalog.byName[name] or nil
	return ammo and ammo.ammoMax and ammo or nil
end

--- What was typed for ammunition: an ammo item's name, or a weapon's name, short or not, standing
--- for the ammunition that loads it.
---@param catalog table
---@param token any
---@return table|nil ammo, string|nil code, table|nil weapon
local function ammoFor(catalog, token)
	local item = Inventory.item(catalog, token)
	if item and item.ammoMax then return item, nil, nil end
	local weapon = Inventory.weapon(catalog, token)
	if weapon == nil then return nil, 'unknown_ammo', nil end
	local ammo = ammoOf(catalog, weapon)
	if ammo == nil then return nil, 'melee_no_ammo', weapon end
	return ammo, nil, weapon
end

--- The serials of one weapon's items in a bag.
---@param bag table
---@param name string
---@return table<string, true>
local function serialsOf(bag, name)
	local serials = {}
	for _, row in ipairs(bag.items) do
		local serial = row.name == name and type(row.metadata) == 'table' and row.metadata.serial
		if type(serial) == 'string' then serials[serial] = true end
	end
	return serials
end

-- ---------------------------------------------------------------------------
-- The holster, on the relay
-- ---------------------------------------------------------------------------

AddEventHandler('open77:weapons:completed', function(playerId, requestId, operation, accepted,
	reason, result)
	local key = tostring(requestId)
	local step = pending[key]
	if step == nil then return end
	pending[key] = nil
	if tonumber(playerId) ~= step.playerId then return end

	if accepted ~= true then
		local code = tostring(reason) == 'request_timeout' and 'weapon_no_answer' or 'refused'
		audit(step.source, 'admin.weapon.holster', false, step.playerId, tostring(reason))
		return refuse(step.source, step.raw, code, { reason = tostring(reason), id = step.playerId })
	end
	audit(step.source, 'admin.weapon.holster', true, step.playerId)
	answer(step.source, step.raw, true, 'admin.done.holstered', { id = step.playerId })
end)

CreateThread(function()
	while true do
		Wait(10000)
		local atMs = Server.nowMs()
		for key, step in pairs(pending) do
			if atMs - (step.atMs or atMs) > PENDING_MS then pending[key] = nil end
		end
	end
end)

-- ---------------------------------------------------------------------------
-- The commands
-- ---------------------------------------------------------------------------

local TARGET = { name = 'playerId|me|citizenId', help = 'admin.help.holder' }

--- The refusals that need no call, answered before a thread is started.
---@return integer|string|nil target, string|nil who, integer|nil playerId
local function resolve(source, raw, token)
	local target, who, playerId, code = Inventory.target(source, token)
	if target == nil then
		refuse(source, raw, code)
		return nil
	end
	if not Inventory.running() then
		refuse(source, raw, 'inventory_unavailable')
		return nil
	end
	return target, who, playerId
end

--- The weapon and its ammunition, both or neither. Coroutine only. The bag is read first so the
--- two are checked together -- CanCarry weighs one item at a time -- and so the weapon just added
--- can be told from a copy already there, by its serial, if the ammunition is then refused.
---@return boolean given
local function giveWithAmmo(source, raw, event, target, who, playerId, entry, ammo, count)
	local both = locale('admin.inventory.pair', { label = entry.label, count = count,
		ammo = ammo.label })
	local bag, bagCode, bagReason = Inventory.bag(target)
	if not bag then
		Inventory.fail(source, raw, event, playerId, who, bagCode, bagReason)
		return false
	end
	local weight = bag.weight + (entry.weight or 0) + (ammo.weight or 0) * count
	local stacked = false
	for _, row in ipairs(bag.items) do
		if row.name == ammo.name and (row.metadata == nil or next(row.metadata) == nil) then
			stacked = true
		end
	end
	local code, reason
	if bag.maxWeight > 0 and weight > bag.maxWeight then
		code, reason = 'bag_too_heavy', 'too_heavy'
	elseif bag.slots - #bag.items < (stacked and 1 or 2) then
		code, reason = 'bag_no_room', 'no_room'
	else
		local carried
		carried, code, reason = Inventory.carry(target, entry.name, 1, { ammo = 0 })
		if carried then carried, code, reason = Inventory.carry(target, ammo.name, count) end
		if carried then code = nil end
	end
	if code then
		Inventory.fail(source, raw, event, playerId, who, code, reason, { item = both })
		return false
	end

	local before = serialsOf(bag, entry.name)
	local added, addCode, addReason = Inventory.call('AddItem', target, entry.name, 1, { ammo = 0 })
	if not added then
		Inventory.fail(source, raw, event, playerId, who, addCode, addReason, { item = entry.label })
		return false
	end
	added, addCode, addReason = Inventory.call('AddItem', target, ammo.name, count)
	if added then return true end

	-- the inventory decides last: the weapon goes back out, so nothing is given
	local after = Inventory.bag(target)
	local taken
	for _, row in ipairs(after and after.items or {}) do
		local serial = row.name == entry.name and type(row.metadata) == 'table' and row.metadata.serial
		if taken == nil and type(serial) == 'string' and not before[serial] then
			taken = Inventory.call('RemoveItem', target, entry.name, 1, row.metadata) and serial or false
		end
	end
	if not taken then
		audit(source, event, false, playerId, ('%s: %s given, %dx %s refused (%s), not taken back')
			:format(who, entry.name, count, ammo.name, tostring(addReason)))
		refuse(source, raw, 'give_partial', { label = entry.label, who = who, count = count,
			ammo = ammo.label, reason = addReason })
		return false
	end
	audit(source, event, false, playerId, ('%s taken back from %s: its ammunition was refused')
		:format(taken, who))
	Inventory.fail(source, raw, event, playerId, who, addCode, addReason, { item = both })
	return false
end

Server.command('opx77.admin.weapon.give', {
	help = 'admin.help.giveWeapon',
	params = { TARGET,
		{ name = 'weapon', help = 'admin.help.weaponName' },
		{ name = 'ammo', help = 'admin.help.giveAmmoCount', optional = true } },
	handler = function(source, args, raw)
		if Text.clean(args[2], 48) == nil then return refuse(source, raw, 'unknown_weapon') end
		local count = typedCount(args[3], 0)
		if count == false then
			return refuse(source, raw, 'bad_count', { max = Inventory.MAX_COUNT })
		end
		count = count or 0
		local target, who, playerId = resolve(source, raw, args[1])
		if target == nil then return end
		CreateThread(function()
			local event = 'admin.weapon.give'
			local catalog, code, reason = Inventory.catalog()
			if not catalog then return Inventory.fail(source, raw, event, playerId, who, code, reason) end
			local entry = Inventory.weapon(catalog, args[2])
			if entry == nil then
				return Inventory.fail(source, raw, event, playerId, who, 'unknown_weapon',
					Text.clean(args[2], 48))
			end
			local ammo = ammoOf(catalog, entry)
			if count > 0 and ammo == nil then
				return Inventory.fail(source, raw, event, playerId, who, 'melee_no_ammo', entry.name,
					{ label = entry.label })
			end

			-- empty: rounds come from ammunition items the player spends on it, never with the weapon
			if count == 0 then
				if not Inventory.give(source, raw, event, target, who, playerId, entry.name, 1,
					ammo and { ammo = 0 } or nil, entry.label) then
					return
				end
			elseif not giveWithAmmo(source, raw, event, target, who, playerId, entry, ammo, count) then
				return
			end

			audit(source, event, true, playerId, ('%s to %s, %dx %s'):format(entry.name, who, count,
				ammo and ammo.name or '-'))
			if playerId and playerId ~= source then
				tell(playerId, 'admin.toast.weapon', { label = entry.label }, 'success')
				if count > 0 then
					tell(playerId, 'admin.toast.itemGiven', { count = count, label = ammo.label }, 'info')
				end
			end
			local key = ammo == nil and 'admin.done.meleeGiven' or count > 0 and
				'admin.done.weaponGivenAmmo' or 'admin.done.weaponGiven'
			answer(source, raw, true, key, { label = entry.label, who = who, count = count,
				ammo = ammo and ammo.label or '' })
		end)
	end,
})

Server.command('opx77.admin.weapon.giveammo', {
	help = 'admin.help.giveAmmo',
	params = { TARGET,
		{ name = 'weapon|ammo', help = 'admin.help.ammoName' },
		{ name = 'count', help = 'admin.help.ammoCount', optional = true } },
	handler = function(source, args, raw)
		if Text.clean(args[2], 48) == nil then
			return refuse(source, raw, 'unknown_ammo', { item = '?' })
		end
		local typed = typedCount(args[3], 1)
		if typed == false then
			return refuse(source, raw, 'bad_count', { max = Inventory.MAX_COUNT })
		end
		local target, who, playerId = resolve(source, raw, args[1])
		if target == nil then return end
		CreateThread(function()
			local event = 'admin.weapon.giveammo'
			local catalog, code, reason = Inventory.catalog()
			if not catalog then return Inventory.fail(source, raw, event, playerId, who, code, reason) end
			local ammo, ammoCode, weapon = ammoFor(catalog, args[2])
			if ammo == nil then
				return Inventory.fail(source, raw, event, playerId, who, ammoCode, Text.clean(args[2], 48),
					{ item = Text.clean(args[2], 48), label = weapon and weapon.label })
			end
			-- one full load of that ammunition when no count is typed
			local count = typed or ammo.ammoMax
			if not Inventory.give(source, raw, event, target, who, playerId, ammo.name, count, nil,
				ammo.label) then
				return
			end
			audit(source, event, true, playerId, ('%dx %s to %s'):format(count, ammo.name, who))
			if playerId and playerId ~= source then
				tell(playerId, 'admin.toast.itemGiven', { count = count, label = ammo.label }, 'info')
			end
			answer(source, raw, true, 'admin.done.ammoGiven', { count = count, label = ammo.label,
				who = who })
		end)
	end,
})

Server.command('opx77.admin.weapon.ammo', {
	help = 'admin.help.ammo',
	params = { TARGET,
		{ name = 'weapon|all', help = 'admin.help.weaponOrAllOptional', optional = true },
		{ name = 'count', help = 'admin.help.refillCount', optional = true } },
	handler = function(source, args, raw)
		local all = args[2] == nil or tostring(args[2]):lower() == 'all'
		local typed = typedCount(args[3], 1)
		if typed == false then
			return refuse(source, raw, 'bad_count', { max = Inventory.MAX_COUNT })
		end
		local target, who, playerId = resolve(source, raw, args[1])
		if target == nil then return end
		CreateThread(function()
			local event = 'admin.weapon.ammo'
			local catalog, code, reason = Inventory.catalog()
			if not catalog then return Inventory.fail(source, raw, event, playerId, who, code, reason) end
			local only
			if not all then
				only = Inventory.weapon(catalog, args[2])
				if only == nil then
					return Inventory.fail(source, raw, event, playerId, who, 'unknown_weapon',
						Text.clean(args[2], 48))
				end
			end
			local bag, bagCode, bagReason = Inventory.bag(target)
			if not bag then
				return Inventory.fail(source, raw, event, playerId, who, bagCode, bagReason)
			end

			-- one ammunition type once, however many weapons of the bag it loads
			local types, seen = {}, {}
			for _, row in ipairs(bag.items) do
				local entry = catalog.byName[row.name]
				local ammo = entry and entry.weapon and (only == nil or only.name == entry.name) and
					ammoOf(catalog, entry) or nil
				if ammo and not seen[ammo.name] then
					seen[ammo.name] = true
					types[#types + 1] = ammo
				end
			end
			if #types == 0 then
				return answer(source, raw, false, 'admin.done.nothingToRefill', { who = who }, 'warning')
			end

			local given, failure = {}, nil
			for _, ammo in ipairs(types) do
				local count = typed or ammo.ammoMax
				local added, addCode, addReason = Inventory.add(target, ammo.name, count)
				if added then
					given[#given + 1] = ('%dx %s'):format(count, ammo.label)
					audit(source, event, true, playerId, ('%dx %s to %s'):format(count, ammo.name, who))
					if playerId and playerId ~= source then
						tell(playerId, 'admin.toast.itemGiven', { count = count, label = ammo.label }, 'info')
					end
				else
					failure = failure or { code = addCode, reason = addReason, label = ammo.label }
				end
			end
			if #given > 0 then
				answer(source, raw, true, 'admin.done.refilled', { items = table.concat(given, ', '),
					who = who })
			end
			if failure then
				Inventory.fail(source, raw, event, playerId, who, failure.code, failure.reason,
					{ item = failure.label })
			end
		end)
	end,
})

Server.command('opx77.admin.weapon.remove', {
	help = 'admin.help.removeWeapon',
	params = { TARGET, { name = 'weapon|all', help = 'admin.help.weaponOrAll' } },
	handler = function(source, args, raw)
		-- no default: taking every weapon is never what a forgotten argument meant
		if Text.clean(args[2], 48) == nil then return refuse(source, raw, 'unknown_weapon') end
		local all = tostring(args[2]):lower() == 'all'
		local target, who, playerId = resolve(source, raw, args[1])
		if target == nil then return end
		CreateThread(function()
			local event = 'admin.weapon.remove'
			local catalog, code, reason = Inventory.catalog()
			if not catalog then return Inventory.fail(source, raw, event, playerId, who, code, reason) end
			local only
			if not all then
				only = Inventory.weapon(catalog, args[2])
				if only == nil then
					return Inventory.fail(source, raw, event, playerId, who, 'unknown_weapon',
						Text.clean(args[2], 48))
				end
			end
			local bag, bagCode, bagReason = Inventory.bag(target)
			if not bag then
				return Inventory.fail(source, raw, event, playerId, who, bagCode, bagReason)
			end

			-- by name and count, not by slot: a slot read a moment ago may hold something else now
			local counts, order = {}, {}
			for _, row in ipairs(bag.items) do
				local entry = catalog.byName[row.name]
				if entry and entry.weapon and (only == nil or only.name == entry.name) then
					if counts[row.name] == nil then order[#order + 1] = row.name end
					counts[row.name] = (counts[row.name] or 0) + row.count
				end
			end
			if #order == 0 then
				return answer(source, raw, false, 'admin.done.noWeapons', { who = who }, 'warning')
			end
			local removed, failure = 0, nil
			for _, name in ipairs(order) do
				local taken, takeCode, takeReason = Inventory.call('RemoveItem', target, name, counts[name])
				if taken then
					removed = removed + counts[name]
				else
					failure = { code = takeCode, reason = takeReason }
				end
			end
			if removed == 0 then
				return Inventory.fail(source, raw, event, playerId, who, failure.code, failure.reason)
			end
			-- the inventory puts a drawn weapon away itself once its item has left the bag
			audit(source, event, true, playerId, ('%d weapon(s) from %s%s'):format(removed, who,
				failure and (', then ' .. tostring(failure.reason)) or ''))
			if playerId and playerId ~= source then
				tell(playerId, 'admin.toast.weaponsTaken', { count = removed }, 'warning')
			end
			answer(source, raw, true, 'admin.done.weaponsRemoved', { count = removed, who = who })
		end)
	end,
})

Server.command('opx77.admin.weapon.holster', {
	help = 'admin.help.holster',
	params = { { name = 'playerId|me', help = 'admin.help.playerOrMe' } },
	handler = function(source, args, raw)
		if not available() then return refuse(source, raw, 'weapons_unavailable') end
		local playerId, code = Server.target(source, args[1])
		if playerId == nil then return refuse(source, raw, code) end
		-- asking an unincarnated client for its loadout is asking the menu puppet
		local admitted, gateCode = Server.admit(playerId)
		if not admitted then
			audit(source, 'admin.weapon.holster', false, playerId, gateCode)
			return refuse(source, raw, gateCode, { id = playerId })
		end
		local requestId, reason = Open77.weapons.holster(playerId)
		if requestId == nil then
			return refuse(source, raw, 'refused', { reason = tostring(reason) })
		end
		pending[tostring(requestId)] = { source = source, raw = raw, playerId = playerId,
			atMs = Server.nowMs() }
	end,
})

Server.command('opx77.admin.weapon.read', {
	help = 'admin.help.loadout', params = { TARGET }, read = true,
	handler = function(source, args, raw)
		local target, who, playerId = resolve(source, raw, args[1])
		if target == nil then return end
		CreateThread(function()
			local event = 'admin.weapon.read'
			local catalog, code, reason = Inventory.catalog()
			if not catalog then return Inventory.fail(source, raw, event, playerId, who, code, reason) end
			local bag, bagCode, bagReason = Inventory.bag(target)
			if not bag then
				return Inventory.fail(source, raw, event, playerId, who, bagCode, bagReason)
			end
			local drawn
			if playerId ~= nil then
				local held = Inventory.call('GetHeldWeapon', playerId)
				local weapon = held and type(held.weapon) == 'table' and held.weapon or nil
				if weapon and weapon.drawn == true and type(weapon.serial) == 'string' then
					drawn = weapon
				end
			end
			local lines = { locale('admin.loadout.header', { who = who }) }
			for _, row in ipairs(bag.items) do
				local entry = catalog.byName[row.name]
				if entry and entry.weapon then
					local metadata = type(row.metadata) == 'table' and row.metadata or {}
					local serial = Text.clean(metadata.serial, 24) or '-'
					local rounds = entry.weapon.ammo and ('  ' .. locale('admin.inventory.rounds',
						{ rounds = Text.integer(metadata.ammo) or 0 })) or ''
					local mark = drawn and metadata.serial == drawn.serial and
						('  ' .. locale('admin.loadout.drawn')) or ''
					lines[#lines + 1] = locale('admin.loadout.row', { slot = row.slot, label = entry.label,
						serial = serial, rounds = rounds, drawn = mark })
				end
			end
			if #lines == 1 then lines[2] = locale('admin.loadout.empty') end
			answer(source, raw, true, 'admin.text.lines', { lines = table.concat(lines, '\n') })
		end)
	end,
})

--- Whether the relay the holster uses exists on this host.
---@return boolean
function Server.weaponsAvailable()
	return available()
end

if not available() then
	Open77.log.warn('Open77.weapons is unavailable on this host: the holster refuses')
end
