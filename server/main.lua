--- @author DemiAutomatic
--- @file server/main.lua
--- @description Answers, audit, readiness gate, placement and the command registry.

OpxAdmin = OpxAdmin or {}

local Config = OPX_ADMIN_CONFIG
local Text = OpxAdmin.Text

--- @author DemiAutomatic
--- @type {table}
--- @description Server-half helpers every staff command file reads.
OpxAdmin.Server = {}
local Server = OpxAdmin.Server

--- @author DemiAutomatic
--- @type {string}
--- @description This resource's name, which placement kills are attributed to.
local RESOURCE = GetCurrentResourceName()

--- @author DemiAutomatic
--- @type {integer}
--- @description Last good monotonic reading in milliseconds, held on failure.
local lastMs = 0

--- @author DemiAutomatic
--- @method OpxAdmin.Server.NowMs
--- @description Host-monotonic milliseconds, holding the last good reading.
--- @returns {integer}
function OpxAdmin.Server.NowMs()
	local read, seconds = pcall(Open77.time.monotonic)
	if read and type(seconds) == 'number' and seconds == seconds and
		seconds >= 0 and seconds < math.huge then
		lastMs = math.floor(seconds * 1000)
	end
	return lastMs
end
local nowMs = Server.NowMs

--- @author DemiAutomatic
--- @method OpxAdmin.Server.Setting
--- @description A configured number, or the fallback when it is unusable.
--- @param value {any}
--- @param fallback {number}
--- @returns {number}
function OpxAdmin.Server.Setting(value, fallback)
	return Text.Finite(value) or fallback
end

--- @author DemiAutomatic
--- @method OpxAdmin.Server.Count
--- @description How many arguments were typed, read from args.n first.
--- @param args {table}
--- @returns {integer}
function OpxAdmin.Server.Count(args)
	local given = Text.Integer(args.n)
	if given == nil or given < 0 then return #args end
	return given
end

--- @author DemiAutomatic
--- @type {table<string, string>}
--- @description Catalogue key a player reads for each refusal code.
local ERRORS = {
	in_game_only = 'admin.error.inGameOnly',
	too_fast = 'admin.error.tooFast',
	failed = 'admin.error.failed',
	no_target = 'admin.error.noTarget',
	bad_target = 'admin.error.badTarget',
	console_has_no_player = 'admin.error.consoleNoPlayer',
	not_connected = 'admin.error.notConnected',
	self_target = 'admin.error.selfTarget',
	not_incarnated = 'admin.error.notIncarnated',
	gate_closed = 'admin.error.gateClosed',
	gate_unreadable = 'admin.error.gateUnreadable',
	no_position = 'admin.error.noPosition',
	kill_refused = 'admin.error.killRefused',
	respawn_refused = 'admin.error.respawnRefused',
	refused = 'admin.error.refused',
	bad_coordinates = 'admin.error.badCoordinates',
	bad_switch = 'admin.error.badSwitch',
	bad_duration = 'admin.error.badDuration',
	empty_text = 'admin.error.emptyText',
	unknown_vehicle = 'admin.error.unknownVehicle',
	vehicle_cap = 'admin.error.vehicleCap',
	no_vehicle = 'admin.error.noVehicle',
	occupied = 'admin.error.occupied',
	unsafe_repair = 'admin.error.unsafeRepair',
	bad_scope = 'admin.error.badScope',
	unknown_flag = 'admin.error.unknownFlag',
	not_ours = 'admin.error.notOurs',
	vehicles_unavailable = 'admin.error.vehiclesUnavailable',
	unknown_weapon = 'admin.error.unknownWeapon',
	weapons_unavailable = 'admin.error.weaponsUnavailable',
	weapon_no_answer = 'admin.error.weaponNoAnswer',
	unknown_ammo = 'admin.error.unknownAmmo',
	melee_no_ammo = 'admin.error.meleeNoAmmo',
	give_partial = 'admin.error.givePartial',
	inventory_unavailable = 'admin.error.inventoryUnavailable',
	inventory_denied = 'admin.error.inventoryDenied',
	bad_holder = 'admin.error.badHolder',
	no_character = 'admin.error.noCharacter',
	unknown_citizen = 'admin.error.unknownCitizen',
	core_unavailable = 'admin.error.coreUnavailable',
	unknown_item = 'admin.error.unknownItem',
	bad_count = 'admin.error.badCount',
	not_enough = 'admin.error.notEnough',
	bag_no_room = 'admin.error.bagNoRoom',
	bag_too_heavy = 'admin.error.bagTooHeavy',
	unknown_location = 'admin.error.unknownLocation',
	bad_location_name = 'admin.error.badLocationName',
	seeded_location = 'admin.error.seededLocation',
}

--- @author DemiAutomatic
--- @type {table<string, boolean>}
--- @description Refusal codes about typed input, answered as warnings.
local TYPED = {
	too_fast = true, no_target = true, bad_target = true, self_target = true,
	bad_coordinates = true, bad_switch = true, bad_duration = true, empty_text = true,
	unknown_vehicle = true, bad_scope = true, unknown_flag = true, unknown_weapon = true,
	unknown_location = true, bad_location_name = true, bad_holder = true, unknown_citizen = true,
	unknown_item = true, bad_count = true, not_enough = true, unknown_ammo = true,
	melee_no_ammo = true,
}

--- @author DemiAutomatic
--- @type {string}
--- @description Catalogue key a report is answered with, drawn as chat.
local REPORT = 'admin.text.lines'

--- @author DemiAutomatic
--- @method OpxAdmin.Server.Answer
--- @description Answers a player through the client half, the console in English.
--- @param source {integer}
--- @param raw {string}
--- @param ok {boolean}
--- @param key {string}
--- @param params {table|nil}
--- @param kind {string|nil} info, success, warning or error; inferred when nil.
--- @returns {boolean}
function OpxAdmin.Server.Answer(source, raw, ok, key, params, kind)
	local player = tonumber(source) or 0
	if player > 0 then
		if key == REPORT then
			kind = 'report'
		elseif kind == nil then
			if ok then
				kind = 'success'
			else
				kind = key:sub(1, 12) == 'admin.usage.' and 'warning' or 'error'
			end
		end
		TriggerClientEvent('opx77_admin:answer', player, raw or '', ok == true,
			locale(key, params), kind)
	else
		local line = OpxAdmin.Locale.English(key, params)
		if ok then Open77.log.info(line) else Open77.log.warn(line) end
	end
	return ok == true
end

--- @author DemiAutomatic
--- @method OpxAdmin.Server.Refuse
--- @description Answers a refusal by its code, with the host's reason when given.
--- @param source {integer}
--- @param raw {string}
--- @param code {string}
--- @param params {table|nil}
--- @returns {boolean}
function OpxAdmin.Server.Refuse(source, raw, code, params)
	params = params or {}
	params.code = code
	params.reason = params.reason and Text.Clean(params.reason, 64) or code
	Server.Answer(source, raw, false, ERRORS[code] or ERRORS.failed, params,
		TYPED[code] and 'warning' or 'error')
	return false
end

--- @author DemiAutomatic
--- @method OpxAdmin.Server.Tell
--- @description Raises a best-effort toast on the target player's screen.
--- @param playerId {integer}
--- @param key {string}
--- @param params {table|nil}
--- @param kind {string|nil} info, success, warning or error.
function OpxAdmin.Server.Tell(playerId, key, params, kind)
	local notifications = Open77.notifications
	if type(notifications) ~= 'table' or type(notifications.send) ~= 'function' then return end
	pcall(notifications.send, playerId, {
		type = kind or 'info',
		title = locale('admin.toast.title'),
		message = locale(key, params),
		durationMs = math.floor(Server.Setting(Config.TOAST_MS, 6000)),
	})
end

--- @author DemiAutomatic
--- @method OpxAdmin.Server.NameOf
--- @description The verified display name, cleaned for a log line or row.
--- @param playerId {integer}
--- @returns {string|nil}
function OpxAdmin.Server.NameOf(playerId)
	local read, name = pcall(Open77.players.name, playerId)
	if not read then return nil end
	return Text.Clean(name, 32)
end

--- @author DemiAutomatic
--- @method OpxAdmin.Server.UserOf
--- @description The durable account id of a connected player.
--- @param playerId {integer}
--- @returns {string|nil}
function OpxAdmin.Server.UserOf(playerId)
	if (tonumber(playerId) or 0) <= 0 then return nil end
	local read, identifier = pcall(Open77.players.identifier, playerId)
	if not read then return nil end
	return Text.Clean(identifier, 64)
end

--- @author DemiAutomatic
--- @method targetOf
--- @description Resolves a typed target to a connected player id, or me.
--- @param source {integer}
--- @param token {any}
--- @returns {integer|nil, string|nil}
local function targetOf(source, token)
	if token == nil then return nil, 'no_target' end
	local word = tostring(token):lower()
	if word == 'me' or word == 'self' then
		if source <= 0 then return nil, 'console_has_no_player' end
		return source, nil
	end
	local playerId = Text.Integer(token)
	if playerId == nil or playerId <= 0 then return nil, 'bad_target' end
	if Server.NameOf(playerId) == nil then return nil, 'not_connected' end
	return playerId, nil
end

--- @author DemiAutomatic
--- @method OpxAdmin.Server.Target
--- @description Resolves a typed target to a connected player, or answers why not.
--- @param source {integer}
--- @param raw {string}
--- @param token {any}
--- @returns {integer|nil}
function OpxAdmin.Server.Target(source, raw, token)
	local playerId, code = targetOf(source, token)
	if playerId == nil then Server.Refuse(source, raw, code) end
	return playerId
end

--- @author DemiAutomatic
--- @method OpxAdmin.Server.PositionOf
--- @description The replicated position and bucket, or nil before the world.
--- @param playerId {integer}
--- @returns {table|nil}
function OpxAdmin.Server.PositionOf(playerId)
	local read, position = pcall(Open77.players.position, playerId)
	if not read or type(position) ~= 'table' then return nil end
	local x, y, z = Text.Finite(position.x), Text.Finite(position.y), Text.Finite(position.z)
	if x == nil or y == nil or z == nil then return nil end
	return { x = x, y = y, z = z, bucket = Text.Integer(position.bucket) or 0 }
end

--- @author DemiAutomatic
--- @method OpxAdmin.Server.LifeOf
--- @description The host's life state for a player, or nil without one.
--- @param playerId {integer}
--- @returns {table|nil}
function OpxAdmin.Server.LifeOf(playerId)
	local read, life = pcall(Open77.players.getLifeState, playerId)
	if not read or type(life) ~= 'table' then return nil end
	return life
end

--- @author DemiAutomatic
--- @method OpxAdmin.Server.Admit
--- @description Whether a player's body may be acted on, failing closed.
--- @param playerId {integer}
--- @returns {boolean, table|string}
function OpxAdmin.Server.Admit(playerId)
	local life = Server.LifeOf(playerId)
	if life == nil then return false, 'not_incarnated' end
	local ready = Open77.ready
	if type(ready) ~= 'table' or type(ready.isReady) ~= 'function' then
		return false, 'gate_unreadable'
	end
	local read, open = pcall(ready.isReady, playerId)
	if not read then return false, 'gate_unreadable' end
	if open ~= true then return false, 'gate_closed' end
	return true, life
end

--- @author DemiAutomatic
--- @method OpxAdmin.Server.Admitted
--- @description Checks the readiness gate, answering and auditing a closed one.
--- @param source {integer}
--- @param raw {string}
--- @param playerId {integer}
--- @param event {string}
--- @returns {boolean}
function OpxAdmin.Server.Admitted(source, raw, playerId, event)
	local admitted, code = Server.Admit(playerId)
	if admitted then return true end
	Server.Refuse(source, raw, code, { id = playerId })
	Server.Audit(source, event, false, playerId, code)
	return false
end

--- @author DemiAutomatic
--- @method OpxAdmin.Server.Place
--- @description Moves a player through kill then respawn, reviving on refusal.
--- @param playerId {integer}
--- @param point {table}
--- @param heading {number|nil}
--- @param bucket {integer|nil} Nil keeps the bucket they are in.
--- @param why {string} What the kill is attributed to.
--- @returns {boolean, string|nil, string|nil}
function OpxAdmin.Server.Place(playerId, point, heading, bucket, why)
	local admitted, code = Server.Admit(playerId)
	if not admitted then return false, code end

	local placement = Config.PLACEMENT or {}
	local health = math.min(1.0, math.max(0.01, Server.Setting(placement.HEALTH, 1.0)))
	local graceMs = math.max(0, math.floor(Server.Setting(placement.GRACE_MS, 5000)))
	if bucket == nil then
		local position = Server.PositionOf(playerId)
		bucket = position and position.bucket or 0
	end

	local killed = false
	local deadRead, dead = pcall(Open77.players.isDead, playerId)
	if not (deadRead and dead == true) then
		local ok, reason = Open77.players.kill(playerId, {
			cause = 'script',
			weapon = RESOURCE .. ':' .. why,
		})
		if not ok then return false, 'kill_refused', tostring(reason) end
		killed = true
	end

	local respawned, reason = Open77.players.respawn(playerId, {
		position = { x = point.x, y = point.y, z = point.z },
		heading = heading or 0.0,
		bucket = bucket,
		health = health,
		graceMs = graceMs,
	})
	if not respawned then
		if killed then
			pcall(Open77.players.revive, playerId, { health = health, graceMs = graceMs })
		end
		return false, 'respawn_refused', tostring(reason)
	end
	return true
end

--- @author DemiAutomatic
--- @type {AuditEntry[]}
--- @description The in-memory audit ring, oldest entry first.
local ledger = {}

--- @author DemiAutomatic
--- @type {integer}
--- @description Sequence number of the last recorded audit entry.
local sequence = 0

--- @author DemiAutomatic
--- @type {integer}
--- @description How many audit entries the ring keeps, at least ten.
local AUDIT_ENTRIES = math.max(10, math.floor(Server.Setting(Config.AUDIT_ENTRIES, 200)))

--- @author DemiAutomatic
--- @method OpxAdmin.Server.Audit
--- @description Records one staff action in the platform log and the ring.
--- @param source {integer}
--- @param event {string} Stable and greppable, like admin.player.kill.
--- @param ok {boolean}
--- @param target {integer|nil}
--- @param detail {string|nil} English, for the log.
function OpxAdmin.Server.Audit(source, event, ok, target, detail)
	local actor = tonumber(source) or 0
	sequence = sequence + 1
	local entry = {
		seq = sequence,
		atMs = nowMs(),
		event = event,
		ok = ok == true,
		actor = actor,
		actorName = actor > 0 and (Server.NameOf(actor) or '?') or 'console',
		target = target,
		targetName = target and Server.NameOf(target) or nil,
		detail = Text.Clean(detail, 120) or '',
	}
	ledger[#ledger + 1] = entry
	if #ledger > AUDIT_ENTRIES then table.remove(ledger, 1) end

	local data = {
		actorName = entry.actorName,
		target = target,
		targetUser = target and Server.UserOf(target) or nil,
		targetName = entry.targetName,
	}
	local encoded, dataText = pcall(json.encode, data)
	local severity = entry.ok and 'info' or 'warn'
	Open77.log[severity](('[audit] event=%s severity=%s player=%d user=%s message=%q data=%s')
		:format(event, severity, actor, Server.UserOf(actor) or '-', entry.detail,
			encoded and dataText or '{}'))
end

--- @author DemiAutomatic
--- @method OpxAdmin.Server.Recent
--- @description The most recent audit entries, newest last.
--- @param count {integer}
--- @returns {AuditEntry[]}
function OpxAdmin.Server.Recent(count)
	local out = {}
	for index = math.max(1, #ledger - count + 1), #ledger do out[#out + 1] = ledger[index] end
	return out
end

--- @author DemiAutomatic
--- @type {AdminCommand[]}
--- @description Registered commands, in registration order.
local commands = {}

--- @author DemiAutomatic
--- @type {table<string, AdminCommand>}
--- @description Registered commands by name, to drop a duplicate.
local byName = {}

--- @author DemiAutomatic
--- @type {table<string, integer>}
--- @description Last run per operator and command or refresh topic, in milliseconds.
local lastRun = {}

--- @author DemiAutomatic
--- @method OpxAdmin.Server.Cooled
--- @description Whether a run falls inside the operator's floor, recording it otherwise.
--- @param player {integer}
--- @param name {string}
--- @param intervalMs {number}
--- @returns {boolean}
function OpxAdmin.Server.Cooled(player, name, intervalMs)
	if player <= 0 then return false end
	local slot = player .. ':' .. name
	local atMs = nowMs()
	local previous = lastRun[slot]
	if previous ~= nil and atMs - previous < intervalMs then return true end
	lastRun[slot] = atMs
	return false
end

--- @author DemiAutomatic
--- @method OpxAdmin.Server.Command
--- @description Registers one restricted staff command with its floor and guard.
--- @param name {string}
--- @param spec {AdminCommandSpec}
function OpxAdmin.Server.Command(name, spec)
	if byName[name] ~= nil then
		Open77.log.error(('command %s is registered twice; the second is dropped'):format(name))
		return
	end
	local rate = Config.RATE or {}
	local interval = spec.read and Server.Setting(rate.READ_MS, 1000)
		or Server.Setting(rate.ACTION_MS, 400)

	RegisterCommand(name, function(source, args, raw)
		local player = tonumber(source) or 0
		raw = type(raw) == 'string' and raw or name
		args = type(args) == 'table' and args or { n = 0 }
		if spec.inGame and player <= 0 then return Server.Refuse(player, raw, 'in_game_only') end
		if Server.Cooled(player, name, interval) then return Server.Refuse(player, raw, 'too_fast') end
		local ran, failure = pcall(spec.handler, player, args, raw)
		if not ran then
			Open77.log.error(('%s raised: %s'):format(name, tostring(failure)))
			Server.Refuse(player, raw, 'failed')
		end
	end, true)

	local entry = { name = name, help = spec.help, params = spec.params or {} }
	commands[#commands + 1] = entry
	byName[name] = entry
end

--- @author DemiAutomatic
--- @method OpxAdmin.Server.Commands
--- @description Every registered command, in registration order.
--- @returns {AdminCommand[]}
function OpxAdmin.Server.Commands()
	return commands
end

--- @author DemiAutomatic
--- @method OpxAdmin.Server.Permitted
--- @description Whether the host ACL grants a command, nil when it cannot say.
--- @param playerId {integer}
--- @param name {string}
--- @returns {boolean|nil}
function OpxAdmin.Server.Permitted(playerId, name)
	if playerId <= 0 then return true end
	local acl = Open77.acl
	if type(acl) ~= 'table' or type(acl.isAllowed) ~= 'function' then return nil end
	local read, allowed = pcall(acl.isAllowed, playerId, 'command.' .. name)
	if not read then return nil end
	return allowed == true
end

--- @author DemiAutomatic
--- @event chat:ready
--- @description Sends chat suggestions for the commands the ACL grants.
RegisterNetEvent('chat:ready', function()
	local player = tonumber(source) or 0
	if player <= 0 or Server.Cooled(player, 'chat:ready', 2000) then return end
	local suggestions = {}
	for _, command in ipairs(commands) do
		if Server.Permitted(player, command.name) == true then
			local parameters = {}
			for index, parameter in ipairs(command.params) do
				parameters[index] = {
					name = parameter.name,
					help = parameter.help and locale(parameter.help) or nil,
					optional = parameter.optional == true or nil,
				}
			end
			suggestions[#suggestions + 1] = {
				command = '/' .. command.name,
				help = locale(command.help),
				parameters = parameters,
			}
		end
	end
	if #suggestions > 0 then TriggerClientEvent('chat:addSuggestions', player, suggestions) end
end)

--- @author DemiAutomatic
--- @event onPlayerDisconnected
--- @description Forgets a departing player's command and refresh floors.
--- @param playerId {integer|string}
AddEventHandler('onPlayerDisconnected', function(playerId)
	local prefix = tostring(tonumber(playerId) or 0) .. ':'
	for slot in pairs(lastRun) do
		if slot:sub(1, #prefix) == prefix then lastRun[slot] = nil end
	end
end)

for _, line in ipairs(OpxAdmin.Catalog.problems) do Open77.log.warn(line) end

do
	local english, french = OpxAdmin.Locale.Keys('en'), OpxAdmin.Locale.Keys('fr')
	for key in pairs(english) do
		if not french[key] then Open77.log.warn('locales/fr.lua is missing ' .. key) end
	end
	for key in pairs(french) do
		if not english[key] then Open77.log.warn('locales/en.lua is missing ' .. key) end
	end
end

if type(Open77.acl) ~= 'table' or type(Open77.acl.isAllowed) ~= 'function' then
	Open77.log.warn('Open77.acl is unavailable: the menu cannot grey out what the ACL refuses, and the travel modes are not revoked with a grant. Every command is still gated by the host.')
end
