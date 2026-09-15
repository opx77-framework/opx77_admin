--- @author DemiAutomatic
--- @file client/doors.lua
--- @description Applies the door states staff set to the doors streamed around this player.

local Client = OpxAdmin.Client

--- @author DemiAutomatic
--- @type {string}
--- @description The official door service; while it runs it projects every door and this file stands down.
local NETWORKED = 'open77_doors'

--- @author DemiAutomatic
--- @type {number}
--- @description Metres around the player doors are looked for, within the native's 100.
local RADIUS = 80

--- @author DemiAutomatic
--- @type {integer}
--- @description Milliseconds between two looks at the streamed doors.
local SCAN_MS = 1000

--- @author DemiAutomatic
--- @type {table<string, table>}
--- @description Door id to the state staff set, for this player's bucket.
local known = {}

--- @author DemiAutomatic
--- @type {table<string, table>}
--- @description The full list still arriving.
local incoming = {}

--- @author DemiAutomatic
--- @type {table<string, boolean>}
--- @description Doors the last look found streamed, so a door streaming in gets its state once.
local streamed = {}

--- @author DemiAutomatic
--- @method doors
--- @description Open77.doors, or nil on a client without the door natives or while open77_doors runs.
--- @returns {table|nil}
local function doors()
	local native = Open77.doors
	if type(native) ~= 'table' or type(native.near) ~= 'function' or type(native.setOpen) ~= 'function' then
		return nil
	end
	if Client.Running(NETWORKED) then return nil end
	return native
end

--- @author DemiAutomatic
--- @method stateOf
--- @description A state from the server, kept to its three booleans, or nil.
--- @param value {any}
--- @returns {table|nil}
local function stateOf(value)
	if type(value) ~= 'table' then return nil end
	local state = {}
	for _, field in ipairs({ 'open', 'locked', 'sealed' }) do
		if type(value[field]) == 'boolean' then state[field] = value[field] end
	end
	return state
end

--- @author DemiAutomatic
--- @method apply
--- @description Puts one streamed door in a state: releases first, then the opening, then the holds.
--- @param native {table}
--- @param door {table} The live snapshot.
--- @param state {table}
local function apply(native, door, state)
	local id = door.id
	if state.locked == false then pcall(native.setLocked, id, false, true) end
	if state.sealed == false then pcall(native.setSealed, id, false, true) end
	-- A lift door follows its cabin.
	if state.open ~= nil and not door.lift then pcall(native.setOpen, id, state.open, true) end
	if state.locked == true then pcall(native.setLocked, id, true, true) end
	if state.sealed == true then pcall(native.setSealed, id, true, true) end
end

--- @author DemiAutomatic
--- @method live
--- @description The live snapshot of a streamed door, or nil.
--- @param native {table}
--- @param id {string}
--- @returns {table|nil}
local function live(native, id)
	local read, door = pcall(native.state, id)
	if not read or type(door) ~= 'table' or type(door.id) ~= 'string' then return nil end
	return door
end

--- @author DemiAutomatic
--- @method release
--- @description Gives a streamed door back to its authored default.
--- @param native {table}
--- @param id {string}
local function release(native, id)
	if live(native, id) then pcall(native.reset, id) end
end

--- @author DemiAutomatic
--- @event opx77_admin:door
--- @description One door's new state, or false for its reset.
--- @param id {string}
--- @param value {table|false}
RegisterNetEvent('opx77_admin:door', function(id, value)
	if type(id) ~= 'string' or #id > 18 then return end
	local native = doors()
	if value == false then
		known[id] = nil
		if native then release(native, id) end
		return
	end
	local state = stateOf(value)
	if state == nil then return end
	known[id] = state
	local door = native and live(native, id) or nil
	if door then apply(native, door, state) end
end)

--- @author DemiAutomatic
--- @event opx77_admin:doors
--- @description Collects the full list of this bucket, releasing doors it no longer names.
--- @param payload {table}
RegisterNetEvent('opx77_admin:doors', function(payload)
	if type(payload) ~= 'table' or type(payload.rows) ~= 'table' then return end
	if payload.offset == 0 then incoming = {} end
	for _, row in ipairs(payload.rows) do
		local state = stateOf(row)
		if state and type(row.id) == 'string' and #row.id <= 18 then incoming[row.id] = state end
	end
	if payload.done ~= true then return end
	local previous = known
	known, incoming, streamed = incoming, {}, {}
	local native = doors()
	if native == nil then return end
	for id in pairs(previous) do
		if known[id] == nil then release(native, id) end
	end
end)

--- @author DemiAutomatic
--- @method scan
--- @description Gives each door that streamed in its state, and puts back a lock or seal the game lifted.
local function scan()
	local native = doors()
	if native == nil or (next(known) == nil and next(streamed) == nil) then return end
	local read, list = pcall(native.near, RADIUS)
	if not read or type(list) ~= 'table' then return end
	local current = {}
	for _, door in ipairs(list) do
		local state = type(door) == 'table' and type(door.id) == 'string' and known[door.id] or nil
		if state then
			current[door.id] = true
			local drifted = (state.locked ~= nil and door.locked ~= state.locked)
				or (state.sealed ~= nil and door.sealed ~= state.sealed)
			if not streamed[door.id] or drifted then apply(native, door, state) end
		end
	end
	streamed = current
end

CreateThread(function()
	while true do
		Wait(SCAN_MS)
		local scanned, failure = pcall(scan)
		if not scanned then Open77.log.warn('door scan failed: ' .. tostring(failure)) end
	end
end)

--- @author DemiAutomatic
--- @event onClientResourceStart
--- @description Asks the server for this bucket's list.
--- @param name {string}
AddEventHandler('onClientResourceStart', function(name)
	if name ~= Client.RESOURCE then return end
	TriggerServerEvent('opx77_admin:doorsHello')
end)

--- @author DemiAutomatic
--- @event onClientResourceStop
--- @description Gives every streamed door this resource held back to its default.
--- @param name {string}
AddEventHandler('onClientResourceStop', function(name)
	if name ~= Client.RESOURCE then return end
	local native = doors()
	if native then
		for id in pairs(known) do release(native, id) end
	end
	known, streamed = {}, {}
end)
