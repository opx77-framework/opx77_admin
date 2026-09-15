--- @author DemiAutomatic
--- @file server/players.lua
--- @description Commands acting on a body or a session: self, players, moderation.

local Config = OPX_ADMIN_CONFIG
local Server = OpxAdmin.Server
local Text = OpxAdmin.Text

local answer, refuse, audit, tell = Server.Answer, Server.Refuse, Server.Audit, Server.Tell
local count = Server.Count

--- @author DemiAutomatic
--- @type {string}
--- @description This resource's name, which staff kills are attributed to.
local RESOURCE = GetCurrentResourceName()

--- @author DemiAutomatic
--- @method nativeRefused
--- @description Answers a refused native mutator and keeps its reason in the audit.
--- @param source {integer}
--- @param raw {string}
--- @param event {string}
--- @param playerId {integer}
--- @param reason {any}
--- @returns {boolean}
local function nativeRefused(source, raw, event, playerId, reason)
	refuse(source, raw, 'refused', { reason = tostring(reason) })
	audit(source, event, false, playerId, 'refused: ' .. tostring(reason))
	return false
end

--- @author DemiAutomatic
--- @method pointOf
--- @description The three typed words as a point within a million, or nil.
--- @param x {any}
--- @param y {any}
--- @param z {any}
--- @returns {table|nil}
local function pointOf(x, y, z)
	x, y, z = Text.Finite(x), Text.Finite(y), Text.Finite(z)
	if x == nil or y == nil or z == nil then return nil end
	if math.abs(x) > 1e6 or math.abs(y) > 1e6 or math.abs(z) > 1e6 then return nil end
	return { x = x, y = y, z = z }
end

--- @author DemiAutomatic
--- @method healthOf
--- @description A player's maximum health in absolute points, and the raw reading.
--- @param playerId {integer}
--- @returns {number, table|nil}
local function healthOf(playerId)
	local read, health = pcall(Open77.players.getHealth, playerId)
	if not read or type(health) ~= 'table' then return 100.0, nil end
	local maximum = Text.Finite(health.maxHealth)
	if maximum == nil or maximum <= 0 then maximum = 100.0 end
	return maximum, health
end

--- @author DemiAutomatic
--- @type {table<integer, string>, table<integer, string>}
--- @description Command name that switched noclip and map travel on, per player.
local noclip, mapPick = {}, {}

--- @author DemiAutomatic
--- @type {table<integer, number>}
--- @description Noclip speed a player chose, so switching on keeps it.
local speedChosen = {}

--- @author DemiAutomatic
--- @method travel
--- @description Sends one travel instruction to a player's client half.
--- @param playerId {integer}
--- @param action {string} noclip, speed, mapPick or copy.
--- @param value {any}
--- @param detail {any}
local function travel(playerId, action, value, detail)
	TriggerClientEvent('opx77_admin:travel', playerId, action, value, detail)
end

--- @author DemiAutomatic
--- @method setNoclip
--- @description Switches a player's noclip, sending the default speed the first time.
--- @param playerId {integer}
--- @param on {boolean}
--- @param grant {string|nil} The command whose grant keeps it on.
local function setNoclip(playerId, on, grant)
	noclip[playerId] = on and grant or nil
	travel(playerId, 'noclip', on == true)
	if on and speedChosen[playerId] == nil then
		travel(playerId, 'speed', Server.Setting((Config.NOCLIP or {}).SPEED, 40.0))
	end
end

--- @author DemiAutomatic
--- @command /opx77.admin.self.noclip
--- @description Switches noclip for the operator, toggling when no word is typed.
Server.Command('opx77.admin.self.noclip', {
	help = 'admin.help.noclip',
	params = { { name = 'on|off', help = 'admin.help.toggle', optional = true } },
	inGame = true,
	handler = function(source, args, raw)
		local wanted, invalid = Text.Switch(args[1])
		if invalid then return refuse(source, raw, 'bad_switch') end
		if wanted == nil then wanted = noclip[source] == nil end
		setNoclip(source, wanted, 'opx77.admin.self.noclip')
		audit(source, 'admin.self.noclip', true, nil, wanted and 'on' or 'off')
		answer(source, raw, true, wanted and 'admin.done.noclipOn' or 'admin.done.noclipOff')
	end,
})

--- @author DemiAutomatic
--- @command /opx77.admin.self.speed
--- @description Sets the operator's noclip speed, 0.1 to 500 metres a second.
Server.Command('opx77.admin.self.speed', {
	help = 'admin.help.speed', params = { { name = 'm/s', help = 'admin.help.speedValue' } },
	inGame = true,
	handler = function(source, args, raw)
		local speed = Text.Finite(args[1])
		if count(args) ~= 1 or speed == nil or speed < 0.1 or speed > 500 then
			return answer(source, raw, false, 'admin.usage.speed')
		end
		speedChosen[source] = speed
		travel(source, 'speed', speed)
		audit(source, 'admin.self.speed', true, nil, ('%.1f'):format(speed))
		answer(source, raw, true, 'admin.done.speed', { speed = ('%.1f'):format(speed) })
	end,
})

--- @author DemiAutomatic
--- @command /opx77.admin.self.maptravel
--- @description Arms map travel, or jumps to the point a double-click sends.
Server.Command('opx77.admin.self.maptravel', {
	help = 'admin.help.maptravel',
	params = { { name = 'on|off|x', help = 'admin.help.maptravelValue', optional = true },
		{ name = 'y', help = 'admin.help.maptravelPoint', optional = true },
		{ name = 'z', help = 'admin.help.maptravelPoint', optional = true } },
	inGame = true,
	handler = function(source, args, raw)
		if count(args) == 3 then
			local point = pointOf(args[1], args[2], args[3])
			if point == nil then return refuse(source, raw, 'bad_coordinates') end
			local placed, code, reason = Server.Place(source, point, 0.0, nil, 'maptravel')
			audit(source, 'admin.self.maptravel', placed, source,
				('%.0f %.0f %.0f %s'):format(point.x, point.y, point.z, code or ''))
			if not placed then return refuse(source, raw, code, { reason = reason }) end
			return answer(source, raw, true, 'admin.done.moved',
				{ x = ('%.1f'):format(point.x), y = ('%.1f'):format(point.y),
					z = ('%.1f'):format(point.z) })
		end
		local wanted, invalid = Text.Switch(args[1])
		if invalid or count(args) > 1 then
			return answer(source, raw, false, 'admin.usage.maptravel')
		end
		if wanted == nil then wanted = mapPick[source] == nil end
		mapPick[source] = wanted and 'opx77.admin.self.maptravel' or nil
		travel(source, 'mapPick', wanted)
		audit(source, 'admin.self.maptravel', true, nil, wanted and 'on' or 'off')
		answer(source, raw, true, wanted and 'admin.done.mapOn' or 'admin.done.mapOff')
	end,
})

CreateThread(function()
	while true do
		Wait(2000)
		local swept, failure = pcall(function()
			for playerId, grant in pairs(noclip) do
				if Server.Permitted(playerId, grant) == false then
					setNoclip(playerId, false)
					Open77.log.info(('noclip off for player %d: %s is no longer granted')
						:format(playerId, grant))
				end
			end
			for playerId, grant in pairs(mapPick) do
				if Server.Permitted(playerId, grant) == false then
					mapPick[playerId] = nil
					travel(playerId, 'mapPick', false)
				end
			end
		end)
		if not swept then Open77.log.warn('travel sweep failed: ' .. tostring(failure)) end
	end
end)

--- @author DemiAutomatic
--- @event onPlayerDisconnected
--- @description Forgets a departing player's travel switches and chosen speed.
--- @param playerId {integer|string}
AddEventHandler('onPlayerDisconnected', function(playerId)
	local player = tonumber(playerId) or 0
	noclip[player], mapPick[player], speedChosen[player] = nil, nil, nil
end)

--- @author DemiAutomatic
--- @event onResourceStop
--- @description Switches every travel mode this resource turned on back off.
--- @param name {string}
AddEventHandler('onResourceStop', function(name)
	if name ~= RESOURCE then return end
	for playerId in pairs(noclip) do travel(playerId, 'noclip', false) end
	for playerId in pairs(mapPick) do travel(playerId, 'mapPick', false) end
end)

--- @author DemiAutomatic
--- @method heal
--- @description Heals a player to their maximum health, audited and answered.
--- @param source {integer}
--- @param raw {string}
--- @param playerId {integer}
--- @param event {string}
local function heal(source, raw, playerId, event)
	if not Server.Admitted(source, raw, playerId, event) then return end
	local maximum = healthOf(playerId)
	local ok, reason = Open77.players.setHealth(playerId, maximum)
	if not ok then return nativeRefused(source, raw, event, playerId, reason) end
	audit(source, event, true, playerId, ('%.0f'):format(maximum))
	if playerId ~= source then tell(playerId, 'admin.toast.healed', nil, 'success') end
	answer(source, raw, true, 'admin.done.healed',
		{ id = playerId, name = Server.NameOf(playerId) or '?' })
end

--- @author DemiAutomatic
--- @method revive
--- @description Revives a player where they lie, audited and answered.
--- @param source {integer}
--- @param raw {string}
--- @param playerId {integer}
--- @param event {string}
local function revive(source, raw, playerId, event)
	if not Server.Admitted(source, raw, playerId, event) then return end
	local ok, reason = Open77.players.revive(playerId, Server.Recovery())
	if not ok then return nativeRefused(source, raw, event, playerId, reason) end
	audit(source, event, true, playerId)
	if playerId ~= source then tell(playerId, 'admin.toast.revived', nil, 'success') end
	answer(source, raw, true, 'admin.done.revived',
		{ id = playerId, name = Server.NameOf(playerId) or '?' })
end

--- @author DemiAutomatic
--- @method god
--- @description Switches a player's god mode, toggling when no word is typed.
--- @param source {integer}
--- @param raw {string}
--- @param playerId {integer}
--- @param word {any}
--- @param event {string}
local function god(source, raw, playerId, word, event)
	local wanted, invalid = Text.Switch(word)
	if invalid then return refuse(source, raw, 'bad_switch') end
	if not Server.Admitted(source, raw, playerId, event) then return end
	if wanted == nil then
		local _, health = healthOf(playerId)
		wanted = not (health ~= nil and health.godMode == true)
	end
	local ok, reason = Open77.players.setGodMode(playerId, wanted)
	if not ok then return nativeRefused(source, raw, event, playerId, reason) end
	audit(source, event, true, playerId, wanted and 'on' or 'off')
	if playerId ~= source then
		tell(playerId, wanted and 'admin.toast.godOn' or 'admin.toast.godOff')
	end
	answer(source, raw, true, wanted and 'admin.done.godOn' or 'admin.done.godOff',
		{ id = playerId, name = Server.NameOf(playerId) or '?' })
end

--- @author DemiAutomatic
--- @command /opx77.admin.self.heal
--- @description Heals the operator to their maximum health.
Server.Command('opx77.admin.self.heal', {
	help = 'admin.help.selfHeal', inGame = true,
	handler = function(source, _, raw) heal(source, raw, source, 'admin.self.heal') end,
})

--- @author DemiAutomatic
--- @command /opx77.admin.self.revive
--- @description Revives the operator where they lie.
Server.Command('opx77.admin.self.revive', {
	help = 'admin.help.selfRevive', inGame = true,
	handler = function(source, _, raw) revive(source, raw, source, 'admin.self.revive') end,
})

--- @author DemiAutomatic
--- @command /opx77.admin.self.god
--- @description Switches the operator's own god mode.
Server.Command('opx77.admin.self.god', {
	help = 'admin.help.selfGod',
	params = { { name = 'on|off', help = 'admin.help.toggle', optional = true } },
	inGame = true,
	handler = function(source, args, raw) god(source, raw, source, args[1], 'admin.self.god') end,
})

--- @author DemiAutomatic
--- @command /opx77.admin.self.pos
--- @description Copies where the operator stands as a LOCATIONS config row.
Server.Command('opx77.admin.self.pos', {
	help = 'admin.help.pos', inGame = true, read = true,
	handler = function(source, _, raw)
		local position = Server.PositionOf(source)
		if position == nil then return refuse(source, raw, 'no_position') end
		local row = ('{ NAME = "here", LABEL = "Here", X = %.2f, Y = %.2f, Z = %.2f, HEADING = 0.0 },')
			:format(position.x, position.y, position.z)
		travel(source, 'copy', row)
		answer(source, raw, true, 'admin.done.pos', { row = row, bucket = position.bucket })
	end,
})

--- @author DemiAutomatic
--- @method beside
--- @description Where to land beside a player, and their bucket.
--- @param playerId {integer}
--- @returns {table|nil, integer|nil}
local function beside(playerId)
	local position = Server.PositionOf(playerId)
	if position == nil then return nil, nil end
	local offset = (Config.PLACEMENT or {}).BESIDE or {}
	return {
		x = position.x + Server.Setting(offset.X, 1.5),
		y = position.y + Server.Setting(offset.Y, 0.0),
		z = position.z + Server.Setting(offset.Z, 0.0),
	}, position.bucket
end

--- @author DemiAutomatic
--- @command /opx77.admin.player.goto
--- @description Teleports the operator beside a player, into their bucket.
Server.Command('opx77.admin.player.goto', {
	help = 'admin.help.goto', params = { { name = 'playerId', help = 'admin.help.playerId' } },
	inGame = true,
	handler = function(source, args, raw)
		local playerId = Server.Target(source, raw, args[1])
		if playerId == nil then return end
		if playerId == source then return refuse(source, raw, 'self_target') end
		if not Server.Admitted(source, raw, playerId, 'admin.player.goto') then return end
		local point, bucket = beside(playerId)
		if point == nil then return refuse(source, raw, 'no_position') end
		local placed, code, reason = Server.Place(source, point, 0.0, bucket, 'goto')
		audit(source, 'admin.player.goto', placed, playerId, code)
		if not placed then return refuse(source, raw, code, { reason = reason }) end
		answer(source, raw, true, 'admin.done.goto',
			{ id = playerId, name = Server.NameOf(playerId) or '?', bucket = bucket })
	end,
})

--- @author DemiAutomatic
--- @command /opx77.admin.player.bring
--- @description Teleports a player beside the operator.
Server.Command('opx77.admin.player.bring', {
	help = 'admin.help.bring', params = { { name = 'playerId', help = 'admin.help.playerId' } },
	inGame = true,
	handler = function(source, args, raw)
		local playerId = Server.Target(source, raw, args[1])
		if playerId == nil then return end
		if playerId == source then return refuse(source, raw, 'self_target') end
		local point, bucket = beside(source)
		if point == nil then return refuse(source, raw, 'no_position') end
		local placed, code, reason = Server.Place(playerId, point, 0.0, bucket, 'bring')
		audit(source, 'admin.player.bring', placed, playerId, code)
		if not placed then return refuse(source, raw, code, { reason = reason, id = playerId }) end
		tell(playerId, 'admin.toast.brought')
		answer(source, raw, true, 'admin.done.bring',
			{ id = playerId, name = Server.NameOf(playerId) or '?' })
	end,
})

--- @author DemiAutomatic
--- @command /opx77.admin.player.tp
--- @description Teleports a player to typed coordinates and an optional heading.
Server.Command('opx77.admin.player.tp', {
	help = 'admin.help.tp',
	params = { { name = 'playerId|me', help = 'admin.help.playerOrMe' },
		{ name = 'x', help = 'admin.help.coordinate' },
		{ name = 'y', help = 'admin.help.coordinate' },
		{ name = 'z', help = 'admin.help.coordinate' },
		{ name = 'heading', help = 'admin.help.heading', optional = true } },
	handler = function(source, args, raw)
		local given = count(args)
		if given < 4 or given > 5 then return answer(source, raw, false, 'admin.usage.tp') end
		local playerId = Server.Target(source, raw, args[1])
		if playerId == nil then return end
		local point = pointOf(args[2], args[3], args[4])
		local heading = given == 5 and Text.Finite(args[5]) or 0.0
		if point == nil or heading == nil then return refuse(source, raw, 'bad_coordinates') end
		local placed, code, reason = Server.Place(playerId, point, heading, nil, 'tp')
		audit(source, 'admin.player.tp', placed, playerId,
			('%.0f %.0f %.0f %s'):format(point.x, point.y, point.z, code or ''))
		if not placed then return refuse(source, raw, code, { reason = reason, id = playerId }) end
		if playerId ~= source then tell(playerId, 'admin.toast.moved') end
		answer(source, raw, true, 'admin.done.moved',
			{ x = ('%.1f'):format(point.x), y = ('%.1f'):format(point.y),
				z = ('%.1f'):format(point.z) })
	end,
})

--- @author DemiAutomatic
--- @command /opx77.admin.player.observe
--- @description Lands the operator above a player with noclip on.
Server.Command('opx77.admin.player.observe', {
	help = 'admin.help.observe', params = { { name = 'playerId', help = 'admin.help.playerId' } },
	inGame = true,
	handler = function(source, args, raw)
		local playerId = Server.Target(source, raw, args[1])
		if playerId == nil then return end
		if playerId == source then return refuse(source, raw, 'self_target') end
		if not Server.Admitted(source, raw, playerId, 'admin.player.observe') then return end
		local position = Server.PositionOf(playerId)
		if position == nil then return refuse(source, raw, 'no_position') end
		local height = Server.Setting((Config.PLACEMENT or {}).OBSERVE_HEIGHT, 2.0)
		local placed, code, reason = Server.Place(source,
			{ x = position.x, y = position.y, z = position.z + height }, 0.0, position.bucket,
			'observe')
		audit(source, 'admin.player.observe', placed, playerId, code)
		if not placed then return refuse(source, raw, code, { reason = reason }) end
		setNoclip(source, true, 'opx77.admin.player.observe')
		answer(source, raw, true, 'admin.done.observe',
			{ id = playerId, name = Server.NameOf(playerId) or '?' })
	end,
})

--- @author DemiAutomatic
--- @command /opx77.admin.player.heal
--- @description Heals a player to their maximum health.
Server.Command('opx77.admin.player.heal', {
	help = 'admin.help.heal', params = { { name = 'playerId|me', help = 'admin.help.playerOrMe' } },
	handler = function(source, args, raw)
		local playerId = Server.Target(source, raw, args[1])
		if playerId then heal(source, raw, playerId, 'admin.player.heal') end
	end,
})

--- @author DemiAutomatic
--- @command /opx77.admin.player.revive
--- @description Revives a player where they lie.
Server.Command('opx77.admin.player.revive', {
	help = 'admin.help.revive',
	params = { { name = 'playerId|me', help = 'admin.help.playerOrMe' } },
	handler = function(source, args, raw)
		local playerId = Server.Target(source, raw, args[1])
		if playerId then revive(source, raw, playerId, 'admin.player.revive') end
	end,
})

--- @author DemiAutomatic
--- @command /opx77.admin.player.god
--- @description Switches a player's god mode.
Server.Command('opx77.admin.player.god', {
	help = 'admin.help.god',
	params = { { name = 'playerId|me', help = 'admin.help.playerOrMe' },
		{ name = 'on|off', help = 'admin.help.toggle', optional = true } },
	handler = function(source, args, raw)
		local playerId = Server.Target(source, raw, args[1])
		if playerId then god(source, raw, playerId, args[2], 'admin.player.god') end
	end,
})

--- @author DemiAutomatic
--- @command /opx77.admin.player.kill
--- @description Kills a player, attributed to the operator.
Server.Command('opx77.admin.player.kill', {
	help = 'admin.help.kill', params = { { name = 'playerId', help = 'admin.help.playerId' } },
	handler = function(source, args, raw)
		local playerId = Server.Target(source, raw, args[1])
		if playerId == nil then return end
		if not Server.Admitted(source, raw, playerId, 'admin.player.kill') then return end
		local ok, reason = Open77.players.kill(playerId, {
			killer = source > 0 and source or nil,
			cause = 'script',
			weapon = RESOURCE .. ':kill',
		})
		if not ok then return nativeRefused(source, raw, 'admin.player.kill', playerId, reason) end
		audit(source, 'admin.player.kill', true, playerId)
		tell(playerId, 'admin.toast.killed', nil, 'warning')
		answer(source, raw, true, 'admin.done.killed',
			{ id = playerId, name = Server.NameOf(playerId) or '?' })
	end,
})

--- @author DemiAutomatic
--- @command /opx77.admin.player.health
--- @description Sets a player's health in points, capped at their maximum.
Server.Command('opx77.admin.player.health', {
	help = 'admin.help.health',
	params = { { name = 'playerId|me', help = 'admin.help.playerOrMe' },
		{ name = 'points', help = 'admin.help.healthPoints' } },
	handler = function(source, args, raw)
		local value = Text.Finite(args[2])
		if count(args) ~= 2 or value == nil or value < 0 then
			return answer(source, raw, false, 'admin.usage.health')
		end
		local playerId = Server.Target(source, raw, args[1])
		if playerId == nil then return end
		if not Server.Admitted(source, raw, playerId, 'admin.player.health') then return end
		local maximum = healthOf(playerId)
		value = math.min(value, maximum)
		local ok, reason = Open77.players.setHealth(playerId, value)
		if not ok then return nativeRefused(source, raw, 'admin.player.health', playerId, reason) end
		audit(source, 'admin.player.health', true, playerId, ('%.0f/%.0f'):format(value, maximum))
		answer(source, raw, true, 'admin.done.health',
			{ id = playerId, value = ('%.0f'):format(value), maximum = ('%.0f'):format(maximum) })
	end,
})

--- @author DemiAutomatic
--- @command /opx77.admin.player.armor
--- @description Sets a player's armour in points, 0 to 10000.
Server.Command('opx77.admin.player.armor', {
	help = 'admin.help.armor',
	params = { { name = 'playerId|me', help = 'admin.help.playerOrMe' },
		{ name = 'points', help = 'admin.help.armorPoints' } },
	handler = function(source, args, raw)
		local value = Text.Finite(args[2])
		if count(args) ~= 2 or value == nil or value < 0 or value > 10000 then
			return answer(source, raw, false, 'admin.usage.armor')
		end
		local playerId = Server.Target(source, raw, args[1])
		if playerId == nil then return end
		if not Server.Admitted(source, raw, playerId, 'admin.player.armor') then return end
		local ok, reason = Open77.players.setArmor(playerId, value)
		if not ok then return nativeRefused(source, raw, 'admin.player.armor', playerId, reason) end
		audit(source, 'admin.player.armor', true, playerId, ('%.0f'):format(value))
		answer(source, raw, true, 'admin.done.armor',
			{ id = playerId, value = ('%.0f'):format(value) })
	end,
})

--- @author DemiAutomatic
--- @type {integer}
--- @description Longest disconnect reason the platform accepts, in UTF-8 bytes.
local KICK_REASON_BYTES = 127

--- @author DemiAutomatic
--- @type {table<string, integer>}
--- @description Seconds per ban duration unit.
local UNITS = { s = 1, m = 60, h = 3600, d = 86400 }

--- @author DemiAutomatic
--- @type {integer}
--- @description Longest timed ban, ten years in seconds.
local MAX_BAN_SECONDS = 3650 * 86400

--- @author DemiAutomatic
--- @method duration
--- @description A typed ban duration in seconds, false for permanent, nil otherwise.
--- @param token {any}
--- @returns {integer|false|nil}
local function duration(token)
	if type(token) ~= 'string' then return nil end
	local word = token:lower()
	if word == 'perm' or word == 'permanent' then return false end
	local amount, unit = word:match('^(%d+)([smhd])$')
	if amount == nil then return nil end
	local seconds = tonumber(amount) * UNITS[unit]
	if seconds <= 0 or seconds > MAX_BAN_SECONDS then return nil end
	return seconds
end

--- @author DemiAutomatic
--- @command /opx77.admin.moderate.kick
--- @description Disconnects a player with a reason cut to the platform limit.
Server.Command('opx77.admin.moderate.kick', {
	help = 'admin.help.kick',
	params = { { name = 'playerId', help = 'admin.help.playerId' },
		{ name = 'reason', help = 'admin.help.reason', optional = true } },
	handler = function(source, args, raw)
		local playerId = Server.Target(source, raw, args[1])
		if playerId == nil then return end
		local reason = Text.Clean(Text.Rest(args, 2), 200) or locale('admin.kick.defaultReason')
		reason = Text.Bytes(reason, KICK_REASON_BYTES)
		local name = Server.NameOf(playerId) or '?'
		local ok, failure = Open77.players.kick(playerId, reason)
		if not ok then return nativeRefused(source, raw, 'admin.moderate.kick', playerId, failure) end
		audit(source, 'admin.moderate.kick', true, playerId, ('%s: %s'):format(name, reason))
		answer(source, raw, true, 'admin.done.kicked', { id = playerId, name = name, reason = reason })
	end,
})

--- @author DemiAutomatic
--- @command /opx77.admin.moderate.ban
--- @description Bans a player's account on this server, timed or permanent.
Server.Command('opx77.admin.moderate.ban', {
	help = 'admin.help.ban',
	params = { { name = 'playerId', help = 'admin.help.playerId' },
		{ name = 'duration', help = 'admin.help.banDuration', optional = true },
		{ name = 'reason', help = 'admin.help.reason', optional = true } },
	handler = function(source, args, raw)
		local playerId = Server.Target(source, raw, args[1])
		if playerId == nil then return end

		local seconds, reasonFrom = nil, 2
		local parsed = duration(args[2])
		if parsed == false then
			reasonFrom = 3
		elseif parsed ~= nil then
			seconds, reasonFrom = parsed, 3
		elseif type(args[2]) == 'string' and args[2]:lower():match('^%-?%d+[smhd]$') then
			return refuse(source, raw, 'bad_duration')
		end

		local access = Open77.access
		if type(access) ~= 'table' or type(access.ban) ~= 'function' then
			return refuse(source, raw, 'refused', { reason = 'access_unavailable' })
		end
		local identifier = Server.UserOf(playerId)
		if identifier == nil then return refuse(source, raw, 'refused', { reason = 'no_identity' }) end

		local reason = Text.Clean(Text.Rest(args, reasonFrom), 200) or locale('admin.ban.defaultReason')
		local name = Server.NameOf(playerId) or '?'
		local ok, failure = access.ban(identifier, reason, seconds, name)
		if not ok then return nativeRefused(source, raw, 'admin.moderate.ban', playerId, failure) end
		audit(source, 'admin.moderate.ban', true, playerId,
			('%s %s: %s'):format(name, seconds and (seconds .. 's') or 'permanent', reason))
		answer(source, raw, true, seconds and 'admin.done.banned' or 'admin.done.bannedForever',
			{ id = playerId, name = name, reason = reason,
				hours = seconds and ('%.1f'):format(seconds / 3600) or '' })
	end,
})
