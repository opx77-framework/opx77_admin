--- @author DemiAutomatic
--- @file client/menu.lua
--- @description The staff menu screens drawn by opx77_menu, and the menu key.

OpxAdmin = OpxAdmin or {}

local Config = OPX_ADMIN_CONFIG
local Client = OpxAdmin.Client
local Catalog = OpxAdmin.Catalog
local Forms = OpxAdmin.Forms
local Keys = OpxAdmin.Keys

--- @author DemiAutomatic
--- @type {table}
--- @description The menu functions forms, answers and exports call.
OpxAdmin.Menu = {}
local Menu = OpxAdmin.Menu

--- @author DemiAutomatic
--- @type {string}
--- @description The resource that draws the menu.
local MENU = 'opx77_menu'

--- @author DemiAutomatic
--- @type {string}
--- @description The local event opx77_menu raises row selections on.
local EVENT = 'opx77_admin:row'

--- @author DemiAutomatic
--- @type {table}
--- @description The LINKS config table, or an empty one.
local LINKS = type(Config.LINKS) == 'table' and Config.LINKS or {}

--- @author DemiAutomatic
--- @type {string}
--- @description Stable mapping id of the menu key.
local KEY_MENU = 'opx77_admin.menu'

--- @author DemiAutomatic
--- @type {string}
--- @description The command the menu key and open export send.
local OPENER = 'opx77.admin'

--- @author DemiAutomatic
--- @type {integer}
--- @description Most list rows one level draws, leaving navigation room.
local MAX_LISTED = 190

--- @author DemiAutomatic
--- @type {integer}
--- @description Rows one page of a catalogue list draws.
local PAGE_ROWS = 20

--- @author DemiAutomatic
--- @type {AdminSession|nil}
--- @description What the server sent when the menu opened.
local session

--- @author DemiAutomatic
--- @type {table[], table<integer, table>, table[]}
--- @description The roster, its index by id, and chunks still arriving.
local roster, rosterById, incoming = {}, {}, {}

--- @author DemiAutomatic
--- @type {table[]}
--- @description The destination rows the server last sent.
local locations = {}

--- @author DemiAutomatic
--- @type {table}
--- @description opx77_inventory's catalogue rows as the server read them.
local catalog = { rows = {}, incoming = {}, loaded = false, error = nil }

--- @author DemiAutomatic
--- @type {table}
--- @description The stacks of the one bag the remove picker draws.
local bag = { target = nil, rows = {}, incoming = {}, loaded = false, error = nil }

--- @author DemiAutomatic
--- @type {table[]}
--- @description Screen, argument and cursor from the root down.
local stack = {}

--- @author DemiAutomatic
--- @type {integer|nil}
--- @description The open menu's handle.
local handle

--- @author DemiAutomatic
--- @type {boolean}
--- @description Whether the menu was taken down to put a form up.
local suspended = false

--- @author DemiAutomatic
--- @type {table|nil}
--- @description A status line to write when the next screen opens.
local queuedStatus

--- @author DemiAutomatic
--- @type {integer}
--- @description Bumped by every draw, so a stale open claims nothing.
local drawn = 0

--- @author DemiAutomatic
--- @method permitted
--- @description Whether the access map grants a command, true without an ACL reader.
--- @param name {any}
--- @returns {boolean}
local function permitted(name)
	if session == nil or type(name) ~= 'string' or name == '' then return false end
	if not session.aclKnown then return true end
	return session.access[name] == true
end

--- @author DemiAutomatic
--- @method text
--- @description A catalogue key's text, or the words of a text table.
--- @param label {string|table}
--- @returns {string}
local function text(label)
	if type(label) == 'table' then return tostring(label.text) end
	return locale(label)
end

--- @author DemiAutomatic
--- @method row
--- @description One menu row with its data and extra properties.
--- @param id {string}
--- @param label {string}
--- @param data {table|nil}
--- @param extra {table|nil}
--- @returns {table}
local function row(id, label, data, extra)
	local item = { id = id, label = label, data = data }
	for key, value in pairs(extra or {}) do item[key] = value end
	return item
end

--- @author DemiAutomatic
--- @method command
--- @description A row running a command line, greyed when the ACL refuses it.
--- @param id {string}
--- @param label {string|table}
--- @param tokens {table}
--- @param refresh {string|nil} What to ask for again after it ran.
--- @param extra {table|nil}
--- @returns {table}
local function command(id, label, tokens, refresh, extra)
	local item = row(id, text(label), { run = tokens, refresh = refresh }, extra)
	if not permitted(tokens[1]) then
		item.disabled = true
		item.value = locale('admin.menu.denied')
	end
	return item
end

--- @author DemiAutomatic
--- @method guarded
--- @description A command row that goes through a confirmation screen first.
--- @param id {string}
--- @param labelKey {string}
--- @param tokens {table}
--- @param confirmKey {string}
--- @returns {table}
local function guarded(id, labelKey, tokens, confirmKey)
	local item = command(id, labelKey, tokens)
	item.data = { confirm = tokens, key = confirmKey }
	return item
end

--- @author DemiAutomatic
--- @method form
--- @description A row opening a form, greyed when its command is refused.
--- @param id {string}
--- @param labelKey {string}
--- @param kind {string}
--- @param arg {any}
--- @param name {string|nil} The command the form ends in.
--- @returns {table}
local function form(id, labelKey, kind, arg, name)
	local item = row(id, locale(labelKey), { form = kind, arg = arg })
	if not permitted(name) then
		item.disabled = true
		item.value = locale('admin.menu.denied')
	end
	return item
end

--- @author DemiAutomatic
--- @method go
--- @description A row that pushes another screen.
--- @param id {string}
--- @param label {string|table}
--- @param screen {string}
--- @param arg {any}
--- @param extra {table|nil}
--- @returns {table}
local function go(id, label, screen, arg, extra)
	return row(id, text(label), { go = screen, arg = arg }, extra)
end

--- @author DemiAutomatic
--- @method paged
--- @description One page of a catalogue list, with a row to the next.
--- @param list {table[]}
--- @param screen {string}
--- @param arg {table}
--- @param title {string}
--- @param build {fun(entry: table): table}
--- @returns {string, table[]}
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

--- @author DemiAutomatic
--- @method section
--- @description A separator row, with a label when given.
--- @param labelKey {string|nil}
--- @returns {table}
local function section(labelKey)
	return { separator = true, label = labelKey and locale(labelKey) or nil }
end

--- @author DemiAutomatic
--- @method inventoryUp
--- @description Whether the server last reported opx77_inventory running.
--- @returns {boolean}
local function inventoryUp()
	return session ~= nil and session.inventory == true
end

--- @author DemiAutomatic
--- @method unavailable
--- @description Greys a row with a word beside it.
--- @param item {table}
--- @param key {string|nil}
--- @returns {table}
local function unavailable(item, key)
	item.disabled, item.value = true, locale(key or 'admin.menu.unavailable')
	return item
end

--- @author DemiAutomatic
--- @method goFor
--- @description A row to a picker, greyed when its final command is refused.
--- @param id {string}
--- @param labelKey {string}
--- @param screen {string}
--- @param arg {any}
--- @param name {string|nil}
--- @returns {table}
local function goFor(id, labelKey, screen, arg, name)
	local item = go(id, labelKey, screen, arg)
	if not permitted(name) then unavailable(item, 'admin.menu.denied') end
	return item
end

--- @author DemiAutomatic
--- @method placeholder
--- @description The one row a picker shows while loading, failed or empty.
--- @param list {table} catalog or bag.
--- @param emptyKey {string}
--- @returns {table}
local function placeholder(list, emptyKey)
	local key = not list.loaded and 'admin.menu.loading' or list.error and 'admin.menu.inventoryError'
		or emptyKey
	return row('empty', locale(key), nil, { disabled = true })
end

--- @author DemiAutomatic
--- @method weaponRows
--- @description The weapon rows for a target, greyed without their provider.
--- @param target {string}
--- @param giveKey {string}
--- @returns {table[]}
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

--- @author DemiAutomatic
--- @method nameOf
--- @description A roster player's name and id, for a title.
--- @param id {integer}
--- @returns {string}
local function nameOf(id)
	local entry = rosterById[id]
	return entry and ('%s [%d]'):format(entry.name, id) or ('[%s]'):format(tostring(id))
end

--- @author DemiAutomatic
--- @type {table<string, function>}
--- @description Every screen by name, each answering a title and rows.
local SCREENS = {}

--- @author DemiAutomatic
--- @method SCREENS.root
--- @description The root screen listing the six sections.
--- @returns {string, table[]}
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

--- @author DemiAutomatic
--- @method SCREENS.players
--- @description The roster with state, bucket and distance per player.
--- @returns {string, table[]}
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

--- @author DemiAutomatic
--- @method SCREENS.player
--- @description Every action on one player, by section.
--- @param id {integer}
--- @returns {string, table[]}
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

--- @author DemiAutomatic
--- @method SCREENS.self
--- @description The operator's own travel, health and position rows.
--- @returns {string, table[]}
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

--- @author DemiAutomatic
--- @method SCREENS.vehicles
--- @description Spawning, and actions on the nearest or own vehicles.
--- @returns {string, table[]}
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

--- @author DemiAutomatic
--- @method titleFor
--- @description A picker title, naming the player when not the operator.
--- @param titleKey {string}
--- @param target {any} me, or a player id.
--- @returns {string}
local function titleFor(titleKey, target)
	if target == nil or target == 'me' then return locale(titleKey) end
	return ('%s: %s'):format(locale(titleKey), nameOf(tonumber(target) or target))
end

--- @author DemiAutomatic
--- @method SCREENS.vehicleClasses
--- @description The vehicle classes that have rows, with their counts.
--- @param target {any}
--- @returns {string, table[]}
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

--- @author DemiAutomatic
--- @method SCREENS.vehicleList
--- @description One class's vehicles, spawned for the operator or delivered.
--- @param arg {table}
--- @returns {string, table[]}
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

--- @author DemiAutomatic
--- @method weaponGroups
--- @description The catalogue's weapons by class, known classes first.
--- @returns {table[], table<string, table>}
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

--- @author DemiAutomatic
--- @method SCREENS.weaponClasses
--- @description The weapon classes that have weapons, with their counts.
--- @param target {any}
--- @returns {string, table[]}
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

--- @author DemiAutomatic
--- @method SCREENS.weaponList
--- @description One class's weapons, each row giving the weapon empty.
--- @param arg {table}
--- @returns {string, table[]}
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

--- @author DemiAutomatic
--- @method SCREENS.ammoList
--- @description The ammunition items, each opening the count form of a give.
--- @param target {any}
--- @returns {string, table[]}
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

--- @author DemiAutomatic
--- @method SCREENS.weapons
--- @description The operator's own weapon rows.
--- @returns {string, table[]}
SCREENS.weapons = function()
	return locale('admin.menu.weapons'), weaponRows('me', 'admin.menu.giveMe')
end

--- @author DemiAutomatic
--- @method SCREENS.itemCategories
--- @description The catalogue's categories, for a give or the holders list.
--- @param arg {table}
--- @returns {string, table[]}
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

--- @author DemiAutomatic
--- @method SCREENS.itemList
--- @description One category's items, each a give form or holders query.
--- @param arg {table}
--- @returns {string, table[]}
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

--- @author DemiAutomatic
--- @method SCREENS.bag
--- @description One bag's stacks, each opening the count form of a removal.
--- @param target {any}
--- @returns {string, table[]}
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

--- @author DemiAutomatic
--- @method SCREENS.locations
--- @description The destinations, each sending the target there.
--- @param target {any}
--- @returns {string, table[]}
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

--- @author DemiAutomatic
--- @method SCREENS.saved
--- @description The destinations saved in game, each forgotten by its row.
--- @returns {string, table[]}
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

--- @author DemiAutomatic
--- @method SCREENS.world
--- @description Announcements, destinations, and the sky screens.
--- @returns {string, table[]}
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

--- @author DemiAutomatic
--- @method SCREENS.weather
--- @description Weather presets, roll, hold and release through opx77_weather.
--- @returns {string, table[]}
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

--- @author DemiAutomatic
--- @method SCREENS.time
--- @description Clock times, a typed time, and the clock hold.
--- @returns {string, table[]}
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

--- @author DemiAutomatic
--- @method SCREENS.server
--- @description Server reports, character commands, and the holders picker.
--- @returns {string, table[]}
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

--- @author DemiAutomatic
--- @method SCREENS.confirm
--- @description The confirmation screen, Cancel first, then Confirm.
--- @param arg {table}
--- @returns {string, table[]}
SCREENS.confirm = function(arg)
	return locale(arg.key), {
		row('cancel', locale('admin.menu.cancel'), { back = true }),
		row('confirm', locale('admin.menu.confirm'), { confirmed = true },
			{ description = table.concat(arg.tokens, ' ') }),
	}
end

--- @author DemiAutomatic
--- @method top
--- @description The screen at the top of the stack.
--- @returns {table|nil}
local function top()
	return stack[#stack]
end

--- @author DemiAutomatic
--- @method draw
--- @description Puts the top screen up, or rebuilds it in place.
--- @param inPlace {boolean|nil}
local function draw(inPlace)
	local current = top()
	if current == nil or suspended then return end
	local builder = SCREENS[current.screen]
	if builder == nil then return end
	local title, items = builder(current.arg)
	if current.screen == 'confirm' then
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

--- @author DemiAutomatic
--- @method push
--- @description Pushes a screen, asks for its data again, and draws it.
--- @param screen {string}
--- @param arg {any}
local function push(screen, arg)
	stack[#stack + 1] = { screen = screen, arg = arg }
	if #stack == 2 then TriggerServerEvent('opx77_admin:refresh', 'access') end
	if screen == 'players' or screen == 'player' then
		TriggerServerEvent('opx77_admin:refresh', 'roster')
	elseif screen == 'locations' or screen == 'saved' then
		TriggerServerEvent('opx77_admin:refresh', 'locations')
	elseif (screen == 'itemCategories' or screen == 'weaponClasses' or screen == 'ammoList') and
		(not catalog.loaded or catalog.error) then
		TriggerServerEvent('opx77_admin:refresh', 'items')
	elseif screen == 'bag' then
		bag.target, bag.rows, bag.incoming, bag.loaded, bag.error = tostring(arg), {}, {}, false, nil
		TriggerServerEvent('opx77_admin:refresh', 'bag', tostring(arg))
	end
	draw()
end

--- @author DemiAutomatic
--- @method pop
--- @description Goes back a screen, or closes the menu at the root.
local function pop()
	if #stack <= 1 then return Menu.Close() end
	stack[#stack] = nil
	draw()
end

--- @author DemiAutomatic
--- @method OpxAdmin.Menu.Status
--- @description Writes the line under the list, or keeps it for later.
--- @param text {string}
--- @param ok {boolean}
function OpxAdmin.Menu.Status(text, ok)
	if type(text) ~= 'string' then return end
	local line = text:match('^[^\n]*') or text
	if #line > 116 then line = line:sub(1, 113) .. '...' end
	if handle == nil then
		queuedStatus = { text = line, ok = ok }
		return
	end
	CreateThread(function() Client.Call(MENU, 'setStatus', line, ok) end)
end

--- @author DemiAutomatic
--- @method OpxAdmin.Menu.Run
--- @description Runs a command line and asks for a list again later.
--- @param tokens {table}
--- @param refresh {string|nil}
function OpxAdmin.Menu.Run(tokens, refresh)
	suspended = false
	if #stack > 0 and handle == nil then draw() end
	if not Client.Execute(tokens) then
		Menu.Status(locale('admin.client.notSent'), false)
		return
	end
	if refresh then
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

--- @author DemiAutomatic
--- @method OpxAdmin.Menu.Confirm
--- @description Pushes the confirmation screen for a command line.
--- @param tokens {table}
--- @param key {string}
function OpxAdmin.Menu.Confirm(tokens, key)
	suspended = false
	if #stack == 0 then return end
	top().cursor = nil
	stack[#stack + 1] = { screen = 'confirm', arg = { tokens = tokens, key = key } }
	draw()
end

--- @author DemiAutomatic
--- @method OpxAdmin.Menu.Suspend
--- @description Takes the menu down for a form, keeping the stack.
function OpxAdmin.Menu.Suspend()
	suspended = true
	if handle == nil then return end
	local closing = handle
	handle = nil
	CreateThread(function() Client.Call(MENU, 'close', closing) end)
end

--- @author DemiAutomatic
--- @method OpxAdmin.Menu.Resume
--- @description Brings the menu back after a form, with an optional line.
--- @param text {string|nil}
--- @param ok {boolean|nil}
function OpxAdmin.Menu.Resume(text, ok)
	suspended = false
	if text then queuedStatus = { text = text, ok = ok } end
	draw()
end

--- @author DemiAutomatic
--- @method OpxAdmin.Menu.Close
--- @description Takes the menu and any form down and empties the stack.
function OpxAdmin.Menu.Close()
	stack = {}
	suspended = false
	Forms.Close()
	if handle == nil then return end
	local closing = handle
	handle = nil
	CreateThread(function() Client.Call(MENU, 'close', closing) end)
end

--- @author DemiAutomatic
--- @method OpxAdmin.Menu.Refresh
--- @description Redraws the open screen in place for changed text.
function OpxAdmin.Menu.Refresh()
	if handle ~= nil and not suspended then draw(true) end
end

--- @author DemiAutomatic
--- @method OpxAdmin.Menu.IsOpen
--- @description Whether the menu or one of its forms is up.
--- @returns {boolean}
function OpxAdmin.Menu.IsOpen()
	return handle ~= nil or Forms.IsOpen()
end

--- @author DemiAutomatic
--- @method OpxAdmin.Menu.Screen
--- @description The name of the screen at the top of the stack.
--- @returns {string|nil}
function OpxAdmin.Menu.Screen()
	local current = top()
	return current and current.screen or nil
end

--- @author DemiAutomatic
--- @event opx77_admin:open
--- @description Opens the root screen from the opener's answer, or toggles closed.
--- @param payload {AdminSession}
RegisterNetEvent('opx77_admin:open', function(payload)
	if type(payload) ~= 'table' then return end
	if #stack > 0 and not suspended then return Menu.Close() end
	if not Client.Need(MENU) then
		Client.Toast('admin.client.menuMissing', nil, 'error')
		return
	end
	session = {
		access = type(payload.access) == 'table' and payload.access or {},
		aclKnown = payload.aclKnown == true,
		weapons = payload.weapons == true,
		inventory = payload.inventory == true,
	}
	catalog.rows, catalog.incoming, catalog.loaded, catalog.error = {}, {}, false, nil
	stack = { { screen = 'root' } }
	suspended = false
	draw()
end)

--- @author DemiAutomatic
--- @event opx77_admin:access
--- @description Takes a fresh access map and redraws in place.
--- @param payload {table}
RegisterNetEvent('opx77_admin:access', function(payload)
	if session == nil or type(payload) ~= 'table' or type(payload.access) ~= 'table' then return end
	session.access, session.aclKnown = payload.access, payload.aclKnown == true
	local inventory = payload.inventory == true
	if inventory and not session.inventory then TriggerServerEvent('opx77_admin:refresh', 'items') end
	session.inventory = inventory
	draw(true)
end)

--- @author DemiAutomatic
--- @method collect
--- @description Gathers one chunk of an inventory list, answering when complete.
--- @param list {table} catalog or bag.
--- @param payload {table}
--- @param accept {fun(entry: table): table|nil}
--- @returns {boolean}
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

--- @author DemiAutomatic
--- @event opx77_admin:items
--- @description Collects the inventory catalogue chunks and redraws a picker.
--- @param payload {table}
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

--- @author DemiAutomatic
--- @event opx77_admin:bag
--- @description Collects the asked bag's stack chunks and redraws the picker.
--- @param payload {table}
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

--- @author DemiAutomatic
--- @event opx77_admin:roster
--- @description Collects roster chunks and redraws the screens that show it.
--- @param payload {table}
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

--- @author DemiAutomatic
--- @event opx77_admin:locations
--- @description Takes the destination list and redraws the screens that show it.
--- @param payload {table}
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

--- @author DemiAutomatic
--- @event opx77_admin:row
--- @description Handles a row selection or a menu close from opx77_menu.
--- @param payload {table}
AddEventHandler(EVENT, function(payload)
	if type(payload) ~= 'table' or payload.owner ~= Client.RESOURCE then return end

	if payload.action == 'close' then
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

--- @author DemiAutomatic
--- @method pressed
--- @description The menu key: closes an open menu, otherwise sends the opener.
local function pressed()
	if Menu.IsOpen() then return Menu.Close() end
	Client.Execute({ OPENER })
end

--- @author DemiAutomatic
--- @event onClientResourceStart
--- @description Registers the menu key when this resource starts.
--- @param name {string}
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

Keys.OnChanged(Menu.Refresh)

--- @author DemiAutomatic
--- @event onClientResourceStop
--- @description Closes the menu and any form when this resource stops.
--- @param name {string}
AddEventHandler('onClientResourceStop', function(name)
	if name ~= Client.RESOURCE then return end
	Menu.Close()
end)
