--- @author DemiAutomatic
--- @file server/world.lua
--- @description Saved destinations, announcements, and the roster, status and audit reads.

local Config = OPX_ADMIN_CONFIG
local Server = OpxAdmin.Server
local Text = OpxAdmin.Text

local answer, refuse, audit, tell = Server.Answer, Server.Refuse, Server.Audit, Server.Tell
local count = Server.Count

--- @author DemiAutomatic
--- @type {integer}
--- @description Shape version of the destinations carried across a reload.
local STATE_PROTOCOL = 1

--- @author DemiAutomatic
--- @type {table<string, AdminLocation>}
--- @description Every destination by name, configured and added in game.
local locations = {}

--- @author DemiAutomatic
--- @type {table<string, AdminLocation>}
--- @description Destinations added in game this run, by name.
local runtime = {}

--- @author DemiAutomatic
--- @method locationOf
--- @description Builds one destination from typed or stored values, nil when unusable.
--- @param name {any}
--- @param label {any}
--- @param x {any}
--- @param y {any}
--- @param z {any}
--- @param heading {any}
--- @param isRuntime {boolean}
--- @returns {AdminLocation|nil}
local function locationOf(name, label, x, y, z, heading, isRuntime)
	name = Text.Slug(name)
	x, y, z = Text.Finite(x), Text.Finite(y), Text.Finite(z)
	if name == nil or x == nil or y == nil or z == nil then return nil end
	return { name = name, label = Text.Clean(label, 48) or name, x = x, y = y, z = z,
		heading = Text.Finite(heading) or 0.0, runtime = isRuntime }
end

--- @author DemiAutomatic
--- @method seed
--- @description Rebuilds the destination list from config, then the in-game additions.
local function seed()
	locations = {}
	for position, row in ipairs(type(Config.LOCATIONS) == 'table' and Config.LOCATIONS or {}) do
		local location = type(row) == 'table'
			and locationOf(row.NAME, row.LABEL, row.X, row.Y, row.Z, row.HEADING, false) or nil
		if location == nil then
			Open77.log.warn(('LOCATIONS #%d ignored: NAME must be a slug and X, Y, Z numbers')
				:format(position))
		else
			locations[location.name] = location
		end
	end
	for name, row in pairs(runtime) do locations[name] = row end
end

--- @author DemiAutomatic
--- @method hasState
--- @description Whether the host offers the reload state store.
--- @returns {boolean}
local function hasState()
	return type(Open77.state) == 'table' and type(Open77.state.save) == 'function'
		and type(Open77.state.load) == 'function'
end

--- @author DemiAutomatic
--- @method save
--- @description Hands the in-game destinations to the host reload store.
local function save()
	if not hasState() then return end
	local list = {}
	for _, row in pairs(runtime) do list[#list + 1] = row end
	pcall(Open77.state.save, { protocol = STATE_PROTOCOL, locations = list })
end

--- @author DemiAutomatic
--- @method restore
--- @description Adopts the destinations carried across a reload, when the shape matches.
local function restore()
	if not hasState() then return end
	local read, carried = pcall(Open77.state.load)
	if not read or type(carried) ~= 'table' or carried.protocol ~= STATE_PROTOCOL then return end
	for _, row in ipairs(type(carried.locations) == 'table' and carried.locations or {}) do
		local location = type(row) == 'table'
			and locationOf(row.name, row.label, row.x, row.y, row.z, row.heading, true) or nil
		if location then runtime[location.name] = location end
	end
end

restore()
seed()

--- @author DemiAutomatic
--- @method OpxAdmin.Server.Locations
--- @description Answers every destination, sorted by name, as the menu draws it.
--- @returns {AdminLocation[]}
function OpxAdmin.Server.Locations()
	local list = {}
	for _, row in pairs(locations) do list[#list + 1] = row end
	table.sort(list, function(left, right) return left.name < right.name end)
	return list
end

--- @author DemiAutomatic
--- @command /opx77.admin.player.send
--- @description Places a player at a saved destination.
Server.Command('opx77.admin.player.send', {
	help = 'admin.help.send',
	params = { { name = 'playerId|me', help = 'admin.help.playerOrMe' },
		{ name = 'location', help = 'admin.help.locationName' } },
	handler = function(source, args, raw)
		if count(args) ~= 2 then return answer(source, raw, false, 'admin.usage.send') end
		local playerId = Server.Target(source, raw, args[1])
		if playerId == nil then return end
		local location = locations[tostring(args[2]):lower()]
		if location == nil then return refuse(source, raw, 'unknown_location') end
		local placed, placeCode, reason = Server.Place(playerId,
			{ x = location.x, y = location.y, z = location.z }, location.heading, nil, 'send')
		audit(source, 'admin.player.send', placed, playerId, ('%s %s'):format(location.name,
			placeCode or ''))
		if not placed then return refuse(source, raw, placeCode, { reason = reason, id = playerId }) end
		if playerId ~= source then tell(playerId, 'admin.toast.sent', { label = location.label }) end
		answer(source, raw, true, 'admin.done.sent',
			{ id = playerId, name = Server.NameOf(playerId) or '?', label = location.label })
	end,
})

--- @author DemiAutomatic
--- @command /opx77.admin.world.loc.add
--- @description Saves where the operator stands as a destination until restart.
Server.Command('opx77.admin.world.loc.add', {
	help = 'admin.help.locAdd',
	params = { { name = 'name', help = 'admin.help.locationName' },
		{ name = 'label', help = 'admin.help.locationLabel', optional = true } },
	inGame = true,
	handler = function(source, args, raw)
		local name = Text.Slug(args[1])
		if name == nil then return refuse(source, raw, 'bad_location_name') end
		local position = Server.PositionOf(source)
		if position == nil then return refuse(source, raw, 'no_position') end
		local label = Text.Clean(Text.Rest(args, 2), 48) or name
		runtime[name] = { name = name, label = label, x = position.x, y = position.y, z = position.z,
			heading = 0.0, runtime = true }
		save()
		seed()
		audit(source, 'admin.world.loc.add', true, nil,
			('%s %.1f %.1f %.1f'):format(name, position.x, position.y, position.z))
		answer(source, raw, true, 'admin.done.locAdded', { name = name, label = label })
	end,
})

--- @author DemiAutomatic
--- @command /opx77.admin.world.loc.remove
--- @description Forgets a destination that was added in game.
Server.Command('opx77.admin.world.loc.remove', {
	help = 'admin.help.locRemove', params = { { name = 'name', help = 'admin.help.locationName' } },
	handler = function(source, args, raw)
		local name = Text.Slug(args[1])
		if name == nil or locations[name] == nil then return refuse(source, raw, 'unknown_location') end
		if runtime[name] == nil then return refuse(source, raw, 'seeded_location') end
		runtime[name] = nil
		save()
		seed()
		audit(source, 'admin.world.loc.remove', true, nil, name)
		answer(source, raw, true, 'admin.done.locRemoved', { name = name })
	end,
})

--- @author DemiAutomatic
--- @command /opx77.admin.read.locations
--- @description Lists every destination as a chat report.
Server.Command('opx77.admin.read.locations', {
	help = 'admin.help.readLocations', read = true,
	handler = function(source, _, raw)
		local list = Server.Locations()
		local lines = { locale('admin.locations.header', { count = #list }) }
		for _, row in ipairs(list) do
			lines[#lines + 1] = locale(row.runtime and 'admin.locations.runtime' or 'admin.locations.row',
				{ name = row.name, label = row.label, x = ('%.1f'):format(row.x),
					y = ('%.1f'):format(row.y), z = ('%.1f'):format(row.z) })
		end
		answer(source, raw, true, 'admin.text.lines', { lines = table.concat(lines, '\n') })
	end,
})

--- @author DemiAutomatic
--- @command /opx77.admin.world.announce
--- @description Sends an announcement toast to every player, and a chat line.
Server.Command('opx77.admin.world.announce', {
	help = 'admin.help.announce', params = { { name = 'text', help = 'admin.help.announceText' } },
	handler = function(source, args, raw)
		local settings = Config.ANNOUNCE or {}
		local text = Text.Clean(Text.Rest(args, 1),
			math.max(1, math.floor(Server.Setting(settings.MAX_CHARACTERS, 240))))
		if text == nil then return refuse(source, raw, 'empty_text') end

		local notifications = Open77.notifications
		local delivered = 0
		if type(notifications) == 'table' and type(notifications.send) == 'function' then
			local read, players = pcall(Open77.players.all)
			for _, playerId in ipairs(read and type(players) == 'table' and players or {}) do
				local sent = pcall(notifications.send, tonumber(playerId), {
					type = 'warning',
					title = locale('admin.announce.title'),
					message = text,
					durationMs = math.floor(Server.Setting(settings.DURATION_MS, 12000)),
				})
				if sent then delivered = delivered + 1 end
			end
		end
		if settings.CHAT ~= false then
			TriggerClientEvent('chat:addMessage', -1, {
				type = 'system',
				author = locale('admin.announce.title'),
				text = text,
			})
		end
		audit(source, 'admin.world.announce', true, nil, text)
		answer(source, raw, true, 'admin.done.announced', { count = delivered })
	end,
})

--- @author DemiAutomatic
--- @type {integer}
--- @description Host clock when this file loaded, for the uptime.
local startedAtMs = Server.NowMs()

--- @author DemiAutomatic
--- @method OpxAdmin.Server.RosterRow
--- @description Builds one roster row as the server sees the player.
--- @param playerId {integer}
--- @param origin {table|nil} The operator's position, for the distance.
--- @returns {AdminRosterRow|nil}
function OpxAdmin.Server.RosterRow(playerId, origin)
	local name = Server.NameOf(playerId)
	if name == nil then return nil end
	local position = Server.PositionOf(playerId)
	local life = Server.LifeOf(playerId)
	local state = 'loading'
	if life ~= nil then
		local admitted = Server.Admit(playerId)
		local deadRead, dead = pcall(Open77.players.isDead, playerId)
		state = not admitted and 'gate' or (deadRead and dead == true) and 'down' or 'up'
	end
	local distance
	if origin and position and origin.bucket == position.bucket then
		local dx, dy, dz = position.x - origin.x, position.y - origin.y, position.z - origin.z
		distance = math.floor(math.sqrt(dx * dx + dy * dy + dz * dz) + 0.5)
	end
	return { id = playerId, name = name, state = state,
		bucket = position and position.bucket or 0, distance = distance }
end

--- @author DemiAutomatic
--- @method OpxAdmin.Server.PlayerIds
--- @description Answers every connected player id, sorted.
--- @returns {integer[]}
function OpxAdmin.Server.PlayerIds()
	local read, players = pcall(Open77.players.all)
	local ids = {}
	for _, value in ipairs(read and type(players) == 'table' and players or {}) do
		local id = tonumber(value)
		if id and id > 0 then ids[#ids + 1] = id end
	end
	table.sort(ids)
	return ids
end

--- @author DemiAutomatic
--- @command /opx77.admin.read.players
--- @description Lists every connected player with state, bucket and distance.
Server.Command('opx77.admin.read.players', {
	help = 'admin.help.readPlayers', read = true,
	handler = function(source, _, raw)
		local origin = source > 0 and Server.PositionOf(source) or nil
		local ids = Server.PlayerIds()
		local lines = { locale('admin.players.header', { count = #ids }) }
		for _, playerId in ipairs(ids) do
			local row = Server.RosterRow(playerId, origin)
			if row then
				lines[#lines + 1] = locale('admin.players.row', {
					id = row.id, name = row.name, state = locale('admin.state.' .. row.state),
					bucket = row.bucket, distance = row.distance and (row.distance .. 'm') or '-',
				})
			end
		end
		answer(source, raw, true, 'admin.text.lines', { lines = table.concat(lines, '\n') })
	end,
})

--- @author DemiAutomatic
--- @type {string[]}
--- @description Resources whose state the status report names.
local WATCHED = { 'opx77_core', 'opx77_menu', 'opx77_input', 'opx77_notify', 'opx77_chat',
	'opx77_appearance', 'opx77_weather', OpxAdmin.Inventory.RESOURCE,
	'open77_weapons', 'open77_admin' }

--- @author DemiAutomatic
--- @command /opx77.admin.read.status
--- @description Reports counts, uptime and the state of related resources.
Server.Command('opx77.admin.read.status', {
	help = 'admin.help.readStatus', read = true,
	handler = function(source, _, raw)
		local ids = Server.PlayerIds()
		local up = 0
		for _, playerId in ipairs(ids) do
			if Server.Admit(playerId) then up = up + 1 end
		end
		local states = {}
		for _, name in ipairs(WATCHED) do
			local read, state = pcall(GetResourceState, name)
			states[#states + 1] = ('%s=%s'):format(name, read and tostring(state or '?') or '?')
		end
		local lines = {
			locale('admin.status.summary', {
				players = #ids, up = up, vehicles = Server.SpawnedCount(),
				minutes = math.floor((Server.NowMs() - startedAtMs) / 60000),
			}),
			table.concat(states, '  '),
		}
		answer(source, raw, true, 'admin.text.lines', { lines = table.concat(lines, '\n') })
	end,
})

--- @author DemiAutomatic
--- @command /opx77.admin.read.audit
--- @description Lists the latest staff actions of this uptime.
Server.Command('opx77.admin.read.audit', {
	help = 'admin.help.readAudit',
	params = { { name = 'count', help = 'admin.help.auditCount', optional = true } }, read = true,
	handler = function(source, args, raw)
		local wanted = math.min(40, math.max(1, Text.Integer(args[1]) or 15))
		local entries = Server.Recent(wanted)
		local lines = { locale('admin.audit.header', { count = #entries }) }
		local atMs = Server.NowMs()
		for _, entry in ipairs(entries) do
			lines[#lines + 1] = locale(entry.ok and 'admin.audit.row' or 'admin.audit.rowFailed', {
				seq = entry.seq,
				minutes = math.floor((atMs - entry.atMs) / 60000),
				actor = entry.actorName,
				event = entry.event,
				target = entry.target and ('%s (%d)'):format(entry.targetName or '?', entry.target) or '-',
				detail = entry.detail,
			})
		end
		answer(source, raw, true, 'admin.text.lines', { lines = table.concat(lines, '\n') })
	end,
})
