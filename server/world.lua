--- Saved destinations, announcements, and the read commands: the roster, the server status and
--- the audit. Time and weather are not here: opx77_weather owns them, its commands are already
--- ACL-gated, and the menu drives those commands rather than standing up a second authority.

local Config = OPX_ADMIN_CONFIG
local Server = OpxAdmin.Server
local Text = OpxAdmin.Text

local answer, refuse, audit, tell = Server.answer, Server.refuse, Server.audit, Server.tell
local count = Server.count

-- ---------------------------------------------------------------------------
-- Destinations
--
-- The configured list is the durable one. Destinations added in game live in Open77.state,
-- which the host carries across a reload of this resource and drops when it stops: a runtime
-- addition is a scratchpad, and /opx77.admin.self.pos is how a spot becomes a config row.
-- ---------------------------------------------------------------------------

local STATE_PROTOCOL = 1

--- name -> { name, label, x, y, z, heading, runtime }
local locations = {}
local runtime = {}

local function seed()
	locations = {}
	for position, row in ipairs(type(Config.LOCATIONS) == 'table' and Config.LOCATIONS or {}) do
		local name = type(row) == 'table' and Text.slug(row.NAME) or nil
		local valid = type(row) == 'table'
		local x = valid and Text.finite(row.X) or nil
		local y = valid and Text.finite(row.Y) or nil
		local z = valid and Text.finite(row.Z) or nil
		if name == nil or x == nil or y == nil or z == nil then
			Open77.log.warn(('LOCATIONS #%d ignored: NAME must be a slug and X, Y, Z numbers')
				:format(position))
		else
			locations[name] = { name = name, label = Text.clean(row.LABEL, 48) or name, x = x, y = y,
				z = z, heading = Text.finite(row.HEADING) or 0.0, runtime = false }
		end
	end
	-- an in-game addition under a configured name replaces it for this run
	for name, row in pairs(runtime) do locations[name] = row end
end

---@return boolean
local function hasState()
	return type(Open77.state) == 'table' and type(Open77.state.save) == 'function'
		and type(Open77.state.load) == 'function'
end

local function save()
	if not hasState() then return end
	local list = {}
	for _, row in pairs(runtime) do list[#list + 1] = row end
	pcall(Open77.state.save, { protocol = STATE_PROTOCOL, locations = list })
end

--- Carried state is untrusted input: a reload may have changed this file, so a shape this
--- version does not know is refused whole rather than half-adopted.
local function restore()
	if not hasState() then return end
	local read, carried = pcall(Open77.state.load)
	if not read or type(carried) ~= 'table' or carried.protocol ~= STATE_PROTOCOL then return end
	for _, row in ipairs(type(carried.locations) == 'table' and carried.locations or {}) do
		local name = type(row) == 'table' and Text.slug(row.name) or nil
		local valid = type(row) == 'table'
		local x = valid and Text.finite(row.x) or nil
		local y = valid and Text.finite(row.y) or nil
		local z = valid and Text.finite(row.z) or nil
		if name and x and y and z then
			runtime[name] = { name = name, label = Text.clean(row.label, 48) or name, x = x, y = y, z = z,
				heading = Text.finite(row.heading) or 0.0, runtime = true }
		end
	end
end

restore()
seed()

--- Every destination, sorted by name, as the menu draws it.
---@return AdminLocation[]
function Server.locations()
	local list = {}
	for _, row in pairs(locations) do list[#list + 1] = row end
	table.sort(list, function(left, right) return left.name < right.name end)
	return list
end

Server.command('opx77.admin.player.send', {
	help = 'admin.help.send',
	params = { { name = 'playerId|me', help = 'admin.help.playerOrMe' },
		{ name = 'location', help = 'admin.help.locationName' } },
	handler = function(source, args, raw)
		if count(args) ~= 2 then return answer(source, raw, false, 'admin.usage.send') end
		local playerId, code = Server.target(source, args[1])
		if playerId == nil then return refuse(source, raw, code) end
		local location = locations[tostring(args[2]):lower()]
		if location == nil then return refuse(source, raw, 'unknown_location') end
		local placed, placeCode, reason = Server.place(playerId,
			{ x = location.x, y = location.y, z = location.z }, location.heading, nil, 'send')
		audit(source, 'admin.player.send', placed, playerId, ('%s %s'):format(location.name,
			placeCode or ''))
		if not placed then return refuse(source, raw, placeCode, { reason = reason, id = playerId }) end
		if playerId ~= source then tell(playerId, 'admin.toast.sent', { label = location.label }) end
		answer(source, raw, true, 'admin.done.sent',
			{ id = playerId, name = Server.nameOf(playerId) or '?', label = location.label })
	end,
})

Server.command('opx77.admin.world.loc.add', {
	help = 'admin.help.locAdd',
	params = { { name = 'name', help = 'admin.help.locationName' },
		{ name = 'label', help = 'admin.help.locationLabel', optional = true } },
	inGame = true,
	handler = function(source, args, raw)
		local name = Text.slug(args[1])
		if name == nil then return refuse(source, raw, 'bad_location_name') end
		local position = Server.positionOf(source)
		if position == nil then return refuse(source, raw, 'no_position') end
		local label = Text.clean(Text.rest(args, 2), 48) or name
		runtime[name] = { name = name, label = label, x = position.x, y = position.y, z = position.z,
			heading = 0.0, runtime = true }
		save()
		seed()
		audit(source, 'admin.world.loc.add', true, nil,
			('%s %.1f %.1f %.1f'):format(name, position.x, position.y, position.z))
		answer(source, raw, true, 'admin.done.locAdded', { name = name, label = label })
	end,
})

Server.command('opx77.admin.world.loc.remove', {
	help = 'admin.help.locRemove', params = { { name = 'name', help = 'admin.help.locationName' } },
	handler = function(source, args, raw)
		local name = Text.slug(args[1])
		if name == nil or locations[name] == nil then return refuse(source, raw, 'unknown_location') end
		if runtime[name] == nil then return refuse(source, raw, 'seeded_location') end
		runtime[name] = nil
		save()
		seed()
		audit(source, 'admin.world.loc.remove', true, nil, name)
		answer(source, raw, true, 'admin.done.locRemoved', { name = name })
	end,
})

Server.command('opx77.admin.read.locations', {
	help = 'admin.help.readLocations', read = true,
	handler = function(source, _, raw)
		local lines = { locale('admin.locations.header', { count = #Server.locations() }) }
		for _, row in ipairs(Server.locations()) do
			lines[#lines + 1] = locale(row.runtime and 'admin.locations.runtime' or 'admin.locations.row',
				{ name = row.name, label = row.label, x = ('%.1f'):format(row.x),
					y = ('%.1f'):format(row.y), z = ('%.1f'):format(row.z) })
		end
		answer(source, raw, true, 'admin.text.lines', { lines = table.concat(lines, '\n') })
	end,
})

-- ---------------------------------------------------------------------------
-- Announcements
-- ---------------------------------------------------------------------------

Server.command('opx77.admin.world.announce', {
	help = 'admin.help.announce', params = { { name = 'text', help = 'admin.help.announceText' } },
	handler = function(source, args, raw)
		local settings = Config.ANNOUNCE or {}
		local text = Text.clean(Text.rest(args, 1),
			math.max(1, math.floor(Server.setting(settings.MAX_CHARACTERS, 240))))
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
					durationMs = math.floor(Server.setting(settings.DURATION_MS, 12000)),
				})
				if sent then delivered = delivered + 1 end
			end
		end
		if settings.CHAT ~= false then
			TriggerClientEvent('chat:addMessage', -1, {
				type = 'system',
				author = locale('admin.announce.title'),
				text = text,
				color = { 245, 196, 80 },
			})
		end
		audit(source, 'admin.world.announce', true, nil, text)
		answer(source, raw, true, 'admin.done.announced', { count = delivered })
	end,
})

-- ---------------------------------------------------------------------------
-- Reads
-- ---------------------------------------------------------------------------

local startedAtMs = Server.nowMs()

--- One roster row as the server sees it. No character: the citizen id and name live in
--- opx77_core's VM, which nothing here can ask. The menu's record row runs opx77.where.
---@param playerId integer
---@param origin table|nil  the operator's position, for the distance
---@return AdminRosterRow|nil
function Server.rosterRow(playerId, origin)
	local name = Server.nameOf(playerId)
	if name == nil then return nil end
	local position = Server.positionOf(playerId)
	local life = Server.lifeOf(playerId)
	local state = 'loading'
	if life ~= nil then
		local admitted = Server.admit(playerId)
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

--- Every connected player id, sorted.
---@return integer[]
function Server.playerIds()
	local read, players = pcall(Open77.players.all)
	local ids = {}
	for _, value in ipairs(read and type(players) == 'table' and players or {}) do
		local id = tonumber(value)
		if id and id > 0 then ids[#ids + 1] = id end
	end
	table.sort(ids)
	return ids
end

Server.command('opx77.admin.read.players', {
	help = 'admin.help.readPlayers', read = true,
	handler = function(source, _, raw)
		local origin = source > 0 and Server.positionOf(source) or nil
		local ids = Server.playerIds()
		local lines = { locale('admin.players.header', { count = #ids }) }
		for _, playerId in ipairs(ids) do
			local row = Server.rosterRow(playerId, origin)
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

--- The OPX//77 set and the platform packages this one leans on or collides with. There is no
--- way to enumerate resources: GetResourceState answers only for a name already known.
local WATCHED = { 'opx77_core', 'opx77_menu', 'opx77_input', 'opx77_notify', 'opx77_chat',
	'opx77_appearance', 'opx77_weather', OpxAdmin.Inventory.RESOURCE,
	'open77_weapons', 'open77_admin' }

Server.command('opx77.admin.read.status', {
	help = 'admin.help.readStatus', read = true,
	handler = function(source, _, raw)
		local ids = Server.playerIds()
		local up = 0
		for _, playerId in ipairs(ids) do
			if Server.admit(playerId) then up = up + 1 end
		end
		local states = {}
		for _, name in ipairs(WATCHED) do
			local read, state = pcall(GetResourceState, name)
			states[#states + 1] = ('%s=%s'):format(name, read and tostring(state or '?') or '?')
		end
		local lines = {
			locale('admin.status.summary', {
				players = #ids, up = up, vehicles = Server.spawnedCount(),
				minutes = math.floor((Server.nowMs() - startedAtMs) / 60000),
			}),
			table.concat(states, '  '),
		}
		answer(source, raw, true, 'admin.text.lines', { lines = table.concat(lines, '\n') })
	end,
})

Server.command('opx77.admin.read.audit', {
	help = 'admin.help.readAudit',
	params = { { name = 'count', help = 'admin.help.auditCount', optional = true } }, read = true,
	handler = function(source, args, raw)
		local wanted = math.min(40, math.max(1, Text.integer(args[1]) or 15))
		local entries = Server.recent(wanted)
		local lines = { locale('admin.audit.header', { count = #entries }) }
		local atMs = Server.nowMs()
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
