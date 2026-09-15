--- @author DemiAutomatic
--- @file server/inventory.lua
--- @description The bridge to opx77_inventory, and the staff bag commands.

local Config = OPX_ADMIN_CONFIG
local Server = OpxAdmin.Server
local Text = OpxAdmin.Text

local answer, refuse, audit, tell = Server.Answer, Server.Refuse, Server.Audit, Server.Tell

--- @author DemiAutomatic
--- @type {table}
--- @description The INVENTORY section of the configuration, or an empty table.
local Settings = type(Config.INVENTORY) == 'table' and Config.INVENTORY or {}

--- @author DemiAutomatic
--- @type {string}
--- @description Name of the inventory resource whose exports are called.
local RESOURCE = type(Settings.RESOURCE) == 'string' and Settings.RESOURCE:match('^[%w_%-%.]+$')
	and Settings.RESOURCE or 'opx77_inventory'

--- @author DemiAutomatic
--- @type {integer}
--- @description Largest count a give or a removal accepts.
local MAX_COUNT = math.max(1, math.floor(Server.Setting(Settings.MAX_COUNT, 10000)))

--- @author DemiAutomatic
--- @type {table}
--- @description The inventory bridge other server files call.
OpxAdmin.Inventory = {}
local Inventory = OpxAdmin.Inventory

--- @author DemiAutomatic
--- @type {string}
--- @description Name of the inventory resource, for the status readout.
Inventory.RESOURCE = RESOURCE

--- @author DemiAutomatic
--- @type {integer}
--- @description Largest count a give or a removal accepts.
Inventory.MAX_COUNT = MAX_COUNT

--- @author DemiAutomatic
--- @type {table<string, boolean>}
--- @description Host reasons meaning the inventory is absent, not refusing.
local UNAVAILABLE = {
	export_not_found = true,
	export_resource_unavailable = true,
	export_resource_stopped = true,
	resource_preparing = true,
	resource_stopping = true,
	export_timeout = true,
	promise_cancelled = true,
	not_running = true,
}

--- @author DemiAutomatic
--- @type {table<string, string>}
--- @description Inventory refusal codes answered in this resource's own words.
local CODES = {
	caller_denied = 'inventory_denied',
	no_room = 'bag_no_room',
	too_heavy = 'bag_too_heavy',
	not_loaded = 'no_character',
	no_character = 'unknown_citizen',
	bad_target = 'bad_holder',
	unknown_item = 'unknown_item',
	not_enough = 'not_enough',
	core_unavailable = 'core_unavailable',
	bad_count = 'bad_count',
}

--- @author DemiAutomatic
--- @method OpxAdmin.Inventory.Running
--- @description Whether the host reports the inventory resource as running.
--- @returns {boolean}
function OpxAdmin.Inventory.Running()
	local read, state = pcall(GetResourceState, RESOURCE)
	return read and state == 'running'
end

--- @author DemiAutomatic
--- @method OpxAdmin.Inventory.Call
--- @description Calls one inventory server export and awaits it, coroutine only.
--- @param name {string}
--- @returns {table|nil, string|nil, string|nil}
function OpxAdmin.Inventory.Call(name, ...)
	if not Inventory.Running() then return nil, 'inventory_unavailable', 'not_running' end
	local exported = Open77.exports
	if type(exported) ~= 'table' or type(exported.call) ~= 'function' then
		return nil, 'inventory_unavailable', 'no_exports'
	end
	local dispatched, promise, reason = pcall(exported.call, RESOURCE, name, ...)
	if not dispatched then return nil, 'refused', Text.Clean(promise, 64) end
	if not promise then
		reason = tostring(reason or 'not_dispatched')
		return nil, UNAVAILABLE[reason] and 'inventory_unavailable' or 'refused', reason
	end
	local result, callError = promise:await()
	if callError then
		callError = tostring(callError)
		return nil, UNAVAILABLE[callError] and 'inventory_unavailable' or 'refused',
			Text.Clean(callError, 64)
	end
	if type(result) ~= 'table' then return nil, 'refused', 'malformed_answer' end
	if result.ok ~= true then
		local code = Text.Clean(result.error, 64) or 'refused'
		return nil, CODES[code] or 'refused', code
	end
	return result, nil, nil
end

--- @author DemiAutomatic
--- @method playerLabel
--- @description Formats a connected player as name and id in brackets.
--- @param playerId {integer}
--- @returns {string}
local function playerLabel(playerId)
	return ('%s [%d]'):format(Server.NameOf(playerId) or '?', playerId)
end

--- @author DemiAutomatic
--- @method OpxAdmin.Inventory.Target
--- @description Resolves a typed holder: me, a player id or a citizen id.
--- @param source {integer}
--- @param token {any}
--- @returns {integer|string|nil, string|nil, integer|nil, string|nil}
function OpxAdmin.Inventory.Target(source, token)
	if token == nil then return nil, nil, nil, 'no_target' end
	local word = tostring(token)
	local lowered = word:lower()
	if lowered == 'me' or lowered == 'self' then
		if source <= 0 then return nil, nil, nil, 'console_has_no_player' end
		return source, playerLabel(source), source, nil
	end
	local playerId = Text.Integer(word)
	if playerId ~= nil then
		if playerId <= 0 then return nil, nil, nil, 'bad_holder' end
		if Server.NameOf(playerId) == nil then return nil, nil, nil, 'not_connected' end
		return playerId, playerLabel(playerId), playerId, nil
	end
	if #word > 32 or not word:match('^[%w_%-]+$') then return nil, nil, nil, 'bad_holder' end
	return word, word, nil, nil
end

--- @author DemiAutomatic
--- @method OpxAdmin.Inventory.Count
--- @description Parses a typed count: one when omitted, else 1..MAX_COUNT.
--- @param token {any}
--- @returns {integer|nil}
function OpxAdmin.Inventory.Count(token)
	if token == nil then return 1 end
	local count = Text.Integer(token)
	if count == nil or count < 1 or count > MAX_COUNT then return nil end
	return count
end

--- @author DemiAutomatic
--- @type {table|nil}
--- @description The inventory catalogue as last read through GetItems.
local cache

--- @author DemiAutomatic
--- @type {integer}
--- @description Longest a cached catalogue is reused, in milliseconds.
local CACHE_MS = 300000

--- @author DemiAutomatic
--- @method forget
--- @description Drops the cached catalogue when the inventory starts or stops.
--- @param name {string}
local function forget(name)
	if name == RESOURCE then cache = nil end
end

--- @author DemiAutomatic
--- @event open77:resource:started
--- @description Forgets the cached catalogue when the inventory starts.
--- @param name {string}
AddEventHandler('open77:resource:started', forget)

--- @author DemiAutomatic
--- @event open77:resource:stopped
--- @description Forgets the cached catalogue when the inventory stops.
--- @param name {string}
AddEventHandler('open77:resource:stopped', forget)

--- @author DemiAutomatic
--- @method OpxAdmin.Inventory.Catalog
--- @description Reads the inventory catalogue page by page, cached, coroutine only.
--- @returns {InventoryCatalog|nil, string|nil, string|nil}
function OpxAdmin.Inventory.Catalog()
	if cache and Server.NowMs() - cache.atMs < CACHE_MS and Inventory.Running() then return cache end
	local items, byName, offset = {}, {}, 0
	for _ = 1, 64 do
		local page, code, reason = Inventory.Call('GetItems', { offset = offset })
		if not page then return nil, code, reason end
		for _, item in ipairs(type(page.items) == 'table' and page.items or {}) do
			local name = type(item) == 'table' and Text.Clean(item.name, 48) or nil
			if name and byName[name] == nil then
				local weapon = type(item.weapon) == 'table' and item.weapon or nil
				local entry = {
					name = name,
					label = Text.Clean(item.label, 48) or name,
					category = Text.Clean(item.category, 32) or 'misc',
					weight = math.max(0, Text.Integer(item.weight) or 0),
					weapon = weapon and {
						class = Text.Clean(weapon.class, 32) or 'other',
						ammo = Text.Clean(weapon.ammo, 48),
					} or nil,
					ammoMax = type(item.ammo) == 'table' and Text.Integer(item.ammo.max) or nil,
				}
				items[#items + 1] = entry
				byName[name] = entry
			end
		end
		local nextOffset = Text.Integer(page.nextOffset)
		if nextOffset == nil or nextOffset <= offset then break end
		offset = nextOffset
	end
	table.sort(items, function(left, right) return left.label < right.label end)
	cache = { items = items, byName = byName, atMs = Server.NowMs() }
	return cache, nil, nil
end

--- @author DemiAutomatic
--- @method OpxAdmin.Inventory.Item
--- @description Finds a catalogue item by its exact name, ignoring case.
--- @param catalog {InventoryCatalog}
--- @param token {any}
--- @returns {InventoryItem|nil}
function OpxAdmin.Inventory.Item(catalog, token)
	if type(token) ~= 'string' then return nil end
	return catalog.byName[token:lower()]
end

--- @author DemiAutomatic
--- @method OpxAdmin.Inventory.Weapon
--- @description Finds a weapon item by name, with or without its prefix.
--- @param catalog {InventoryCatalog}
--- @param token {any}
--- @returns {InventoryItem|nil}
function OpxAdmin.Inventory.Weapon(catalog, token)
	if type(token) ~= 'string' then return nil end
	local lowered = token:lower()
	local entry = catalog.byName[lowered] or catalog.byName['weapon_' .. lowered]
	if entry == nil or entry.weapon == nil then return nil end
	return entry
end

--- @author DemiAutomatic
--- @method OpxAdmin.Inventory.LabelOf
--- @description Labels a stored item, falling back to its name.
--- @param catalog {InventoryCatalog|nil}
--- @param name {string}
--- @returns {string}
function OpxAdmin.Inventory.LabelOf(catalog, name)
	local entry = catalog and catalog.byName[name]
	return entry and entry.label or name
end

--- @author DemiAutomatic
--- @method OpxAdmin.Inventory.Bag
--- @description Reads every stack of a bag, page by page, coroutine only.
--- @param target {integer|string}
--- @returns {InventoryBag|nil, string|nil, string|nil}
function OpxAdmin.Inventory.Bag(target)
	local bag, offset = nil, 0
	for _ = 1, 64 do
		local page, code, reason = Inventory.Call('GetInventory', target, { offset = offset })
		if not page then return nil, code, reason end
		bag = bag or {
			citizenId = Text.Clean(page.citizenId, 32) or '?',
			slots = Text.Integer(page.slots) or 0,
			maxWeight = Text.Integer(page.maxWeight) or 0,
			weight = Text.Integer(page.weight) or 0,
			items = {},
		}
		for _, row in ipairs(type(page.items) == 'table' and page.items or {}) do
			local slot, name = type(row) == 'table' and Text.Integer(row.slot) or nil,
				type(row) == 'table' and Text.Clean(row.name, 48) or nil
			if slot and name then
				bag.items[#bag.items + 1] = {
					slot = slot, name = name, count = Text.Integer(row.count) or 0,
					metadata = type(row.metadata) == 'table' and row.metadata or nil,
				}
			end
		end
		local nextOffset = Text.Integer(page.nextOffset)
		if nextOffset == nil or nextOffset <= offset then break end
		offset = nextOffset
	end
	return bag, nil, nil
end

--- @author DemiAutomatic
--- @method OpxAdmin.Inventory.Fail
--- @description Audits a refused bag action and answers the refusal.
--- @param source {integer}
--- @param raw {string}
--- @param event {string}
--- @param playerId {integer|nil}
--- @param who {string|nil}
--- @param code {string}
--- @param reason {string|nil}
--- @param params {table|nil}
function OpxAdmin.Inventory.Fail(source, raw, event, playerId, who, code, reason, params)
	audit(source, event, false, playerId, ('%s: %s'):format(who or '-', tostring(reason or code)))
	params = params or {}
	params.who = params.who or who or '?'
	params.reason = reason
	params.max = params.max or MAX_COUNT
	refuse(source, raw, code, params)
end

--- @author DemiAutomatic
--- @method OpxAdmin.Inventory.Carry
--- @description Asks CanCarry whether the bag takes those items, coroutine only.
--- @param target {integer|string}
--- @param name {string}
--- @param count {integer}
--- @param metadata {table|nil}
--- @returns {boolean, string|nil, string|nil}
function OpxAdmin.Inventory.Carry(target, name, count, metadata)
	local carry, code, reason = Inventory.Call('CanCarry', target, name, count, metadata)
	if not carry then return false, code, reason end
	if carry.result ~= true then
		return false, carry.reason == 'too_heavy' and 'bag_too_heavy' or 'bag_no_room',
			Text.Clean(carry.reason, 32)
	end
	return true, nil, nil
end

--- @author DemiAutomatic
--- @method OpxAdmin.Inventory.Add
--- @description Runs CanCarry then AddItem without answering, coroutine only.
--- @param target {integer|string}
--- @param name {string}
--- @param count {integer}
--- @param metadata {table|nil}
--- @returns {boolean, string|nil, string|nil}
function OpxAdmin.Inventory.Add(target, name, count, metadata)
	local carried, code, reason = Inventory.Carry(target, name, count, metadata)
	if not carried then return false, code, reason end
	local added, addCode, addReason = Inventory.Call('AddItem', target, name, count, metadata)
	if not added then return false, addCode, addReason end
	return true, nil, nil
end

--- @author DemiAutomatic
--- @method OpxAdmin.Inventory.Give
--- @description Adds items to a bag, answering and auditing a refusal.
--- @param source {integer}
--- @param raw {string}
--- @param event {string}
--- @param target {integer|string}
--- @param who {string}
--- @param playerId {integer|nil}
--- @param name {string}
--- @param count {integer}
--- @param metadata {table|nil}
--- @param label {string}
--- @returns {boolean}
function OpxAdmin.Inventory.Give(source, raw, event, target, who, playerId, name, count, metadata, label)
	local added, code, reason = Inventory.Add(target, name, count, metadata)
	if not added then
		Inventory.Fail(source, raw, event, playerId, who, code, reason, { item = label })
		return false
	end
	return true
end

--- @author DemiAutomatic
--- @type {AdminParameter}
--- @description Suggestion parameter for a holder: player, me or citizen id.
local TARGET = { name = 'playerId|me|citizenId', help = 'admin.help.holder' }

--- @author DemiAutomatic
--- @type {AdminParameter}
--- @description Suggestion parameter for an item name.
local ITEM = { name = 'item', help = 'admin.help.itemName' }

--- @author DemiAutomatic
--- @type {AdminParameter}
--- @description Suggestion parameter for an optional item count.
local COUNT = { name = 'count', help = 'admin.help.count', optional = true }

--- @author DemiAutomatic
--- @method resolve
--- @description Answers the refusals that need no export call.
--- @param source {integer}
--- @param raw {string}
--- @param token {any}
--- @returns {integer|string|nil, string|nil, integer|nil}
local function resolve(source, raw, token)
	local target, who, playerId, code = Inventory.Target(source, token)
	if target == nil then
		refuse(source, raw, code)
		return nil
	end
	if not Inventory.Running() then
		refuse(source, raw, 'inventory_unavailable')
		return nil
	end
	return target, who, playerId
end

--- @author DemiAutomatic
--- @method extraOf
--- @description Formats a stack's rounds and serial for a report row.
--- @param metadata {table|nil}
--- @returns {string}
local function extraOf(metadata)
	if type(metadata) ~= 'table' then return '' end
	local parts = {}
	local ammo = Text.Integer(metadata.ammo)
	if ammo then parts[#parts + 1] = locale('admin.inventory.rounds', { rounds = ammo }) end
	local serial = Text.Clean(metadata.serial, 24)
	if serial then parts[#parts + 1] = '#' .. serial end
	return #parts > 0 and ('  ' .. table.concat(parts, '  ')) or ''
end

--- @author DemiAutomatic
--- @method kilograms
--- @description Formats grams as kilograms with one decimal.
--- @param grams {integer}
--- @returns {string}
local function kilograms(grams)
	return ('%.1f'):format(grams / 1000)
end

--- @author DemiAutomatic
--- @command /opx77.admin.inventory.view
--- @description Lists every stack of a bag as a chat report.
Server.Command('opx77.admin.inventory.view', {
	help = 'admin.help.invView', params = { TARGET }, read = true,
	handler = function(source, args, raw)
		local target, who, playerId = resolve(source, raw, args[1])
		if target == nil then return end
		CreateThread(function()
			local bag, code, reason = Inventory.Bag(target)
			if not bag then
				return Inventory.Fail(source, raw, 'admin.inventory.view', playerId, who, code, reason)
			end
			local catalog = Inventory.Catalog()
			local lines = { locale('admin.inventory.header', {
				who = who, citizenId = bag.citizenId, used = #bag.items, slots = bag.slots,
				weight = kilograms(bag.weight), maxWeight = kilograms(bag.maxWeight),
			}) }
			for _, row in ipairs(bag.items) do
				lines[#lines + 1] = locale('admin.inventory.row', {
					slot = row.slot, label = Inventory.LabelOf(catalog, row.name), name = row.name,
					count = row.count, extra = extraOf(row.metadata),
				})
			end
			if #bag.items == 0 then lines[#lines + 1] = locale('admin.inventory.empty') end
			audit(source, 'admin.inventory.view', true, playerId, bag.citizenId)
			answer(source, raw, true, 'admin.text.lines', { lines = table.concat(lines, '\n') })
		end)
	end,
})

--- @author DemiAutomatic
--- @command /opx77.admin.inventory.give
--- @description Adds catalogue items to a bag.
Server.Command('opx77.admin.inventory.give', {
	help = 'admin.help.invGive', params = { TARGET, ITEM, COUNT },
	handler = function(source, args, raw)
		if Text.Clean(args[2], 48) == nil then
			return refuse(source, raw, 'unknown_item', { item = '?' })
		end
		local count = Inventory.Count(args[3])
		if count == nil then return refuse(source, raw, 'bad_count', { max = MAX_COUNT }) end
		local target, who, playerId = resolve(source, raw, args[1])
		if target == nil then return end
		CreateThread(function()
			local event = 'admin.inventory.give'
			local catalog, code, reason = Inventory.Catalog()
			if not catalog then return Inventory.Fail(source, raw, event, playerId, who, code, reason) end
			local item = Inventory.Item(catalog, args[2])
			if item == nil then
				return Inventory.Fail(source, raw, event, playerId, who, 'unknown_item',
					Text.Clean(args[2], 48), { item = Text.Clean(args[2], 48) })
			end
			if not Inventory.Give(source, raw, event, target, who, playerId, item.name, count, nil,
				item.label) then
				return
			end
			audit(source, event, true, playerId, ('%dx %s to %s'):format(count, item.name, who))
			if playerId and playerId ~= source then
				tell(playerId, 'admin.toast.itemGiven', { count = count, label = item.label }, 'info')
			end
			answer(source, raw, true, 'admin.done.itemGiven',
				{ count = count, label = item.label, who = who })
		end)
	end,
})

--- @author DemiAutomatic
--- @command /opx77.admin.inventory.remove
--- @description Takes items out of a bag by name and count.
Server.Command('opx77.admin.inventory.remove', {
	help = 'admin.help.invRemove', params = { TARGET, ITEM, COUNT },
	handler = function(source, args, raw)
		local name = type(args[2]) == 'string' and args[2]:lower() or nil
		if name == nil or #name > 48 or not name:match('^[%w_%-%.]+$') then
			return refuse(source, raw, 'unknown_item', { item = Text.Clean(args[2], 48) or '?' })
		end
		local count = Inventory.Count(args[3])
		if count == nil then return refuse(source, raw, 'bad_count', { max = MAX_COUNT }) end
		local target, who, playerId = resolve(source, raw, args[1])
		if target == nil then return end
		CreateThread(function()
			local event = 'admin.inventory.remove'
			local label = Inventory.LabelOf(Inventory.Catalog(), name)
			local removed, code, reason = Inventory.Call('RemoveItem', target, name, count)
			if not removed then
				return Inventory.Fail(source, raw, event, playerId, who, code, reason,
					{ item = label, count = count })
			end
			audit(source, event, true, playerId, ('%dx %s from %s'):format(count, name, who))
			if playerId and playerId ~= source then
				tell(playerId, 'admin.toast.itemTaken', { count = count, label = label }, 'warning')
			end
			answer(source, raw, true, 'admin.done.itemRemoved',
				{ count = count, label = label, who = who })
		end)
	end,
})

--- @author DemiAutomatic
--- @command /opx77.admin.inventory.clear
--- @description Empties every stack out of a bag.
Server.Command('opx77.admin.inventory.clear', {
	help = 'admin.help.invClear', params = { TARGET },
	handler = function(source, args, raw)
		local target, who, playerId = resolve(source, raw, args[1])
		if target == nil then return end
		CreateThread(function()
			local event = 'admin.inventory.clear'
			local cleared, code, reason = Inventory.Call('ClearInventory', target)
			if not cleared then
				return Inventory.Fail(source, raw, event, playerId, who, code, reason)
			end
			audit(source, event, true, playerId, who)
			if playerId and playerId ~= source then
				tell(playerId, 'admin.toast.bagCleared', nil, 'warning')
			end
			answer(source, raw, true, 'admin.done.bagCleared', { who = who })
		end)
	end,
})

CreateThread(function()
	Wait(5000)
	if not Inventory.Running() then
		Open77.log.warn(('%s is not running: the weapon and inventory commands refuse until it is')
			:format(RESOURCE))
	end
end)
