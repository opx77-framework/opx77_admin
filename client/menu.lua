--- The staff menu, drawn by opx77_menu. Every row that does something is a command line sent
--- through Client.Execute, so the host resolves the ACL for it exactly as for a typed command.
--- The access map the server sends only greys out what would be refused; it decides nothing.
---
--- Each screen is its own opx77_menu `open`, not a submenu of one big tree: opx77_menu refuses a
--- spec past 400 rows across the whole tree, and a roster of thirty players with twenty actions
--- each is past it. The stack of screens is kept here instead.

OpxAdmin = OpxAdmin or {}

local Config = OPX_ADMIN_CONFIG
local Client = OpxAdmin.Client
local Catalog = OpxAdmin.Catalog
local Forms = OpxAdmin.Forms
local Keys = OpxAdmin.Keys

OpxAdmin.Menu = {}
local Menu = OpxAdmin.Menu

local MENU = 'opx77_menu'
local EVENT = 'opx77_admin:row'
local LINKS = type(Config.LINKS) == 'table' and Config.LINKS or {}

--- The mapping that opens and closes the menu, and the command it sends. The id is stable: a
--- player's rebind is stored under it.
local KEY_MENU = 'opx77_admin.menu'
local OPENER = 'opx77.admin'

--- opx77_menu refuses a level past 200 rows; the navigation rows need room.
local MAX_LISTED = 190

--- Rows a catalogue list draws at once; a longer list is drawn a page at a time. opx77_menu
--- checks every row of a spec in one handler, at a few hundred VM instructions a row, and the
--- host stops a client handler once it runs past 10 000 of them.
local PAGE_ROWS = 20

--- What the server said at open: `you`, `access`, `aclKnown`, `weapons`, `inventory`.
---@type table|nil
local session

local roster, rosterById, incoming = {}, {}, {}
local locations = {}

--- opx77_inventory's catalogue as the server read it: `{ name, label, category, class, max }`,
--- and whether it has arrived. Weapons are the rows with a class, ammunition the `ammo` category
--- with its full load in `max`.
local catalog = { rows = {}, incoming = {}, loaded = false, error = nil }

--- The stacks of the one bag the remove picker is drawing, by the target the server was asked.
local bag = { target = nil, rows = {}, incoming = {}, loaded = false, error = nil }

--- { screen, arg, cursor } from the root down.
local stack = {}

--- The open menu's handle, and whether it was taken down on purpose to put a form up.
local handle
local suspended = false

--- A status line to write when the next screen opens.
local queuedStatus

--- Bumped by every draw, so a slow `open` that lost the race does not claim the handle.
local drawn = 0

-- ---------------------------------------------------------------------------
-- Rows
-- ---------------------------------------------------------------------------

--- Whether the ACL grants a command, as far as the server could tell. Without an ACL reader on
--- the host every row is drawn enabled and the host answers for each one.
---@param name any
---@return boolean
local function permitted(name)
	if session == nil or type(name) ~= 'string' or name == '' then return false end
	if not session.aclKnown then return true end
	return session.access[name] == true
end

--- A catalogue key, or `{ text = ... }` for words that are data rather than this resource's.
---@param label string|table
---@return string
local function text(label)
	if type(label) == 'table' then return tostring(label.text) end
	return locale(label)
end

---@param id string
---@param label string
---@param data table|nil
---@param extra table|nil
---@return table
local function row(id, label, data, extra)
	local item = { id = id, label = label, data = data }
	for key, value in pairs(extra or {}) do item[key] = value end
	return item
end

--- A row that runs a command line. Greyed, with the reason beside it, when the ACL refuses it.
---@param id string
---@param label string|table
---@param tokens table
---@param refresh string|nil  roster | locations: what to ask for again after it ran
---@param extra table|nil
local function command(id, label, tokens, refresh, extra)
	local item = row(id, text(label), { run = tokens, refresh = refresh }, extra)
	if not permitted(tokens[1]) then
		item.disabled = true
		item.value = locale('admin.menu.denied')
	end
	return item
end

--- A row that asks before it runs: kill, kick, ban and anything that reaches everybody.
local function guarded(id, labelKey, tokens, confirmKey)
	local item = command(id, labelKey, tokens)
	item.data = { confirm = tokens, key = confirmKey }
	return item
end

--- A row that opens a form. `name` is the command the form ends in, for the grey-out.
local function form(id, labelKey, kind, arg, name)
	local item = row(id, locale(labelKey), { form = kind, arg = arg })
	if not permitted(name) then
		item.disabled = true
		item.value = locale('admin.menu.denied')
	end
	return item
end

---@param id string
---@param label string|table
---@param screen string
---@param arg any
---@param extra table|nil
local function go(id, label, screen, arg, extra)
	return row(id, text(label), { go = screen, arg = arg }, extra)
end

--- One page of a catalogue list: the rows `build` makes for it, then a row to the next page
--- when there is one. `arg` is the screen's argument, its page in `p`; the title gains the page.
---@param list table[]
---@param screen string
---@param arg table
---@param title string
---@param build fun(entry: table): table
---@return string title, table[] items
local function paged(list, screen, arg, title, build)
	local pages = math.max(1, math.ceil(#list / PAGE_ROWS))
	local page = math.min(math.max(math.floor(tonumber(arg.p) or 1), 1), pages)
	local first = (page - 1) * PAGE_ROWS + 1
	local items = {}
	for index = first, math.min(#list, first + PAGE_ROWS - 1) do
		items[#items + 1] = build(list[index])
	end
	if page < pages then
		local following = {}
		for key, value in pairs(arg) do following[key] = value end
		following.p = page + 1
		items[#items + 1] = go('more', 'admin.menu.more', screen, following,
			{ value = ('%d/%d'):format(page + 1, pages) })
	end
	if pages > 1 then title = ('%s %d/%d'):format(title, page, pages) end
	return title, items
end

---@param labelKey string|nil
local function section(labelKey)
	return { separator = true, label = labelKey and locale(labelKey) or nil }
end

--- Whether the server could reach opx77_inventory when the menu opened or last refreshed.
---@return boolean
local function inventoryUp()
	return session ~= nil and session.inventory == true
end

--- A row greyed with a word beside it, for what cannot be done here at all.
---@param item table
---@param key string
---@return table
local function unavailable(item, key)
	item.disabled, item.value = true, locale(key or 'admin.menu.unavailable')
	return item
end

--- A row that goes to a picker, greyed when the ACL refuses the command the picker ends in.
local function goFor(id, labelKey, screen, arg, name)
	local item = go(id, labelKey, screen, arg)
	if not permitted(name) then unavailable(item, 'admin.menu.denied') end
	return item
end

--- The one row a picker shows while its list is on its way, or when it cannot be had.
---@param list table  `catalog` or `bag`
---@param emptyKey string
---@return table
local function placeholder(list, emptyKey)
	local key = not list.loaded and 'admin.menu.loading' or list.error and 'admin.menu.inventoryError'
		or emptyKey
	return row('empty', locale(key), nil, { disabled = true })
end

--- The weapon rows for a target, "me" or a player id. A weapon and its ammunition are
--- opx77_inventory items, so every row but the holster needs that resource; the holster needs
--- the platform's weapon relay.
---@param target string
---@param giveKey string
---@return table[]
local function weaponRows(target, giveKey)
	local items = {
		goFor('giveWeapon', giveKey, 'weaponClasses', target, 'opx77.admin.weapon.give'),
		goFor('giveAmmo', 'admin.menu.giveAmmo', 'ammoList', target, 'opx77.admin.weapon.giveammo'),
		command('ammo', 'admin.menu.ammo', { 'opx77.admin.weapon.ammo', target }),
		command('holster', 'admin.menu.holster', { 'opx77.admin.weapon.holster', target }),
		guarded('disarm', 'admin.menu.disarm', { 'opx77.admin.weapon.remove', target, 'all' },
			'admin.confirm.disarm'),
		command('loadout', 'admin.menu.loadout', { 'opx77.admin.weapon.read', target }),
	}
	for _, item in ipairs(items) do
		local relay = item.id == 'holster'
		if not item.disabled and ((relay and not (session and session.weapons)) or
			(not relay and not inventoryUp())) then
			unavailable(item)
		end
	end
	return items
end

--- The name of a roster player, for a title.
---@param id integer
---@return string
local function nameOf(id)
	local entry = rosterById[id]
	return entry and ('%s [%d]'):format(entry.name, id) or ('[%s]'):format(tostring(id))
end

-- ---------------------------------------------------------------------------
-- Screens: each answers a title and its rows
-- ---------------------------------------------------------------------------

local SCREENS = {}

SCREENS.root = function()
	return locale('admin.menu.title'), {
		go('players', 'admin.menu.players', 'players', nil, { value = tostring(#roster) }),
		go('self', 'admin.menu.self', 'self'),
		go('vehicles', 'admin.menu.vehicles', 'vehicles'),
		go('weapons', 'admin.menu.weapons', 'weapons'),
		go('world', 'admin.menu.world', 'world'),
		go('server', 'admin.menu.server', 'server'),
	}
end

SCREENS.players = function()
	local items = {}
	for index = 1, math.min(#roster, MAX_LISTED) do
		local entry = roster[index]
		local value = locale('admin.state.' .. entry.state)
		if entry.bucket ~= 0 then value = value .. ' b' .. entry.bucket end
		if entry.distance then value = value .. ' ' .. entry.distance .. 'm' end
		items[#items + 1] = go('player_' .. entry.id,
			{ text = ('[%d] %s'):format(entry.id, entry.name) }, 'player', entry.id, { value = value })
	end
	if #items == 0 then
		items[1] = row('empty', locale('admin.menu.nobody'), nil, { disabled = true })
	end
	return locale('admin.menu.players'), items
end

SCREENS.player = function(id)
	local target = tostring(id)
	local items = {
		section('admin.menu.section.movement'),
		command('goto', 'admin.menu.goto', { 'opx77.admin.player.goto', target }),
		command('bring', 'admin.menu.bring', { 'opx77.admin.player.bring', target }, 'roster'),
		go('send', 'admin.menu.send', 'locations', id),
		form('coords', 'admin.menu.coords', 'coords', id, 'opx77.admin.player.tp'),
		command('observe', 'admin.menu.observe', { 'opx77.admin.player.observe', target }),

		section('admin.menu.section.health'),
		command('heal', 'admin.menu.heal', { 'opx77.admin.player.heal', target }, 'roster'),
		command('revive', 'admin.menu.revive', { 'opx77.admin.player.revive', target }, 'roster'),
		command('god', 'admin.menu.god', { 'opx77.admin.player.god', target }),
		form('health', 'admin.menu.health', 'health', id, 'opx77.admin.player.health'),
		form('armor', 'admin.menu.armor', 'armor', id, 'opx77.admin.player.armor'),
		guarded('kill', 'admin.menu.kill', { 'opx77.admin.player.kill', target }, 'admin.confirm.kill'),
	}

	if Client.Running('opx77_core') then
		items[#items + 1] = section('admin.menu.section.character')
		if LINKS.WHERE then
			items[#items + 1] = command('record', 'admin.menu.record', { LINKS.WHERE, target })
		end
		if LINKS.JOB then
			items[#items + 1] = form('job', 'admin.menu.job', 'job', id, LINKS.JOB)
		end
		if LINKS.GANG then
			items[#items + 1] = form('gang', 'admin.menu.gang', 'gang', id, LINKS.GANG)
		end
		if LINKS.MONEY then
			items[#items + 1] = form('money', 'admin.menu.money', 'money', id, LINKS.MONEY)
		end
	end

	items[#items + 1] = section('admin.menu.section.items')
	items[#items + 1] = go('giveVehicle', 'admin.menu.giveVehicle', 'vehicleClasses', id)
	for _, item in ipairs(weaponRows(target, 'admin.menu.giveWeapon')) do items[#items + 1] = item end

	if inventoryUp() then
		items[#items + 1] = section('admin.menu.section.inventory')
		items[#items + 1] = command('invView', 'admin.menu.invView',
			{ 'opx77.admin.inventory.view', target })
		if LINKS.INVENTORY_OPEN then
			-- the inventory's screen takes the keyboard: the menu steps aside rather than sit under it
			items[#items + 1] = command('invOpen', 'admin.menu.invOpen', { LINKS.INVENTORY_OPEN, target })
			items[#items].data.closeAfter = true
		end
		items[#items + 1] = goFor('invGive', 'admin.menu.invGive', 'itemCategories',
			{ t = target, m = 'give' }, 'opx77.admin.inventory.give')
		items[#items + 1] = goFor('invRemove', 'admin.menu.invRemove', 'bag', target,
			'opx77.admin.inventory.remove')
		items[#items + 1] = guarded('invClear', 'admin.menu.invClear',
			{ 'opx77.admin.inventory.clear', target }, 'admin.confirm.invClear')
	end

	items[#items + 1] = section('admin.menu.section.moderation')
	items[#items + 1] = form('kick', 'admin.menu.kick', 'kick', id, 'opx77.admin.moderate.kick')
	items[#items + 1] = form('ban', 'admin.menu.ban', 'ban', id, 'opx77.admin.moderate.ban')
	return nameOf(id), items
end

SCREENS.self = function()
	return locale('admin.menu.self'), {
		command('noclip', 'admin.menu.noclip', { 'opx77.admin.self.noclip' }),
		command('maptravel', 'admin.menu.maptravel', { 'opx77.admin.self.maptravel' }),
		command('god', 'admin.menu.god', { 'opx77.admin.self.god' }),
		command('heal', 'admin.menu.heal', { 'opx77.admin.self.heal' }),
		command('revive', 'admin.menu.revive', { 'opx77.admin.self.revive' }),
		section(),
		go('teleport', 'admin.menu.teleport', 'locations', 'me'),
		form('coords', 'admin.menu.coords', 'coords', 'me', 'opx77.admin.player.tp'),
		command('pos', 'admin.menu.pos', { 'opx77.admin.self.pos' }),
	}
end

SCREENS.vehicles = function()
	local items = {
		go('spawn', 'admin.menu.spawn', 'vehicleClasses', 'me'),
		section('admin.menu.section.nearest'),
		command('repair', 'admin.menu.repair', { 'opx77.admin.vehicle.repair', 'near', 'full' }),
		command('repairVisual', 'admin.menu.repairVisual',
			{ 'opx77.admin.vehicle.repair', 'near', 'visual' }),
	}
	local flags = type((Config.VEHICLES or {}).FLAGS) == 'table' and Config.VEHICLES.FLAGS or {}
	for _, flag in ipairs(flags) do
		if type(flag) == 'string' and flag:match('^[%w_]+$') then
			items[#items + 1] = command('flag_' .. flag,
				{ text = locale('admin.menu.flag', { flag = flag }) },
				{ 'opx77.admin.vehicle.flag', 'near', flag })
		end
	end
	items[#items + 1] = command('remove', 'admin.menu.remove',
		{ 'opx77.admin.vehicle.remove', 'near' })
	items[#items + 1] = section()
	items[#items + 1] = command('removeMine', 'admin.menu.removeMine',
		{ 'opx77.admin.vehicle.remove', 'mine' })
	items[#items + 1] = guarded('cleanup', 'admin.menu.cleanup', { 'opx77.admin.vehicle.cleanup' },
		'admin.confirm.cleanup')
	return locale('admin.menu.vehicles'), items
end

---@param titleKey string
---@param target any  "me", or a player id
---@return string
local function titleFor(titleKey, target)
	if target == nil or target == 'me' then return locale(titleKey) end
	return ('%s: %s'):format(locale(titleKey), nameOf(tonumber(target) or target))
end

SCREENS.vehicleClasses = function(target)
	local items = {}
	for _, class in ipairs(Catalog.vehicleClasses) do
		if #class.members > 0 then
			items[#items + 1] = go('class_' .. class.key, { text = class.label }, 'vehicleList',
				{ t = target, c = class.key }, { value = tostring(#class.members) })
		end
	end
	if #items == 0 then items[1] = row('empty', locale('admin.menu.catalogEmpty'), nil,
		{ disabled = true }) end
	return titleFor('admin.menu.vehicles', target), items
end

--- The rows of one class, each a spawn for the operator or a delivery to a player.
SCREENS.vehicleList = function(arg)
	local target = type(arg) == 'table' and arg.t or 'me'
	local found
	for _, class in ipairs(Catalog.vehicleClasses) do
		if type(arg) == 'table' and class.key == arg.c then found = class end
	end
	local title, items = paged(found and found.members or {}, 'vehicleList',
		type(arg) == 'table' and arg or {}, found and found.label or '?', function(entry)
			local tokens = target == 'me' and { 'opx77.admin.vehicle.spawn', entry.name }
				or { 'opx77.admin.vehicle.give', tostring(target), entry.name }
			return command('entry_' .. entry.name, { text = entry.label }, tokens)
		end)
	if #items == 0 then items[1] = row('empty', locale('admin.menu.catalogEmpty'), nil,
		{ disabled = true }) end
	return title, items
end

--- The weapon items of opx77_inventory's catalogue by class: the classes of data/weapons.lua in
--- their order, then any class that file does not name, under its key.
---@return { key: string, label: string, members: table[] }[]
local function weaponGroups()
	local groups, byKey = {}, {}
	for _, class in ipairs(Catalog.weaponClasses) do
		byKey[class.key] = { key = class.key, label = class.label, members = {} }
		groups[#groups + 1] = byKey[class.key]
	end
	for _, entry in ipairs(catalog.rows) do
		if entry.class then
			if byKey[entry.class] == nil then
				byKey[entry.class] = { key = entry.class, label = entry.class, members = {} }
				groups[#groups + 1] = byKey[entry.class]
			end
			local members = byKey[entry.class].members
			members[#members + 1] = entry
		end
	end
	return groups, byKey
end

SCREENS.weaponClasses = function(target)
	local items = {}
	for _, group in ipairs(weaponGroups()) do
		if #group.members > 0 then
			items[#items + 1] = go('class_' .. group.key, { text = group.label }, 'weaponList',
				{ t = target, c = group.key }, { value = tostring(#group.members) })
		end
	end
	if #items == 0 then items[1] = placeholder(catalog, 'admin.menu.catalogEmpty') end
	return titleFor('admin.menu.weapons', target), items
end

--- A weapon row gives it empty: its ammunition is the next picker's.
SCREENS.weaponList = function(arg)
	local target = type(arg) == 'table' and tostring(arg.t) or 'me'
	local _, byKey = weaponGroups()
	local group = type(arg) == 'table' and byKey[arg.c] or nil
	local title, items = paged(group and group.members or {}, 'weaponList',
		type(arg) == 'table' and arg or {}, group and group.label or '?', function(entry)
			local item = command('entry_' .. entry.name, { text = entry.label },
				{ 'opx77.admin.weapon.give', target, entry.name })
			if not item.disabled and not inventoryUp() then unavailable(item) end
			return item
		end)
	if #items == 0 then items[1] = placeholder(catalog, 'admin.menu.catalogEmpty') end
	return title, items
end

--- The ammunition items of opx77_inventory's catalogue, each opening the count form of a give.
SCREENS.ammoList = function(target)
	local items = {}
	for _, entry in ipairs(catalog.rows) do
		if entry.category == 'ammo' and #items < MAX_LISTED then
			local item = form('ammo_' .. entry.name, 'admin.menu.giveAmmo', 'ammoGive',
				{ t = tostring(target), n = entry.name, l = entry.label, x = entry.max },
				'opx77.admin.weapon.giveammo')
			item.label = entry.label
			item.description = entry.name
			if not item.disabled and not inventoryUp() then unavailable(item) end
			items[#items + 1] = item
		end
	end
	if #items == 0 then items[1] = placeholder(catalog, 'admin.menu.catalogEmpty') end
	return titleFor('admin.menu.giveAmmo', target), items
end

SCREENS.weapons = function()
	return locale('admin.menu.weapons'), weaponRows('me', 'admin.menu.giveMe')
end

--- The categories of opx77_inventory's catalogue, sorted, for a give (`m = "give"`, to `t`) or
--- for the holders list (`m = "holders"`).
SCREENS.itemCategories = function(arg)
	local counts, names = {}, {}
	for _, entry in ipairs(catalog.rows) do
		if counts[entry.category] == nil then names[#names + 1] = entry.category end
		counts[entry.category] = (counts[entry.category] or 0) + 1
	end
	table.sort(names)
	local items = {}
	for _, name in ipairs(names) do
		items[#items + 1] = go('cat_' .. name, { text = name }, 'itemList',
			{ t = arg.t, m = arg.m, c = name }, { value = tostring(counts[name]) })
	end
	if #items == 0 then items[1] = placeholder(catalog, 'admin.menu.catalogEmpty') end
	local titleKey = arg.m == 'holders' and 'admin.menu.invHolders' or 'admin.menu.invGive'
	return titleFor(titleKey, arg.t), items
end

SCREENS.itemList = function(arg)
	local matching = {}
	for _, entry in ipairs(catalog.rows) do
		if entry.category == arg.c then matching[#matching + 1] = entry end
	end
	local title, items = paged(matching, 'itemList', arg, arg.c, function(entry)
		local item
		if arg.m == 'holders' then
			item = command('item_' .. entry.name, { text = entry.label },
				{ LINKS.INVENTORY_HOLDERS, entry.name })
		else
			item = form('item_' .. entry.name, 'admin.menu.invGive', 'itemGive',
				{ t = arg.t, n = entry.name, l = entry.label }, 'opx77.admin.inventory.give')
			item.label = entry.label
		end
		item.description = entry.name
		return item
	end)
	if #items == 0 then items[1] = placeholder(catalog, 'admin.menu.catalogEmpty') end
	return title, items
end

--- One bag's stacks, each opening the count form of a removal.
SCREENS.bag = function(target)
	local items = {}
	if bag.target == tostring(target) then
		for _, entry in ipairs(bag.rows) do
			if #items >= MAX_LISTED then break end
			local item = form(('slot_%d'):format(entry.slot), 'admin.menu.invRemove', 'itemRemove',
				{ t = tostring(target), n = entry.name, l = entry.label, c = entry.count },
				'opx77.admin.inventory.remove')
			item.label = ('%d  %s'):format(entry.slot, entry.label)
			if not item.disabled then item.value = 'x' .. tostring(entry.count) end
			item.description = entry.name
			items[#items + 1] = item
		end
	end
	if #items == 0 then
		items[1] = placeholder(bag.target == tostring(target) and bag or { loaded = false },
			'admin.menu.bagEmpty')
	end
	return titleFor('admin.menu.invRemove', target), items
end

SCREENS.locations = function(target)
	local items = {}
	for index = 1, math.min(#locations, MAX_LISTED) do
		local entry = locations[index]
		local item = command('loc_' .. entry.name, { text = entry.label },
			{ 'opx77.admin.player.send', tostring(target), entry.name })
		if not item.disabled and entry.runtime then item.value = locale('admin.menu.runtime') end
		items[#items + 1] = item
	end
	if #items == 0 then items[1] = row('empty', locale('admin.menu.noLocations'), nil,
		{ disabled = true }) end
	local title = target == 'me' and locale('admin.menu.teleport')
		or ('%s: %s'):format(locale('admin.menu.send'), nameOf(target))
	return title, items
end

SCREENS.saved = function()
	local items = {}
	for _, entry in ipairs(locations) do
		if entry.runtime then
			items[#items + 1] = command('forget_' .. entry.name,
				{ text = locale('admin.menu.forget', { label = entry.label }) },
				{ 'opx77.admin.world.loc.remove', entry.name }, 'locations')
		end
	end
	if #items == 0 then items[1] = row('empty', locale('admin.menu.noSaved'), nil,
		{ disabled = true }) end
	return locale('admin.menu.saved'), items
end

SCREENS.world = function()
	local items = {
		form('announce', 'admin.menu.announce', 'announce', nil, 'opx77.admin.world.announce'),
		section('admin.menu.section.locations'),
		go('teleport', 'admin.menu.teleport', 'locations', 'me'),
		form('save', 'admin.menu.saveHere', 'location', nil, 'opx77.admin.world.loc.add'),
		go('saved', 'admin.menu.saved', 'saved'),
	}
	if Client.Running('opx77_weather') then
		items[#items + 1] = section('admin.menu.section.sky')
		items[#items + 1] = go('weather', 'admin.menu.weather', 'weather')
		items[#items + 1] = go('time', 'admin.menu.time', 'time')
	end
	return locale('admin.menu.world'), items
end

SCREENS.weather = function()
	local items = {}
	if LINKS.WEATHER_SET then
		for _, preset in ipairs(type(Config.WEATHER_PRESETS) == 'table' and Config.WEATHER_PRESETS
			or {}) do
			if type(preset) == 'string' and preset:match('^[%w_%-]+$') then
				items[#items + 1] = command('preset_' .. preset, { text = preset },
					{ LINKS.WEATHER_SET, preset })
			end
		end
	end
	items[#items + 1] = section()
	if LINKS.WEATHER_NEXT then
		items[#items + 1] = command('next', 'admin.menu.weatherNext', { LINKS.WEATHER_NEXT })
	end
	if LINKS.WEATHER_FREEZE then
		items[#items + 1] = command('hold', 'admin.menu.weatherHold', { LINKS.WEATHER_FREEZE, 'on' })
		items[#items + 1] = command('release', 'admin.menu.weatherRelease',
			{ LINKS.WEATHER_FREEZE, 'off' })
	end
	return locale('admin.menu.weather'), items
end

SCREENS.time = function()
	local items = {}
	if LINKS.TIME then
		for _, clock in ipairs(type(Config.TIMES) == 'table' and Config.TIMES or {}) do
			if type(clock) == 'string' and clock:match('^%d%d?:%d%d$') then
				items[#items + 1] = command('at_' .. (clock:gsub(':', '_')), { text = clock },
					{ LINKS.TIME, clock })
			end
		end
		items[#items + 1] = form('custom', 'admin.menu.timeCustom', 'time', nil, LINKS.TIME)
	end
	items[#items + 1] = section()
	if LINKS.TIME_FREEZE then
		items[#items + 1] = command('hold', 'admin.menu.clockHold', { LINKS.TIME_FREEZE, 'on' })
		items[#items + 1] = command('release', 'admin.menu.clockRelease', { LINKS.TIME_FREEZE, 'off' })
	end
	return locale('admin.menu.time'), items
end

SCREENS.server = function()
	local items = {
		command('status', 'admin.menu.status', { 'opx77.admin.read.status' }),
		command('list', 'admin.menu.playerList', { 'opx77.admin.read.players' }),
		command('audit', 'admin.menu.audit', { 'opx77.admin.read.audit' }),
		command('locations', 'admin.menu.locationList', { 'opx77.admin.read.locations' }),
	}
	if Client.Running('opx77_core') then
		items[#items + 1] = section('admin.menu.section.characters')
		if LINKS.CHARACTERS then
			items[#items + 1] = command('characters', 'admin.menu.characters', { LINKS.CHARACTERS })
		end
		if LINKS.SAVE then
			items[#items + 1] = guarded('save', 'admin.menu.saveAll', { LINKS.SAVE },
				'admin.confirm.save')
		end
	end
	if inventoryUp() and LINKS.INVENTORY_HOLDERS then
		items[#items + 1] = section('admin.menu.section.inventory')
		items[#items + 1] = goFor('holders', 'admin.menu.invHolders', 'itemCategories',
			{ m = 'holders' }, LINKS.INVENTORY_HOLDERS)
	end
	return locale('admin.menu.server'), items
end

SCREENS.confirm = function(arg)
	return locale(arg.key), {
		row('cancel', locale('admin.menu.cancel'), { back = true }),
		row('confirm', locale('admin.menu.confirm'), { confirmed = true },
			{ description = table.concat(arg.tokens, ' ') }),
	}
end

-- ---------------------------------------------------------------------------
-- Drawing
-- ---------------------------------------------------------------------------

---@return table|nil
local function top()
	return stack[#stack]
end

--- Put the top screen up. `inPlace` rebuilds the open one without moving the cursor.
---@param inPlace boolean|nil
local function draw(inPlace)
	local current = top()
	if current == nil or suspended then return end
	local builder = SCREENS[current.screen]
	if builder == nil then return end
	local title, items = builder(current.arg)
	if current.screen == 'confirm' then
		-- Cancel is already the first row: a Back under it would be a second way to say no
	elseif #stack > 1 then
		items[#items + 1] = section()
		items[#items + 1] = row('back', locale('admin.menu.back'), { back = true })
	else
		items[#items + 1] = section()
		local key = Keys.Effective(KEY_MENU)
		items[#items + 1] = { id = 'close', label = locale('admin.menu.close'), close = true,
			description = key and locale('admin.menu.closeKey', { key = key }) or nil }
	end

	drawn = drawn + 1
	local mine = drawn
	local status = queuedStatus
	queuedStatus = nil
	CreateThread(function()
		if inPlace and handle ~= nil then
			local _, reason = Client.Call(MENU, 'update', handle, { title = title, items = items })
			if reason == nil then return end
		end
		local opened, reason = Client.Call(MENU, 'open', {
			id = 'opx77_admin.' .. current.screen,
			title = title,
			event = EVENT,
			cursor = current.cursor,
			status = status and status.text or nil,
			items = items,
		})
		if mine ~= drawn then return end
		if opened == nil then
			handle = nil
			Open77.log.warn(('menu %s did not open: %s'):format(current.screen, tostring(reason)))
			if reason == 'menu_busy' then Client.Toast('admin.client.menuBusy', nil, 'warning') end
			return
		end
		handle = opened.handle
		if status and status.ok == false then
			Client.Call(MENU, 'setStatus', status.text, false)
		end
	end)
end

---@param screen string
---@param arg any
local function push(screen, arg)
	stack[#stack + 1] = { screen = screen, arg = arg }
	-- leaving the root: a grant added or removed with acl.reload shows without reopening
	if #stack == 2 then TriggerServerEvent('opx77_admin:refresh', 'access') end
	if screen == 'players' or screen == 'player' then
		TriggerServerEvent('opx77_admin:refresh', 'roster')
	elseif screen == 'locations' or screen == 'saved' then
		TriggerServerEvent('opx77_admin:refresh', 'locations')
	elseif (screen == 'itemCategories' or screen == 'weaponClasses' or screen == 'ammoList') and
		(not catalog.loaded or catalog.error) then
		TriggerServerEvent('opx77_admin:refresh', 'items')
	elseif screen == 'bag' then
		-- always read again: a bag changes under a staff member between two visits
		bag.target, bag.rows, bag.incoming, bag.loaded, bag.error = tostring(arg), {}, {}, false, nil
		TriggerServerEvent('opx77_admin:refresh', 'bag', tostring(arg))
	end
	draw()
end

local function pop()
	if #stack <= 1 then return Menu.Close() end
	stack[#stack] = nil
	draw()
end

--- Write the line under the list, or keep it for the next screen when none is up.
---@param text string
---@param ok boolean
function OpxAdmin.Menu.Status(text, ok)
	if type(text) ~= 'string' then return end
	-- the line is capped at 120 characters and a listing is many lines: the chat box has it all
	local line = text:match('^[^\n]*') or text
	if #line > 116 then line = line:sub(1, 113) .. '...' end
	if handle == nil then
		queuedStatus = { text = line, ok = ok }
		return
	end
	CreateThread(function() Client.Call(MENU, 'setStatus', line, ok) end)
end

--- Run a command line from a row or a form, and ask for a list again once it has had time to
--- land. The answer is written under the list when it comes back.
---@param tokens table
---@param refresh string|nil
function OpxAdmin.Menu.Run(tokens, refresh)
	suspended = false
	if #stack > 0 and handle == nil then draw() end
	if not Client.Execute(tokens) then
		Menu.Status(locale('admin.client.notSent'), false)
		return
	end
	if refresh then
		-- a bag is asked for by the target its screen draws
		local current = top()
		local arg = refresh == 'bag' and current and current.screen == 'bag' and tostring(current.arg)
			or nil
		if refresh == 'bag' and arg == nil then return end
		CreateThread(function()
			Wait(1200)
			TriggerServerEvent('opx77_admin:refresh', refresh, arg)
		end)
	end
end

--- Ask before running.
---@param tokens table
---@param key string
function OpxAdmin.Menu.Confirm(tokens, key)
	suspended = false
	if #stack == 0 then return end
	top().cursor = nil
	stack[#stack + 1] = { screen = 'confirm', arg = { tokens = tokens, key = key } }
	draw()
end

--- Take the menu down for a form, keeping the stack.
function OpxAdmin.Menu.Suspend()
	suspended = true
	if handle == nil then return end
	local closing = handle
	handle = nil
	CreateThread(function() Client.Call(MENU, 'close', closing) end)
end

--- Bring the menu back after a form, with a line under it if there is one.
---@param text string|nil
---@param ok boolean|nil
function OpxAdmin.Menu.Resume(text, ok)
	suspended = false
	if text then queuedStatus = { text = text, ok = ok } end
	draw()
end

function OpxAdmin.Menu.Close()
	stack = {}
	suspended = false
	Forms.Close()
	if handle == nil then return end
	local closing = handle
	handle = nil
	CreateThread(function() Client.Call(MENU, 'close', closing) end)
end

--- Redraw the open screen in place, for text that changed under it.
function OpxAdmin.Menu.Refresh()
	if handle ~= nil and not suspended then draw(true) end
end

---@return boolean
function OpxAdmin.Menu.IsOpen()
	return handle ~= nil or Forms.IsOpen()
end

---@return string|nil
function OpxAdmin.Menu.Screen()
	local current = top()
	return current and current.screen or nil
end

-- ---------------------------------------------------------------------------
-- The wire
-- ---------------------------------------------------------------------------

--- The opener's answer. Any client resource can raise this name locally; what it would get is
--- a menu whose every row is a command the host refuses it.
RegisterNetEvent('opx77_admin:open', function(payload)
	if type(payload) ~= 'table' then return end
	if #stack > 0 and not suspended then return Menu.Close() end -- the command toggles
	if not Client.Need(MENU) then
		Client.Toast('admin.client.menuMissing', nil, 'error')
		return
	end
	session = {
		you = tonumber(payload.you),
		access = type(payload.access) == 'table' and payload.access or {},
		aclKnown = payload.aclKnown == true,
		weapons = payload.weapons == true,
		inventory = payload.inventory == true,
	}
	-- the catalogue follows on its own event; one read before it would draw an old one
	catalog.rows, catalog.incoming, catalog.loaded, catalog.error = {}, {}, false, nil
	stack = { { screen = 'root' } }
	suspended = false
	draw()
end)

RegisterNetEvent('opx77_admin:access', function(payload)
	if session == nil or type(payload) ~= 'table' or type(payload.access) ~= 'table' then return end
	session.access, session.aclKnown = payload.access, payload.aclKnown == true
	local inventory = payload.inventory == true
	if inventory and not session.inventory then TriggerServerEvent('opx77_admin:refresh', 'items') end
	session.inventory = inventory
	draw(true)
end)

--- Chunks of a list the server read from opx77_inventory. Rows are data drawn as text; what a
--- row runs is a command line the host gates like any other.
---@param list table  `catalog` or `bag`
---@param payload table
---@param accept fun(entry: table): table|nil
---@return boolean done
local function collect(list, payload, accept)
	if payload.offset == 0 then list.incoming = {} end
	for _, entry in ipairs(payload.rows) do
		local kept = type(entry) == 'table' and accept(entry) or nil
		if kept then list.incoming[#list.incoming + 1] = kept end
	end
	if payload.done ~= true then return false end
	list.rows, list.incoming = list.incoming, {}
	list.loaded = true
	list.error = type(payload.error) == 'string' and payload.error or nil
	return true
end

RegisterNetEvent('opx77_admin:items', function(payload)
	if type(payload) ~= 'table' or type(payload.rows) ~= 'table' then return end
	local done = collect(catalog, payload, function(entry)
		if type(entry.name) ~= 'string' then return nil end
		local max = tonumber(entry.max)
		return { name = entry.name, label = tostring(entry.label or entry.name),
			category = tostring(entry.category or 'misc'),
			class = type(entry.class) == 'string' and entry.class or nil,
			max = max and math.floor(max) or nil }
	end)
	local screen = Menu.Screen()
	if done and (screen == 'itemCategories' or screen == 'itemList' or screen == 'weaponClasses' or
		screen == 'weaponList' or screen == 'ammoList') then
		draw(true)
	end
end)

RegisterNetEvent('opx77_admin:bag', function(payload)
	if type(payload) ~= 'table' or type(payload.rows) ~= 'table' then return end
	if payload.target ~= bag.target then return end
	local done = collect(bag, payload, function(entry)
		local slot, count = tonumber(entry.slot), tonumber(entry.count)
		if slot == nil or count == nil or type(entry.name) ~= 'string' then return nil end
		return { slot = math.floor(slot), count = math.floor(count), name = entry.name,
			label = tostring(entry.label or entry.name) }
	end)
	if done and Menu.Screen() == 'bag' then draw(true) end
end)

RegisterNetEvent('opx77_admin:roster', function(payload)
	if type(payload) ~= 'table' or type(payload.rows) ~= 'table' then return end
	if payload.offset == 0 then incoming = {} end
	for _, entry in ipairs(payload.rows) do
		local id = tonumber(type(entry) == 'table' and entry.id or nil)
		if id and type(entry.name) == 'string' then
			incoming[#incoming + 1] = {
				id = id, name = entry.name, bucket = tonumber(entry.bucket) or 0,
				distance = tonumber(entry.distance),
				state = (entry.state == 'up' or entry.state == 'down' or entry.state == 'gate')
					and entry.state or 'loading',
			}
		end
	end
	if payload.done ~= true then return end
	roster, rosterById = incoming, {}
	incoming = {}
	for _, entry in ipairs(roster) do rosterById[entry.id] = entry end
	local screen = Menu.Screen()
	if screen == 'players' or screen == 'player' or screen == 'root' then draw(true) end
end)

RegisterNetEvent('opx77_admin:locations', function(payload)
	if type(payload) ~= 'table' or type(payload.rows) ~= 'table' then return end
	local rows = {}
	for _, entry in ipairs(payload.rows) do
		if type(entry) == 'table' and type(entry.name) == 'string' and entry.name:match('^[%w_%-]+$')
		then
			rows[#rows + 1] = { name = entry.name, label = tostring(entry.label or entry.name),
				runtime = entry.runtime == true }
		end
	end
	locations = rows
	local screen = Menu.Screen()
	if screen == 'locations' or screen == 'saved' then draw(true) end
end)

--- A row was used. Any resource on this machine can raise this name, so the shape and the
--- owner are checked; whatever a row runs is gated by the host anyway.
AddEventHandler(EVENT, function(payload)
	if type(payload) ~= 'table' or payload.owner ~= Client.RESOURCE then return end

	if payload.action == 'close' then
		-- a screen this one replaced, whose close can arrive before the new handle does
		if payload.reason == 'reopened' or payload.handle ~= handle then return end
		handle = nil
		if suspended then return end
		if payload.reason == 'back' and #stack > 1 then
			stack[#stack] = nil
			return draw()
		end
		stack = {}
		return
	end

	if payload.action ~= 'select' or type(payload.data) ~= 'table' then return end
	local data = payload.data
	local current = top()
	if current == nil then return end
	current.cursor = payload.itemId

	if data.back then return pop() end
	if data.confirmed and current.screen == 'confirm' then
		local tokens = current.arg.tokens
		stack[#stack] = nil
		draw()
		return Menu.Run(tokens)
	end
	if type(data.go) == 'string' and SCREENS[data.go] then return push(data.go, data.arg) end
	if type(data.run) == 'table' then
		Menu.Run(data.run, data.refresh)
		if data.closeAfter then Menu.Close() end
		return
	end
	if type(data.confirm) == 'table' and type(data.key) == 'string' then
		return Menu.Confirm(data.confirm, data.key)
	end
	if type(data.form) == 'string' then return Forms.Open(data.form, data.arg) end
end)

-- ---------------------------------------------------------------------------
-- The key
-- ---------------------------------------------------------------------------

--- Up, the menu comes down here: closing grants nothing. Down, the key sends the line
--- /opx77.admin sends, so the host resolves command.opx77.admin before the server answers with
--- a menu, and a player without the grant gets the host's refusal and nothing else.
local function pressed()
	if Menu.IsOpen() then return Menu.Close() end
	Client.Execute({ OPENER })
end

AddEventHandler('onClientResourceStart', function(name)
	if name ~= Client.RESOURCE then return end
	local keys = Config.KEYS
	if keys ~= nil and type(keys) ~= 'table' then
		Open77.log.warn('config: KEYS must be a table; using the default keys')
		keys = nil
	end
	keys = keys or {}
	Keys.Register(KEY_MENU, 'admin.key.menu', Keys.Setting('KEYS.MENU', keys.MENU, 'F9'), pressed)
end)

-- the close row names the key, so a rebind in the pause menu shows without reopening
Keys.OnChanged(Menu.Refresh)

AddEventHandler('onClientResourceStop', function(name)
	if name ~= Client.RESOURCE then return end
	-- opx77_menu and opx77_input sweep a stopped owner, but not instantly
	Menu.Close()
end)
