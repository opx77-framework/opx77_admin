--- @author DemiAutomatic
--- @file client/target.lua
--- @description Staff rows on opx77_target's eye: yourself, players, vehicles, doors and the sky.

OpxAdmin = OpxAdmin or {}

local Config = OPX_ADMIN_CONFIG
local Client = OpxAdmin.Client
local Menu = OpxAdmin.Menu
local Tags = OpxAdmin.Tags
local Text = OpxAdmin.Text

--- @author DemiAutomatic
--- @type {table}
--- @description The functions the menu hands access maps to.
OpxAdmin.Target = {}

--- @author DemiAutomatic
--- @type {string}
--- @description The resource that draws the eye.
local TARGET = 'opx77_target'

--- @author DemiAutomatic
--- @type {string}
--- @description The opener command, whose grant makes a player staff.
local OPENER = 'opx77.admin'

--- @author DemiAutomatic
--- @type {string}
--- @description The official door service; while it runs the door rows stand down.
local NETWORKED_DOORS = 'open77_doors'

--- @author DemiAutomatic
--- @type {string}
--- @description The resource behind the weather and time screens.
local WEATHER = 'opx77_weather'

--- @author DemiAutomatic
--- @type {integer}
--- @description Rows sent in one registration, under the client's instruction budget.
local BATCH = 5

--- @author DemiAutomatic
--- @type {integer}
--- @description Milliseconds before the first access request, then between two.
local ACCESS_FIRST_MS, ACCESS_EVERY_MS = 5000, 60000

--- @author DemiAutomatic
--- @type {table}
--- @description The TARGET config table, or an empty one.
local SETTINGS = type(Config.TARGET) == 'table' and Config.TARGET or {}

--- @author DemiAutomatic
--- @type {table}
--- @description The LINKS config table, or an empty one.
local LINKS = type(Config.LINKS) == 'table' and Config.LINKS or {}

--- @author DemiAutomatic
--- @type {number}
--- @description Metres a player, vehicle or door rows reach, 1..12.
local DISTANCE = math.min(12, math.max(1, Text.Finite(SETTINGS.DISTANCE) or 10))

--- @author DemiAutomatic
--- @type {table<string, string>}
--- @description The opx77_target export that registers each kind of row.
local REGISTERS = { self = 'registerSelf', player = 'registerPlayers', vehicle = 'registerVehicles',
	door = 'registerDoors', sky = 'registerSky' }

--- @author DemiAutomatic
--- @type {string[]}
--- @description Kinds in the order they are registered.
local KINDS = { 'self', 'player', 'vehicle', 'door', 'sky' }

--- @author DemiAutomatic
--- @type {table<string, boolean>|nil, boolean}
--- @description The last access map the server sent, and whether it could read the ACL.
local access, aclKnown = nil, false

--- @author DemiAutomatic
--- @type {string|nil}
--- @description Signature of the rows opx77_target holds for this resource, nil for none.
local registered

--- @author DemiAutomatic
--- @type {boolean, boolean}
--- @description Whether a registration is running, and whether another is wanted after it.
local syncing, dirty = false, false

--- @author DemiAutomatic
--- @method run
--- @description Sends a command line, answering whether it left.
--- @param tokens {string[]}
--- @returns {boolean}
local function run(tokens)
	return Client.Execute(tokens)
end

--- @author DemiAutomatic
--- @method idOf
--- @description A positive whole id the context's target names under a key, as text.
--- @param context {table}
--- @param key {string} playerId or vehicleId.
--- @returns {string|nil}
local function idOf(context, key)
	local target = type(context) == 'table' and context.target or nil
	local id = type(target) == 'table' and math.tointeger(target[key]) or nil
	if id == nil or id < 1 then return nil end
	return ('%d'):format(id)
end

--- @author DemiAutomatic
--- @method doorOf
--- @description The live snapshot of the door the context hit, or nil.
--- @param context {table}
--- @returns {table|nil}
local function doorOf(context)
	if Client.Running(NETWORKED_DOORS) then return nil end
	local target = type(context) == 'table' and context.target or nil
	local entity = type(target) == 'table' and target.engineEntity or nil
	local native = Open77.doors
	if type(entity) ~= 'string' or type(native) ~= 'table' or type(native.state) ~= 'function' then return nil end
	local read, door = pcall(native.state, entity)
	if not read or type(door) ~= 'table' or type(door.id) ~= 'string' then return nil end
	return door
end

--- @author DemiAutomatic
--- @method onPlayer
--- @description A select that runs a command naming the targeted player.
--- @param command {string}
--- @returns {fun(context: table): boolean}
local function onPlayer(command)
	return function(context)
		local id = idOf(context, 'playerId')
		return id ~= nil and run({ command, id })
	end
end

--- @author DemiAutomatic
--- @method onVehicle
--- @description A select that runs a command naming the targeted vehicle, then extra words.
--- @param command {string}
--- @param ... {string}
--- @returns {fun(context: table): boolean}
local function onVehicle(command, ...)
	local extra = { ... }
	return function(context)
		local id = idOf(context, 'vehicleId')
		if id == nil then return false end
		return run({ command, id, table.unpack(extra) })
	end
end

--- @author DemiAutomatic
--- @method onDoor
--- @description A select that runs the door command on the targeted door.
--- @param action {string}
--- @returns {fun(context: table): boolean}
local function onDoor(action)
	return function(context)
		local door = doorOf(context)
		return door ~= nil and run({ 'opx77.admin.world.door', door.id, action })
	end
end

--- @author DemiAutomatic
--- @method doorThere
--- @description A check that the eye hit a door, a lift door only when it passes.
--- @param lifts {boolean} Whether a lift door passes.
--- @returns {fun(context: table): boolean}
local function doorThere(lifts)
	return function(context)
		local door = doorOf(context)
		return door ~= nil and (lifts or not door.lift)
	end
end

--- @author DemiAutomatic
--- @method doorReads
--- @description A state reading one boolean field of the targeted door's snapshot.
--- @param field {string} open or locked.
--- @returns {fun(context: table): boolean|nil}
local function doorReads(field)
	return function(context)
		local door = doorOf(context)
		if door == nil then return nil end
		return door[field] == true
	end
end

--- @author DemiAutomatic
--- @method onDoorFlip
--- @description A select that sends the door the action undoing what a field of its snapshot reads.
--- @param field {string} open or locked.
--- @param onAction {string} The action that makes the field true.
--- @param offAction {string} The action that makes it false.
--- @returns {fun(context: table): boolean}
local function onDoorFlip(field, onAction, offAction)
	return function(context)
		local door = doorOf(context)
		if door == nil then return false end
		return run({ 'opx77.admin.world.door', door.id, door[field] == true and offAction or onAction })
	end
end

--- @author DemiAutomatic
--- @type {boolean|nil, table<integer, boolean>|nil}
--- @description Whether the server last said this player's body is hidden, and the players it said are held
--- still; nil until it first said.
local invisible, frozenIds = nil, nil

--- @author DemiAutomatic
--- @method noclipOn
--- @description The noclip state, as this client applied it.
--- @returns {boolean}
local function noclipOn()
	return Client.IsNoclip()
end

--- @author DemiAutomatic
--- @method godOn
--- @description The operator's god mode, from their replicated health snapshot.
--- @returns {boolean|nil}
local function godOn()
	return Client.GodMode()
end

--- @author DemiAutomatic
--- @method invisibleOn
--- @description Whether the server last said the operator's body is hidden.
--- @returns {boolean|nil}
local function invisibleOn()
	return invisible
end

--- @author DemiAutomatic
--- @method tagsOn
--- @description Whether the operator's name tags are on, as the server last said.
--- @returns {boolean}
local function tagsOn()
	return Tags.IsShown()
end

--- @author DemiAutomatic
--- @method frozenOn
--- @description Whether the server last said the targeted player is held still.
--- @param context {table}
--- @returns {boolean|nil}
local function frozenOn(context)
	local id = idOf(context, 'playerId')
	if id == nil or frozenIds == nil then return nil end
	return frozenIds[tonumber(id)] == true
end

--- @author DemiAutomatic
--- @method lockedOn
--- @description The targeted vehicle's replicated entry lock, nil when unreadable.
--- @param context {table}
--- @returns {boolean|nil}
local function lockedOn(context)
	local id = idOf(context, 'vehicleId')
	local vehicles = Open77.vehicles
	if id == nil or type(vehicles) ~= 'table' or type(vehicles.isLocked) ~= 'function' then return nil end
	local read, value = pcall(vehicles.isLocked, tonumber(id))
	if not read or type(value) ~= 'boolean' then return nil end
	return value
end

--- @author DemiAutomatic
--- @method onFlip
--- @description A select that runs a switch command with the word undoing what its state reads, and no word,
--- so the server toggles, when it reads nothing.
--- @param state {fun(context: table): boolean|nil}
--- @param command {string}
--- @param key {string|nil} playerId or vehicleId when the command names the target.
--- @param ... {string} Words between the target and the switch word.
--- @returns {fun(context: table): boolean}
local function onFlip(state, command, key, ...)
	local extra = { ... }
	return function(context)
		local tokens = { command }
		if key ~= nil then
			local id = idOf(context, key)
			if id == nil then return false end
			tokens[2] = id
		end
		for _, word in ipairs(extra) do tokens[#tokens + 1] = word end
		local on = state(context)
		if type(on) == 'boolean' then tokens[#tokens + 1] = on and 'off' or 'on' end
		return run(tokens)
	end
end

--- @author DemiAutomatic
--- @type {table[]}
--- @description Every staff row: id, the folder it sits in under the staff group, kind, label key, icon,
--- the command its grant is read from, a check when it applies only to some targets, the on/off state its
--- checkbox reads, a resource it needs running, and what selecting it does.
local ROWS = {
	{ id = 'selfNoclip', folder = 'move', kind = 'self', label = 'admin.target.noclip', icon = 'location',
		grant = 'opx77.admin.self.noclip', state = noclipOn, select = onFlip(noclipOn, 'opx77.admin.self.noclip') },
	{ id = 'selfGod', folder = 'state', kind = 'self', label = 'admin.target.god', icon = 'heal',
		grant = 'opx77.admin.self.god', state = godOn, select = onFlip(godOn, 'opx77.admin.self.god') },
	{ id = 'selfInvisible', folder = 'state', kind = 'self', label = 'admin.target.invisible', icon = 'person',
		grant = 'opx77.admin.self.invisible', state = invisibleOn,
		select = onFlip(invisibleOn, 'opx77.admin.self.invisible') },
	{ id = 'selfHeal', folder = 'state', kind = 'self', label = 'admin.target.heal', icon = 'heal',
		grant = 'opx77.admin.self.heal', select = function() return run({ 'opx77.admin.self.heal' }) end },
	{ id = 'selfAmmo', folder = 'state', kind = 'self', label = 'admin.target.ammo', icon = 'box',
		grant = 'opx77.admin.weapon.ammo', select = function() return run({ 'opx77.admin.weapon.ammo', 'me' }) end },
	{ id = 'selfTags', folder = 'state', kind = 'self', label = 'admin.target.tags', icon = 'info',
		grant = 'opx77.admin.self.tags', state = tagsOn, select = onFlip(tagsOn, 'opx77.admin.self.tags') },
	{ id = 'selfMap', folder = 'move', kind = 'self', label = 'admin.target.maptravel', icon = 'location',
		grant = 'opx77.admin.self.maptravel', select = function() return run({ 'opx77.admin.self.maptravel' }) end },
	{ id = 'selfPos', folder = 'move', kind = 'self', label = 'admin.target.pos', icon = 'info',
		grant = 'opx77.admin.self.pos', select = function() return run({ 'opx77.admin.self.pos' }) end },
	{ id = 'selfMenu', kind = 'self', label = 'admin.target.selfMenu', icon = 'tool',
		grant = OPENER, select = function() return Menu.OpenAt('self') end },

	{ id = 'playerManage', kind = 'player', label = 'admin.target.manage', icon = 'person', grant = OPENER,
		select = function(context)
			local id = idOf(context, 'playerId')
			return id ~= nil and Menu.OpenAt('player', tonumber(id))
		end },
	{ id = 'playerHeal', kind = 'player', label = 'admin.target.heal', icon = 'heal',
		grant = 'opx77.admin.player.heal', select = onPlayer('opx77.admin.player.heal') },
	{ id = 'playerRevive', kind = 'player', label = 'admin.target.revive', icon = 'heal',
		grant = 'opx77.admin.player.revive', select = onPlayer('opx77.admin.player.revive') },
	{ id = 'playerFreeze', kind = 'player', label = 'admin.target.freeze', icon = 'lock',
		grant = 'opx77.admin.player.freeze', state = frozenOn,
		select = onFlip(frozenOn, 'opx77.admin.player.freeze', 'playerId') },
	{ id = 'playerBag', kind = 'player', label = 'admin.target.bag', icon = 'box',
		grant = LINKS.INVENTORY_OPEN, select = onPlayer(LINKS.INVENTORY_OPEN) },
	{ id = 'playerKick', folder = 'moderation', kind = 'player', label = 'admin.target.kick', icon = 'lock', danger = true,
		grant = 'opx77.admin.moderate.kick', select = function(context)
			local id = idOf(context, 'playerId')
			return id ~= nil and Menu.OpenAt('player', tonumber(id), 'kick')
		end },
	{ id = 'playerBan', folder = 'moderation', kind = 'player', label = 'admin.target.ban', icon = 'lock', danger = true,
		grant = 'opx77.admin.moderate.ban', select = function(context)
			local id = idOf(context, 'playerId')
			return id ~= nil and Menu.OpenAt('player', tonumber(id), 'ban')
		end },

	{ id = 'vehicleEnter', kind = 'vehicle', label = 'admin.target.enter', icon = 'vehicle',
		grant = 'opx77.admin.vehicle.enter', select = onVehicle('opx77.admin.vehicle.enter') },
	{ id = 'vehicleRepair', kind = 'vehicle', label = 'admin.target.repair', icon = 'tool',
		grant = 'opx77.admin.vehicle.repair', select = onVehicle('opx77.admin.vehicle.repair', 'full') },
	{ id = 'vehicleBody', kind = 'vehicle', label = 'admin.target.repairVisual', icon = 'tool',
		grant = 'opx77.admin.vehicle.repair', select = onVehicle('opx77.admin.vehicle.repair', 'visual') },
	{ id = 'vehicleLock', kind = 'vehicle', label = 'admin.target.vehicleLocked', icon = 'lock',
		grant = 'opx77.admin.vehicle.flag', state = lockedOn,
		select = onFlip(lockedOn, 'opx77.admin.vehicle.flag', 'vehicleId', 'locked') },
	{ id = 'vehicleRemove', kind = 'vehicle', label = 'admin.target.removeVehicle', icon = 'tool', danger = true,
		grant = 'opx77.admin.vehicle.remove', select = onVehicle('opx77.admin.vehicle.remove') },

	{ id = 'doorOpen', kind = 'door', label = 'admin.target.doorOpen', icon = 'door',
		grant = 'opx77.admin.world.door', check = doorThere(false), state = doorReads('open'),
		select = onDoorFlip('open', 'open', 'close') },
	{ id = 'doorLock', kind = 'door', label = 'admin.target.doorLocked', icon = 'lock',
		grant = 'opx77.admin.world.door', check = doorThere(true), state = doorReads('locked'),
		select = onDoorFlip('locked', 'lock', 'unlock') },
	{ id = 'doorReset', kind = 'door', label = 'admin.target.doorReset', icon = 'door',
		grant = 'opx77.admin.world.door', check = function(context) return doorOf(context) ~= nil end,
		select = onDoor('reset') },
	{ id = 'doorCopy', kind = 'door', label = 'admin.target.doorCopy', icon = 'info',
		grant = 'opx77.admin.world.door', check = function(context) return doorOf(context) ~= nil end,
		select = function(context)
			local door = doorOf(context)
			local clipboard = Open77.clipboard
			if door == nil or type(clipboard) ~= 'table' or type(clipboard.setText) ~= 'function' then return false end
			local read, copied = pcall(clipboard.setText, door.id)
			Client.Toast(read and copied and 'admin.target.doorCopied' or 'admin.target.clipboardMissing',
				{ door = door.id }, read and copied and 'success' or 'error')
			return read and copied == true
		end },

	{ id = 'skyNoclip', kind = 'sky', label = 'admin.target.noclip', icon = 'location',
		grant = 'opx77.admin.self.noclip', state = noclipOn, select = onFlip(noclipOn, 'opx77.admin.self.noclip') },
}

--- @author DemiAutomatic
--- @type {integer}
--- @description Weather presets the sky lists, leaving room in the eye's list for the other sky rows.
local MAX_PRESETS = 8

do
	local listed = 0
	for _, preset in ipairs(type(Config.WEATHER_PRESETS) == 'table' and Config.WEATHER_PRESETS or {}) do
		if listed < MAX_PRESETS and type(preset) == 'string' and preset:match('^[%w_%-]+$') then
			listed = listed + 1
			local key = 'admin.weather.' .. preset
			ROWS[#ROWS + 1] = { id = 'skyWeather_' .. preset, folder = 'weather', kind = 'sky', icon = 'location',
				text = function()
					local name = locale(key)
					if name == key then name = preset end
					return locale('admin.target.weatherPreset', { preset = name })
				end,
				grant = LINKS.WEATHER_SET, needs = WEATHER,
				select = function() return run({ LINKS.WEATHER_SET, preset }) end }
		end
	end
end
ROWS[#ROWS + 1] = { id = 'skyWeatherNext', folder = 'weather', kind = 'sky', label = 'admin.target.weatherNext', icon = 'location',
	grant = LINKS.WEATHER_NEXT, needs = WEATHER, select = function() return run({ LINKS.WEATHER_NEXT }) end }
ROWS[#ROWS + 1] = { id = 'skyTime', kind = 'sky', label = 'admin.target.time', icon = 'location',
	grant = LINKS.TIME, needs = WEATHER, select = function() return Menu.OpenAt('time') end }

--- @author DemiAutomatic
--- @type {table<string, table>}
--- @description Every row by id.
local BY_ID = {}
for _, row in ipairs(ROWS) do BY_ID[row.id] = row end

--- @author DemiAutomatic
--- @method granted
--- @description Whether the last access map grants a command.
--- @param name {any}
--- @returns {boolean}
local function granted(name)
	if access == nil or access[OPENER] ~= true or type(name) ~= 'string' or name == '' then return false end
	return not aclKnown or access[name] == true
end

--- @author DemiAutomatic
--- @method wanted
--- @description The rows the access map grants, by kind, and their signature.
--- @returns {table<string, table[]>, string}
local function wanted()
	local byKind, ids = {}, {}
	for index, row in ipairs(ROWS) do
		if granted(row.grant) and (row.needs == nil or Client.Running(row.needs)) then
			byKind[row.kind] = byKind[row.kind] or {}
			table.insert(byKind[row.kind], {
				id = 'opx77_admin_' .. row.id,
				label = row.text and row.text() or locale(row.label),
				group = row.folder and ('%s/%s'):format(locale('admin.target.group'), locale('admin.target.folder.' .. row.folder))
					or locale('admin.target.group'),
				icon = row.icon,
				danger = row.danger == true,
				distance = DISTANCE,
				order = 100 + index,
				canInteract = row.check and 'targetCanInteract' or nil,
				checked = row.state and 'targetChecked' or nil,
				onSelect = 'targetSelect',
				data = { row = row.id },
			})
			ids[#ids + 1] = row.id
		end
	end
	return byKind, table.concat(ids, ',')
end

--- @author DemiAutomatic
--- @method report
--- @description Tells the server how the registration went, so it lands in the server log.
--- @param text {string}
local function report(text)
	TriggerServerEvent('opx77_admin:targetReport', text)
end

--- @author DemiAutomatic
--- @method register
--- @description Replaces this resource's rows on the eye with the granted ones, coroutine only.
--- Never under a pcall: every export answer is awaited, and a yield under a pcall is not safe.
--- @param byKind {table<string, table[]>}
--- @param signature {string}
--- @returns {boolean}
local function register(byKind, signature)
	if signature == registered then return true end
	local _, failure = Client.Call(TARGET, 'clear')
	if failure ~= nil then
		report('clear refused: ' .. tostring(failure))
		return false
	end
	registered = ''
	for _, kind in ipairs(KINDS) do
		local rows = byKind[kind] or {}
		for first = 1, #rows, BATCH do
			local batch = {}
			for index = first, math.min(first + BATCH - 1, #rows) do batch[#batch + 1] = rows[index] end
			local answer, reason = Client.Call(TARGET, REGISTERS[kind], batch)
			if answer == nil then
				local line = ('the %s staff rows were not registered: %s'):format(kind, tostring(reason))
				Open77.log.warn(line)
				report(line)
				Client.Call(TARGET, 'clear')
				registered = nil
				return false
			end
		end
	end
	registered = signature
	local total = 0
	for _, rows in pairs(byKind) do total = total + #rows end
	report(('%d staff rows on the eye'):format(total))
	return true
end

--- @author DemiAutomatic
--- @method sync
--- @description Brings the eye's rows in line with the access map, one registration at a time.
local function sync()
	if not Client.Running(TARGET) then
		registered = nil
		return
	end
	if syncing then
		dirty = true
		return
	end
	syncing = true
	CreateThread(function()
		repeat
			dirty = false
			-- Only the building is guarded; the registration awaits and stays outside the pcall.
			local built, byKind, signature = pcall(wanted)
			if built then
				register(byKind, signature)
			else
				registered = nil
				Open77.log.warn('staff rows: ' .. tostring(byKind))
				report('staff rows not built: ' .. tostring(byKind))
			end
		until not dirty
		syncing = false
	end)
end

--- @author DemiAutomatic
--- @method OpxAdmin.Target.Access
--- @description Takes an access map from the opener or a refresh, and registers what it grants.
--- @param payload {table}
function OpxAdmin.Target.Access(payload)
	if type(payload) ~= 'table' or type(payload.access) ~= 'table' then return end
	access, aclKnown = payload.access, payload.aclKnown == true
	sync()
end

--- @author DemiAutomatic
--- @method rowOf
--- @description The staff row an observation from the eye names, or nil for any other caller.
--- @param context {any}
--- @returns {table|nil}
local function rowOf(context)
	if GetInvokingResource() ~= TARGET or type(context) ~= 'table' then return nil end
	local option = type(context.option) == 'table' and context.option or nil
	local data = option and type(option.data) == 'table' and option.data or nil
	local row = data and BY_ID[data.row] or nil
	if row == nil or not granted(row.grant) or (row.needs ~= nil and not Client.Running(row.needs)) then
		return nil
	end
	return row
end

--- @author DemiAutomatic
--- @export targetCanInteract
--- @description Whether a staff row applies to what the eye hit right now.
--- @param context {table}
--- @returns {boolean}
exports('targetCanInteract', function(context)
	local row = rowOf(context)
	if row == nil then return false end
	return row.check == nil or row.check(context) == true
end)

--- @author DemiAutomatic
--- @export targetSelect
--- @description Runs a picked staff row; the server checks every command again.
--- @param context {table}
--- @returns {boolean}
exports('targetSelect', function(context)
	local row = rowOf(context)
	if row == nil or (row.check ~= nil and row.check(context) ~= true) then return false end
	return row.select(context) == true
end)

--- @author DemiAutomatic
--- @export targetChecked
--- @description The on/off state a staff row's checkbox shows; nil draws no box.
--- @param context {table}
--- @returns {boolean|nil}
exports('targetChecked', function(context)
	local row = rowOf(context)
	if row == nil or row.state == nil then return nil end
	local on = row.state(context)
	if type(on) ~= 'boolean' then return nil end
	return on
end)

--- @author DemiAutomatic
--- @event opx77_admin:bodies
--- @description Takes whether this player's body is hidden and which players are held still, as the server says.
--- @param payload {table} invisible, and frozen as a list of player ids.
RegisterNetEvent('opx77_admin:bodies', function(payload)
	if type(payload) ~= 'table' then return end
	local held = {}
	-- An empty list may not survive the trip as a table: none reads as nobody held.
	for _, value in ipairs(type(payload.frozen) == 'table' and payload.frozen or {}) do
		local id = math.tointeger(tonumber(value) or 0)
		if id ~= nil and id > 0 then held[id] = true end
	end
	invisible, frozenIds = payload.invisible == true, held
end)

CreateThread(function()
	Wait(ACCESS_FIRST_MS)
	while true do
		TriggerServerEvent('opx77_admin:refresh', 'access')
		Wait(ACCESS_EVERY_MS)
	end
end)

--- @author DemiAutomatic
--- @event onClientResourceStart
--- @description Registers the rows again when opx77_target starts after this resource, or when the
--- weather rows gain their provider.
--- @param name {string}
AddEventHandler('onClientResourceStart', function(name)
	if name == TARGET then registered = nil end
	if (name == TARGET or name == WEATHER) and access ~= nil then sync() end
end)

--- @author DemiAutomatic
--- @event onClientResourceStop
--- @description Forgets the rows when opx77_target stops, which drops them itself, and takes the
--- weather rows down with their provider.
--- @param name {string}
AddEventHandler('onClientResourceStop', function(name)
	if name == TARGET then registered = nil end
	if name == WEATHER and access ~= nil then sync() end
end)
