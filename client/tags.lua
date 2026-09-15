--- @author DemiAutomatic
--- @file client/tags.lua
--- @description Staff name tags drawn natively above nearby players' heads.

OpxAdmin = OpxAdmin or {}

local Config = OPX_ADMIN_CONFIG
local Client = OpxAdmin.Client
local Text = OpxAdmin.Text

--- @author DemiAutomatic
--- @type {table}
--- @description What the menu reads the name tag switch from.
OpxAdmin.Tags = {}

--- @author DemiAutomatic
--- @type {table}
--- @description The TAGS config table, or an empty one.
local TAGS = type(Config.TAGS) == 'table' and Config.TAGS or {}

--- @author DemiAutomatic
--- @type {string}
--- @description The client store key the switch is remembered under.
local KVP_KEY = 'tags.shown'

--- @author DemiAutomatic
--- @type {integer}
--- @description Anchors the platform allows one resource.
local ANCHOR_LIMIT = 32

--- @author DemiAutomatic
--- @type {number}
--- @description Metres past DISTANCE a player is looked at early.
local CULL_MARGIN = 1.5

--- @author DemiAutomatic
--- @type {number}
--- @description Metres the head must move before the tag height is sent again.
local OFFSET_STEP = 0.15

--- @author DemiAutomatic
--- @type {integer}
--- @description Times a saved switch is asked back before giving up.
local RESTORE_TRIES = 3

--- @author DemiAutomatic
--- @type {integer}
--- @description Milliseconds before each ask for a saved switch.
local RESTORE_DELAY_MS = 5000

--- @author DemiAutomatic
--- @method setting
--- @description A configured number inside its range, or the fallback.
--- @param value {any}
--- @param fallback {number}
--- @param low {number}
--- @param high {number}
--- @returns {number}
local function setting(value, fallback, low, high)
	local number = Text.Finite(value)
	if number == nil or number < low or number > high then return fallback end
	return number
end

--- @author DemiAutomatic
--- @method colour
--- @description A configured #RRGGBB colour, or the fallback.
--- @param value {any}
--- @param fallback {string}
--- @returns {string}
local function colour(value, fallback)
	if type(value) == 'string' and value:match('^#%x%x%x%x%x%x$') then return value:upper() end
	return fallback
end

--- @author DemiAutomatic
--- @type {table}
--- @description The TAGS.COLORS config table, or an empty one.
local COLORS = type(TAGS.COLORS) == 'table' and TAGS.COLORS or {}

--- @author DemiAutomatic
--- @type {table}
--- @description The TAGS settings read once, each inside its range.
local tuning = {
	distance = setting(TAGS.DISTANCE, 25.0, 1.0, 100.0),
	fadeStart = setting(TAGS.FADE_START, 0.55, 0.0, 1.0),
	headLift = setting(TAGS.HEAD_LIFT, 0.35, 0.0, 2.0),
	headOffset = setting(TAGS.HEAD_OFFSET_Z, 2.05, 0.5, 3.0),
	updateMs = math.floor(setting(TAGS.UPDATE_MS, 250, 50, 2000)),
	max = math.floor(setting(TAGS.MAX, ANCHOR_LIMIT, 1, ANCHOR_LIMIT)),
	own = TAGS.OWN == true,
	hideFirstPerson = TAGS.HIDE_IN_FIRST_PERSON == true,
	technical = TAGS.TECHNICAL ~= false,
	text = colour(COLORS.TEXT, '#F2F6F8'),
	accent = colour(COLORS.ACCENT, '#FCEE0A'),
	staff = colour(COLORS.STAFF, '#22D8E2'),
	background = colour(COLORS.BACKGROUND, '#0A1220'),
}

--- @author DemiAutomatic
--- @type {boolean}
--- @description Whether the server last said this operator's tags are on.
local shown = false

--- @author DemiAutomatic
--- @type {boolean}
--- @description Whether the server answered a switch since this resource started.
local answered = false

--- @author DemiAutomatic
--- @type {table<integer, table>, table<integer, table>}
--- @description Names by player id from the server, and a list still arriving.
local known, incoming = {}, {}

--- @author DemiAutomatic
--- @type {table<integer, table>}
--- @description The anchor drawn for each tagged player id.
local anchors = {}

--- @author DemiAutomatic
--- @type {boolean}
--- @description Whether the update loop is running.
local running = false

--- @author DemiAutomatic
--- @type {boolean}
--- @description Whether opx77_medic last said this operator is down.
local down = false

--- @author DemiAutomatic
--- @type {table<string, boolean>}
--- @description Problems already logged, one line each.
local reported = {}

--- @author DemiAutomatic
--- @method warnOnce
--- @description Logs one problem the first time it happens.
--- @param key {string}
--- @param message {string}
local function warnOnce(key, message)
	if reported[key] then return end
	reported[key] = true
	Open77.log.warn(message)
end

--- @author DemiAutomatic
--- @method OpxAdmin.Tags.IsShown
--- @description Whether this operator's name tags are on, for the menu row.
--- @returns {boolean}
function OpxAdmin.Tags.IsShown()
	return shown
end

--- @author DemiAutomatic
--- @method alphaFor
--- @description Fades a tag over the far part of the distance, in tenths.
--- @param distance {number}
--- @returns {number}
local function alphaFor(distance)
	local start = tuning.distance * tuning.fadeStart
	local alpha = 1.0
	if distance > start and tuning.distance > start then
		alpha = math.max(0.0, 1.0 - (distance - start) / (tuning.distance - start))
	end
	return math.floor(alpha * 10 + 0.5) / 10
end

--- @author DemiAutomatic
--- @method presentationFor
--- @description The whole card table for one player's tag, and its comparison key.
--- @param id {integer}
--- @param row {table}
--- @param alpha {number}
--- @returns {table, string}
local function presentationFor(id, row, alpha)
	local strong = ('%02X'):format(math.floor(alpha * 255 + 0.5))
	local fill = ('%02X'):format(math.floor(alpha * 240 + 0.5))
	local look = {
		label = row.name,
		sublabel = row.staff and locale('admin.tags.staff') or '',
		key = tuning.technical and tostring(id) or '',
		color = tuning.text .. strong,
		accent = (row.staff and tuning.staff or tuning.accent) .. strong,
		background = tuning.background .. fill,
		progress = -1.0,
		showDistance = false,
	}
	return look, table.concat({ look.label, look.sublabel, look.key, look.accent, strong }, '\t')
end

--- @author DemiAutomatic
--- @method headOffset
--- @description Metres from a body's origin to just above its head slot.
--- @param entity {any}
--- @param position {table|nil}
--- @returns {number}
local function headOffset(entity, position)
	local character = Open77.character
	if type(character) ~= 'table' or type(character.bonePosition) ~= 'function' or
		type(position) ~= 'table' then
		return tuning.headOffset
	end
	local read, head, reason = pcall(character.bonePosition, entity, 'head')
	if not read or type(head) ~= 'table' then
		if read and reason ~= 'unknown_bone' and reason ~= 'entity_not_attached' then
			warnOnce('head', ('name tags cannot read the head slot (%s): using TAGS.HEAD_OFFSET_Z')
				:format(tostring(reason)))
		end
		return tuning.headOffset
	end
	local headZ, bodyZ = Text.Finite(head.z), Text.Finite(position.z)
	if headZ == nil or bodyZ == nil then return tuning.headOffset end
	local offset = headZ - bodyZ + tuning.headLift
	if offset < 0.5 or offset > 3.0 then return tuning.headOffset end
	return offset
end

--- @author DemiAutomatic
--- @method thirdPerson
--- @description Whether the view in force is third person, nil when unreadable.
--- @returns {boolean|nil}
local function thirdPerson()
	local perspective = Open77.perspective
	if type(perspective) ~= 'table' or type(perspective.get) ~= 'function' then return nil end
	local read, mode = pcall(perspective.get)
	if not read or type(mode) ~= 'string' then return nil end
	return mode == 'tps'
end

--- @author DemiAutomatic
--- @method drop
--- @description Removes one player's tag anchor.
--- @param id {integer}
local function drop(id)
	local current = anchors[id]
	anchors[id] = nil
	if current and type(Open77.anchors) == 'table' then pcall(Open77.anchors.remove, current.handle) end
end

--- @author DemiAutomatic
--- @method dropAll
--- @description Removes every tag anchor this resource drew.
local function dropAll()
	for id in pairs(anchors) do drop(id) end
	if type(Open77.anchors) == 'table' and type(Open77.anchors.clear) == 'function' then
		pcall(Open77.anchors.clear)
	end
end

--- @author DemiAutomatic
--- @method place
--- @description Creates or patches one player's tag, following their body.
--- @param id {integer}
--- @param entry {table} A players.nearby entry.
--- @param row {table}
--- @param distance {number}
local function place(id, entry, row, distance)
	local api = Open77.anchors
	local offset = headOffset(entry.entity, entry.position)
	local look, key = presentationFor(id, row, alphaFor(distance))
	local current = anchors[id]
	if current and current.entity ~= entry.entity then
		drop(id)
		current = nil
	end

	if current == nil then
		local called, handle, reason = pcall(api.create, {
			entity = entry.entity,
			offset = { x = 0.0, y = 0.0, z = offset },
			tag = 'player.' .. id,
			maxDistance = tuning.distance,
			render = 'card',
			presentation = look,
		})
		if not called or not handle then
			warnOnce('create', ('a name tag was refused: %s'):format(tostring(called and reason or handle)))
			return
		end
		anchors[id] = { handle = handle, entity = entry.entity, offset = offset, key = key }
		return
	end

	local patch
	if math.abs(current.offset - offset) >= OFFSET_STEP then
		patch = { offset = { x = 0.0, y = 0.0, z = offset } }
		current.offset = offset
	end
	if current.key ~= key then
		patch = patch or {}
		patch.presentation = look
		current.key = key
	end
	if patch == nil then return end
	local called, ok = pcall(api.update, current.handle, patch)
	if not called or not ok then drop(id) end
end

--- @author DemiAutomatic
--- @method tick
--- @description Tags every known player in range, nearest first, and drops the rest.
local function tick()
	local api, players = Open77.anchors, Open77.players
	if type(api) ~= 'table' or type(api.create) ~= 'function' or type(api.update) ~= 'function' then
		return warnOnce('anchors', 'Open77.anchors is not on this client: name tags cannot be drawn')
	end
	if type(players) ~= 'table' or type(players.nearby) ~= 'function' then
		return warnOnce('nearby', 'Open77.players.nearby is not on this client: name tags cannot be drawn')
	end

	local third = thirdPerson()
	local wanted = {}
	if not down and not (tuning.hideFirstPerson and third == false) then
		local read, entries = pcall(players.nearby, tuning.distance + CULL_MARGIN,
			{ includeSelf = tuning.own, limit = tuning.max })
		for _, entry in ipairs(read and type(entries) == 'table' and entries or {}) do
			local id = type(entry) == 'table' and tonumber(entry.playerId) or nil
			local row = id and known[id] or nil
			local distance = row and Text.Finite(entry.distance) or nil
			if distance and entry.entity ~= nil and (entry.isLocal ~= true or third == true) then
				wanted[id] = true
				place(id, entry, row, distance)
			end
		end
	end
	for id in pairs(anchors) do
		if not wanted[id] then drop(id) end
	end
end

--- @author DemiAutomatic
--- @method run
--- @description Starts the update loop, which clears every tag when it ends.
local function run()
	if running then return end
	running = true
	CreateThread(function()
		while shown do
			local ticked, failure = pcall(tick)
			if not ticked then warnOnce('tick', 'name tag update failed: ' .. tostring(failure)) end
			Wait(tuning.updateMs)
		end
		dropAll()
		running = false
		if shown then run() end
	end)
end

--- @author DemiAutomatic
--- @method remember
--- @description Saves the switch on this machine for this server.
--- @param on {boolean}
local function remember(on)
	local kvp = Open77.kvp
	if type(kvp) ~= 'table' or type(kvp.set) ~= 'function' then
		return warnOnce('kvp', 'Open77.kvp is not on this client: the name tag switch lasts this session only')
	end
	local called, ok, reason = pcall(kvp.set, KVP_KEY, on)
	if not called or not ok then
		warnOnce('kvpSet', ('the name tag switch was not saved: %s'):format(tostring(called and reason or ok)))
	end
end

--- @author DemiAutomatic
--- @event opx77_admin:tagsState
--- @description Turns the tags on or off as the server decided.
--- @param on {boolean}
--- @param persist {boolean} Whether to save it as the preference.
RegisterNetEvent('opx77_admin:tagsState', function(on, persist)
	answered = true
	shown = on == true
	if persist == true then remember(shown) end
	if shown then
		run()
	else
		known, incoming = {}, {}
		if not running then dropAll() end
	end
	OpxAdmin.Menu.Refresh()
end)

--- @author DemiAutomatic
--- @event opx77_admin:tagRows
--- @description Collects the name list chunks the server sends to staff.
--- @param payload {table}
RegisterNetEvent('opx77_admin:tagRows', function(payload)
	if not shown or type(payload) ~= 'table' or type(payload.rows) ~= 'table' then return end
	if payload.offset == 0 then incoming = {} end
	for _, entry in ipairs(payload.rows) do
		local id = tonumber(type(entry) == 'table' and entry.id or nil)
		if id and type(entry.name) == 'string' then
			incoming[id] = { name = Text.Bytes(entry.name, 192), staff = entry.staff == true }
		end
	end
	if payload.done ~= true then return end
	known, incoming = incoming, {}
end)

--- @author DemiAutomatic
--- @event onClientResourceStart
--- @description Asks the server back for tags this operator left on.
--- @param name {string}
AddEventHandler('onClientResourceStart', function(name)
	if name ~= Client.RESOURCE then return end
	local kvp = Open77.kvp
	if type(kvp) ~= 'table' or type(kvp.get) ~= 'function' then return end
	local read, saved = pcall(kvp.get, KVP_KEY, false)
	if not read or saved ~= true then return end
	CreateThread(function()
		for _ = 1, RESTORE_TRIES do
			Wait(RESTORE_DELAY_MS)
			if answered then return end
			TriggerServerEvent('opx77_admin:tagsRestore')
		end
	end)
end)

--- @author DemiAutomatic
--- @event opx77:medic:stateChanged
--- @description Hides every tag while this operator is down.
--- @param payload {table} down and waiting.
AddEventHandler('opx77:medic:stateChanged', function(payload)
	if type(payload) ~= 'table' then return end
	down = payload.down == true
end)

--- @author DemiAutomatic
--- @event open77:worldReady
--- @description Forgets the tag handles a world exit already removed.
AddEventHandler('open77:worldReady', function()
	anchors = {}
end)

--- @author DemiAutomatic
--- @event onClientResourceStop
--- @description Removes every tag when this resource stops.
--- @param name {string}
AddEventHandler('onClientResourceStop', function(name)
	if name ~= Client.RESOURCE then return end
	shown = false
	dropAll()
end)
