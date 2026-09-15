--- @author DemiAutomatic
--- @file client/main.lua
--- @description Client plumbing: export calls, answers, the command channel and travel.

OpxAdmin = OpxAdmin or {}

local Text = OpxAdmin.Text

--- @author DemiAutomatic
--- @type {table}
--- @description The client helpers the other client files call.
OpxAdmin.Client = {}
local Client = OpxAdmin.Client

--- @author DemiAutomatic
--- @type {string}
--- @description This resource's name, as the host reports it.
local RESOURCE = GetCurrentResourceName()
Client.RESOURCE = RESOURCE

--- @author DemiAutomatic
--- @type {string}
--- @description Fragment both known queue acknowledgement wordings share.
local QUEUE_ACK = 'queued by '

--- @author DemiAutomatic
--- @type {integer}
--- @description The last finite scheduler reading, in milliseconds.
local lastMs = 0

--- @author DemiAutomatic
--- @method OpxAdmin.Client.NowMs
--- @description Scheduler clock in milliseconds, holding the last finite reading.
--- @returns {integer}
function OpxAdmin.Client.NowMs()
	local read, seconds = pcall(Open77.time.monotonic)
	if read and type(seconds) == 'number' and seconds == seconds and
		seconds >= 0 and seconds < math.huge then
		lastMs = math.floor(seconds * 1000)
	end
	return lastMs
end

--- @author DemiAutomatic
--- @method OpxAdmin.Client.Running
--- @description Whether another resource is in the running state.
--- @param resource {string}
--- @returns {boolean}
function OpxAdmin.Client.Running(resource)
	local read, state = pcall(GetResourceState, resource)
	return read and state == 'running'
end

--- @author DemiAutomatic
--- @method OpxAdmin.Client.Call
--- @description Calls another resource's client export and awaits its answer.
--- @param resource {string}
--- @param name {string}
--- @returns {table|nil, string|nil, boolean}
function OpxAdmin.Client.Call(resource, name, ...)
	if not Client.Running(resource) then return nil, 'not_running', false end
	if Open77.exports == nil then return nil, 'not_dispatched', false end
	local dispatched, promise, reason = pcall(Open77.exports.call, resource, name, ...)
	if not dispatched then return nil, tostring(promise), false end
	if not promise then return nil, tostring(reason or 'not_dispatched'), false end
	local result, callError = promise:await()
	if callError then return nil, tostring(callError), false end
	if type(result) ~= 'table' then return nil, 'malformed_answer', true end
	if result.ok == false then return nil, tostring(result.error or 'refused'), true end
	return result, nil, true
end

--- @author DemiAutomatic
--- @type {table<string, boolean>}
--- @description Soft dependencies already reported missing, one log line each.
local reported = {}

--- @author DemiAutomatic
--- @method OpxAdmin.Client.Need
--- @description Whether a soft dependency runs, logging its absence once.
--- @param resource {string}
--- @returns {boolean}
function OpxAdmin.Client.Need(resource)
	if Client.Running(resource) then return true end
	if not reported[resource] then
		reported[resource] = true
		Open77.log.warn(('%s is not running; the staff menu cannot use it'):format(resource))
	end
	return false
end

--- @author DemiAutomatic
--- @type {boolean}
--- @description Whether a toast that could not be raised was logged.
local toastReported = false

--- @author DemiAutomatic
--- @method chatLine
--- @description Writes an answer into the chat box when no toast is raised.
--- @param kind {string}
--- @param message {string}
local function chatLine(kind, message)
	local accepted = kind == 'info' or kind == 'success'
	TriggerEvent('chat:addMessage', {
		type = accepted and 'info' or 'error',
		author = locale('admin.toast.title'),
		text = message,
		color = accepted and { 120, 220, 232 } or { 255, 76, 92 },
	})
end

--- @author DemiAutomatic
--- @method OpxAdmin.Client.Notice
--- @description Raises this resource's toast, or a chat line without one.
--- @param kind {string} info, success, warning or error.
--- @param message {string}
function OpxAdmin.Client.Notice(kind, message)
	CreateThread(function()
		local _, failure = Client.Call('opx77_notify', 'show', {
			id = 'opx77_admin', replace = true, type = kind,
			title = locale('admin.toast.title'), message = message, durationMs = 5000,
		})
		if failure == nil then return end
		if not toastReported then
			toastReported = true
			Open77.log.warn(('no toast (%s): staff answers go to the chat box instead')
				:format(failure))
		end
		chatLine(kind, message)
	end)
end

--- @author DemiAutomatic
--- @method OpxAdmin.Client.Toast
--- @description Raises a notice whose text comes from a catalogue key.
--- @param key {string}
--- @param params {table|nil}
--- @param kind {string|nil}
function OpxAdmin.Client.Toast(key, params, kind)
	Client.Notice(kind or 'info', locale(key, params))
end

--- @author DemiAutomatic
--- @type {table<string, integer>}
--- @description Command name to when the menu sent it.
local awaiting = {}

--- @author DemiAutomatic
--- @method OpxAdmin.Client.Execute
--- @description Sends one command line exactly as the chat box would.
--- @param tokens {string[]}
--- @returns {boolean}
function OpxAdmin.Client.Execute(tokens)
	local clean = {}
	for _, token in ipairs(type(tokens) == 'table' and tokens or {}) do
		local word = Text.Clean(token, 256)
		if word then
			for piece in word:gmatch('%S+') do clean[#clean + 1] = Text.Bytes(piece, 256) end
		end
	end
	if #clean == 0 or #clean > 32 then return false end
	local sent, reason = TriggerServerEvent('open77:command:execute', table.unpack(clean))
	if not sent then
		Open77.log.warn(('command %s not sent: %s'):format(clean[1], tostring(reason)))
		return false
	end
	awaiting[clean[1]:lower()] = Client.NowMs()
	return true
end

--- @author DemiAutomatic
--- @method underList
--- @description Writes an answer under the list when the menu sent it lately.
--- @param raw {string}
--- @param accepted {boolean}
--- @param message {string}
--- @returns {boolean}
local function underList(raw, accepted, message)
	local name = (raw:match('^/?(%S+)') or ''):lower()
	local sentAt = awaiting[name]
	if sentAt == nil or Client.NowMs() - sentAt > 15000 then return false end
	OpxAdmin.Menu.Status(message, accepted == true)
	return true
end

--- @author DemiAutomatic
--- @event open77:command:result
--- @description Handles the dispatcher's acknowledgements, refusals and linked reports.
--- @param raw {string}
--- @param accepted {boolean}
--- @param message {string}
RegisterNetEvent('open77:command:result', function(raw, accepted, message)
	if type(raw) ~= 'string' or type(message) ~= 'string' then return end
	if accepted == true and message:find(QUEUE_ACK, 1, true) then return end
	if accepted == true then
		if underList(raw, true, message) and message:find('\n', 1, true) then
			chatLine('info', message)
		end
		return
	end
	OpxAdmin.Controls.Answered(raw, false)
	local name = raw:match('^/?(%S+)') or raw
	if message == 'unknown_command' then
		message = locale('admin.client.unknownCommand', { command = name })
	elseif message:find('permission_denied:', 1, true) == 1 then
		message = locale('admin.client.denied', { command = name })
	end
	underList(raw, false, message)
end)

--- @author DemiAutomatic
--- @event opx77_admin:answer
--- @description Shows this resource's answer under the list, in chat or toast.
--- @param raw {string}
--- @param accepted {boolean}
--- @param message {string}
--- @param kind {string} report, info, success, warning or error.
RegisterNetEvent('opx77_admin:answer', function(raw, accepted, message, kind)
	if type(raw) ~= 'string' or type(message) ~= 'string' or message == '' then return end
	underList(raw, accepted == true, message)
	if kind == 'report' then return chatLine('info', message) end
	if OpxAdmin.Controls.Answered(raw, accepted == true) then return end
	if kind ~= 'info' and kind ~= 'success' and kind ~= 'warning' and kind ~= 'error' then
		kind = accepted == true and 'success' or 'error'
	end
	Client.Notice(kind, message)
end)

--- @author DemiAutomatic
--- @method OpxAdmin.Client.TravelNative
--- @description One Open77.travel function, or nil when this build lacks it.
--- @param name {string}
--- @returns {function|nil}
function OpxAdmin.Client.TravelNative(name)
	local travel = Open77.travel
	if type(travel) ~= 'table' or type(travel[name]) ~= 'function' then return nil end
	return travel[name]
end

--- @author DemiAutomatic
--- @type {boolean}
--- @description Whether map travel is armed, so picked points are sent.
local mapArmed = false

--- @author DemiAutomatic
--- @type {boolean}
--- @description Whether this resource switched noclip on.
local noclipOn = false

--- @author DemiAutomatic
--- @method applyTravel
--- @description Applies one travel native, logging a missing or refused one.
--- @param name {string}
--- @param value {any}
--- @returns {boolean}
local function applyTravel(name, value)
	local native = Client.TravelNative(name)
	if native == nil then
		Open77.log.warn(('Open77.travel.%s is not in this client build'):format(name))
		Client.Toast('admin.client.travelMissing', nil, 'error')
		return false
	end
	local ok, reason = native(value)
	if not ok then Open77.log.warn(('%s refused: %s'):format(name, tostring(reason))) end
	return ok == true
end

--- @author DemiAutomatic
--- @event opx77_admin:travel
--- @description Applies noclip, speed, map picking or a clipboard row from the server.
--- @param action {string} noclip, speed, mapPick or copy.
--- @param value {any}
RegisterNetEvent('opx77_admin:travel', function(action, value)
	if action == 'noclip' then
		if applyTravel('setNoclip', value == true) then noclipOn = value == true end
		OpxAdmin.Controls.Noclip(noclipOn)
	elseif action == 'speed' then
		local speed = Text.Finite(value)
		if speed and speed >= 0.1 and speed <= 500 and applyTravel('setNoclipSpeed', speed) then
			OpxAdmin.Controls.Speed(speed)
		end
	elseif action == 'mapPick' then
		mapArmed = value == true and applyTravel('setMapPick', true)
		if value ~= true then applyTravel('setMapPick', false) end
		OpxAdmin.Controls.MapPick(mapArmed)
	elseif action == 'copy' then
		if type(value) ~= 'string' or #value > 160 or not value:match('^{ NAME = ') then return end
		local clipboard = Open77.clipboard
		if type(clipboard) == 'table' and type(clipboard.setText) == 'function' then
			pcall(clipboard.setText, value)
		end
	end
end)

--- @author DemiAutomatic
--- @event open77:map:picked
--- @description Sends a double-clicked map point back as a travel command.
--- @param x {number}
--- @param y {number}
--- @param z {number}
AddEventHandler('open77:map:picked', function(x, y, z)
	if not mapArmed then return end
	x, y, z = Text.Finite(x), Text.Finite(y), Text.Finite(z)
	if x == nil or y == nil or z == nil then return end
	Client.Execute({ 'opx77.admin.self.maptravel', ('%.3f'):format(x), ('%.3f'):format(y),
		('%.3f'):format(z) })
end)

--- @author DemiAutomatic
--- @event onClientResourceStop
--- @description Switches off the noclip and map picking this resource armed.
--- @param name {string}
AddEventHandler('onClientResourceStop', function(name)
	if name ~= RESOURCE then return end
	if noclipOn and Client.TravelNative('setNoclip') then pcall(Open77.travel.setNoclip, false) end
	noclipOn = false
	if mapArmed and Client.TravelNative('setMapPick') then pcall(Open77.travel.setMapPick, false) end
	mapArmed = false
end)
