--- @author DemiAutomatic
--- @file server/doors.lua
--- @description Staff door states: the door command, and each bucket's states sent to the players in it.

local Server = OpxAdmin.Server

local answer, refuse, audit = Server.Answer, Server.Refuse, Server.Audit
local count = Server.Count

--- @author DemiAutomatic
--- @type {string}
--- @description The official door service; while it runs it owns every door and this file stands down.
local NETWORKED = 'open77_doors'

--- @author DemiAutomatic
--- @type {integer}
--- @description Doors one bucket may hold a staff state for.
local MAX_DOORS = 256

--- @author DemiAutomatic
--- @type {integer}
--- @description Rows per full state list event.
local CHUNK = 40

--- @author DemiAutomatic
--- @type {integer}
--- @description Milliseconds between two looks at which bucket each player is in.
local SWEEP_MS = 2000

--- @author DemiAutomatic
--- @type {table<string, table>}
--- @description The fields each action writes over a door's state.
local ACTIONS = {
	open = { open = true },
	close = { open = false },
	lock = { locked = true, open = false },
	unlock = { locked = false },
	seal = { sealed = true, open = false },
	unseal = { sealed = false },
}

--- @author DemiAutomatic
--- @type {table<integer, table<string, table>>}
--- @description Bucket to door id to the state staff set.
local states = {}

--- @author DemiAutomatic
--- @type {table<integer, integer>}
--- @description The bucket whose full list each player was last sent.
local sentBucket = {}

--- @author DemiAutomatic
--- @method doorId
--- @description A typed door id in its canonical 0x spelling, or nil.
--- @param token {any}
--- @returns {string|nil}
local function doorId(token)
	if type(token) ~= 'string' then return nil end
	local digits = token:match('^0[xX](%x+)$')
	if digits == nil or #digits > 16 or digits:match('^0+$') then return nil end
	return '0x' .. digits:upper()
end

--- @author DemiAutomatic
--- @method rowsOf
--- @description Every staff door state of one bucket, as rows.
--- @param bucket {integer}
--- @returns {table[]}
local function rowsOf(bucket)
	local rows = {}
	for id, state in pairs(states[bucket] or {}) do
		rows[#rows + 1] = { id = id, open = state.open, locked = state.locked, sealed = state.sealed }
	end
	return rows
end

--- @author DemiAutomatic
--- @method pushAll
--- @description Sends one player every door state of their bucket, in chunks.
--- @param playerId {integer}
--- @param bucket {integer}
local function pushAll(playerId, bucket)
	local rows = rowsOf(bucket)
	local offset = 0
	repeat
		local chunk = {}
		for index = offset + 1, math.min(offset + CHUNK, #rows) do chunk[#chunk + 1] = rows[index] end
		TriggerClientEvent('opx77_admin:doors', playerId, { rows = chunk, offset = offset,
			done = offset + #chunk >= #rows })
		offset = offset + #chunk
	until offset >= #rows
	sentBucket[playerId] = bucket
end

--- @author DemiAutomatic
--- @method pushOne
--- @description Sends one door's state, or its reset, to every player in the bucket.
--- @param bucket {integer}
--- @param id {string}
--- @param state {table|nil}
local function pushOne(bucket, id, state)
	for _, playerId in ipairs(Server.PlayerIds()) do
		local position = Server.PositionOf(playerId)
		if position and position.bucket == bucket then
			TriggerClientEvent('opx77_admin:door', playerId, id, state or false)
		end
	end
end

--- @author DemiAutomatic
--- @command /opx77.admin.world.door
--- @description Opens, closes, locks, seals or resets a door for every player in the operator's bucket.
Server.Command('opx77.admin.world.door', {
	help = 'admin.help.door',
	params = { { name = 'doorId', help = 'admin.help.doorId' },
		{ name = 'open|close|lock|unlock|seal|unseal|reset', help = 'admin.help.doorAction' } },
	inGame = true,
	handler = function(source, args, raw)
		local action = type(args[2]) == 'string' and args[2]:lower() or nil
		if count(args) ~= 2 or (action ~= 'reset' and ACTIONS[action] == nil) then
			return answer(source, raw, false, 'admin.usage.door')
		end
		local id = doorId(args[1])
		if id == nil then return refuse(source, raw, 'bad_door') end
		local read, networked = pcall(GetResourceState, NETWORKED)
		if read and networked == 'running' then return refuse(source, raw, 'doors_networked') end
		local position = Server.PositionOf(source)
		if position == nil then return refuse(source, raw, 'no_position') end

		local bucket = states[position.bucket] or {}
		local door = bucket[id]
		if action == 'reset' then
			door = nil
		else
			if door == nil then
				local held = 0
				for _ in pairs(bucket) do held = held + 1 end
				if held >= MAX_DOORS then return refuse(source, raw, 'door_limit', { max = MAX_DOORS }) end
				door = {}
			end
			for field, value in pairs(ACTIONS[action]) do door[field] = value end
		end
		bucket[id] = door
		states[position.bucket] = next(bucket) ~= nil and bucket or nil
		pushOne(position.bucket, id, door)
		audit(source, 'admin.world.door', true, nil, ('%s %s bucket %d'):format(id, action, position.bucket))
		answer(source, raw, true, 'admin.done.door',
			{ door = id, action = locale('admin.door.' .. action) })
	end,
})

--- @author DemiAutomatic
--- @event opx77_admin:doorsHello
--- @description A client half started: its full list goes out on the next sweep.
RegisterNetEvent('opx77_admin:doorsHello', function()
	local player = tonumber(source) or 0
	if player <= 0 or Server.Cooled(player, 'doors:hello', 2000) then return end
	sentBucket[player] = nil
end)

CreateThread(function()
	while true do
		Wait(SWEEP_MS)
		local swept, failure = pcall(function()
			for _, playerId in ipairs(Server.PlayerIds()) do
				local position = Server.PositionOf(playerId)
				if position and sentBucket[playerId] ~= position.bucket then pushAll(playerId, position.bucket) end
			end
		end)
		if not swept then Open77.log.warn('door sweep failed: ' .. tostring(failure)) end
	end
end)

--- @author DemiAutomatic
--- @event onPlayerDisconnected
--- @description Forgets which list a departing player was sent.
--- @param playerId {integer|string}
AddEventHandler('onPlayerDisconnected', function(playerId)
	sentBucket[tonumber(playerId) or 0] = nil
end)
