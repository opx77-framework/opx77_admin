--- The client half's plumbing: the export-call helper, the command channel, and the two
--- capabilities that only exist on the client -- noclip and map travel -- applied when an
--- ACL-gated server command says so. It holds no authority and asserts none.

OpxAdmin = OpxAdmin or {}

local Text = OpxAdmin.Text

local Client = {}
OpxAdmin.Client = Client

local RESOURCE = GetCurrentResourceName()
Client.RESOURCE = RESOURCE

--- The dispatcher acknowledges a queued command on the same event as a command's own answer,
--- and only its English wording tells the two apart. Matched as the fragment both known
--- wordings share -- `queued by <resource>` and `command '<name>' queued by resource
--- <resource>` -- not anchored. See opx77_chat/docs/unknowns.md.
local QUEUE_ACK = 'queued by '

--- The scheduler clock in milliseconds; `monotonic` answers SECONDS. A non-finite reading is
--- dropped rather than propagated: a NaN would expire nothing, an infinity everything.
local lastMs = 0
---@return integer
function Client.nowMs()
	local read, seconds = pcall(Open77.time.monotonic)
	if read and type(seconds) == 'number' and seconds == seconds and
		seconds >= 0 and seconds < math.huge then
		lastMs = math.floor(seconds * 1000)
	end
	return lastMs
end

---@param resource string
---@return boolean
function Client.running(resource)
	local read, state = pcall(GetResourceState, resource)
	return read and state == 'running'
end

--- One call to another resource's client export; coroutine only. The third return says
--- whether the target answered at all, because a refusal is authoritative and a call that
--- never landed says nothing.
---@param resource string
---@param name string
---@return table|nil result, string|nil reason, boolean answered
function Client.call(resource, name, ...)
	if not Client.running(resource) then return nil, 'not_running', false end
	if Open77.exports == nil then return nil, 'not_dispatched', false end
	-- the wrapping stops here: `await` below yields, and a yield is not safe under a pcall
	local dispatched, promise, reason = pcall(Open77.exports.call, resource, name, ...)
	if not dispatched then return nil, tostring(promise), false end
	-- tested for presence, never for its Lua type: the host's promise is userdata, not a table
	if not promise then return nil, tostring(reason or 'not_dispatched'), false end
	local result, callError = promise:await()
	if callError then return nil, tostring(callError), false end
	if type(result) ~= 'table' then return nil, 'malformed_answer', true end
	if result.ok == false then return nil, tostring(result.error or 'refused'), true end
	return result, nil, true
end

--- Soft dependencies already reported, so a missing one costs one line, not one per click.
local reported = {}

--- Whether a soft dependency is up; says so once when it is not.
---@param resource string
---@return boolean
function Client.need(resource)
	if Client.running(resource) then return true end
	if not reported[resource] then
		reported[resource] = true
		Open77.log.warn(('%s is not running; the staff menu cannot use it'):format(resource))
	end
	return false
end

--- Whether a toast that could not be raised has been logged: one line, not one per answer.
local toastReported = false

--- The chat line an answer was before it was a toast, for when there is no toast to raise.
---@param kind string
---@param message string
local function chatLine(kind, message)
	local accepted = kind == 'info' or kind == 'success'
	TriggerEvent('chat:addMessage', {
		type = accepted and 'info' or 'error',
		author = locale('admin.toast.title'),
		text = message,
		color = accepted and { 120, 220, 232 } or { 255, 76, 92 },
	})
end

--- A toast of this resource's own, text already rendered, through opx77_notify while it runs;
--- a chat line when it does not or refuses the toast. Best-effort, never a dependency.
---@param kind string  info | success | warning | error
---@param message string
function Client.notice(kind, message)
	CreateThread(function()
		local _, failure = Client.call('opx77_notify', 'show', {
			-- one slot, replaced: staff clicking through a screen see the last answer, not a stack
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

--- `Client.notice` from a catalogue key.
---@param key string
---@param params? table
---@param kind? string
function Client.toast(key, params, kind)
	Client.notice(kind or 'info', locale(key, params))
end

-- ---------------------------------------------------------------------------
-- The command channel
-- ---------------------------------------------------------------------------

--- Command name -> when the menu sent it, so its answer can be put under the list.
local awaiting = {}

--- Send one command line exactly as the chat box would. The server resolves `command.<first
--- token>` against this player's ACL before any handler runs, so this is not a door into
--- anything: it is the same door, used by a menu instead of a keyboard.
---@param tokens string[]
---@return boolean sent
function Client.execute(tokens)
	local clean = {}
	for _, token in ipairs(type(tokens) == 'table' and tokens or {}) do
		-- the transport refuses control characters and a token past 256 bytes outright
		local word = Text.clean(token, 256)
		if word then
			for piece in word:gmatch('%S+') do clean[#clean + 1] = Text.bytes(piece, 256) end
		end
	end
	if #clean == 0 or #clean > 32 then return false end
	local sent, reason = TriggerServerEvent('open77:command:execute', table.unpack(clean))
	if not sent then
		Open77.log.warn(('command %s not sent: %s'):format(clean[1], tostring(reason)))
		return false
	end
	awaiting[clean[1]:lower()] = Client.nowMs()
	return true
end

--- Put an answer under the list when it answers a command this menu sent in the last fifteen
--- seconds. Other resources share the result events.
---@param raw string
---@param accepted boolean
---@param message string
---@return boolean sentByMenu
local function underList(raw, accepted, message)
	local name = (raw:match('^/?(%S+)') or ''):lower()
	local sentAt = awaiting[name]
	if sentAt == nil or Client.nowMs() - sentAt > 15000 then return false end
	local Menu = OpxAdmin.Menu
	if Menu then Menu.status(message, accepted == true) end
	return true
end

--- Another resource's answer, or the dispatcher's: its queue acknowledgement, dropped, or a
--- refusal, whose code is put in words. opx77_chat toasts the refusal as well.
---
--- opx77_chat prints no accepted result, so a report of a linked command the menu sent -- the
--- holders of an item, from opx77_inventory -- is a chat line here, as this resource's own
--- reports are: the line under the list holds only its first line.
RegisterNetEvent('open77:command:result', function(raw, accepted, message)
	if type(raw) ~= 'string' or type(message) ~= 'string' then return end
	if accepted == true and message:find(QUEUE_ACK, 1, true) then return end
	if accepted == true then
		if underList(raw, true, message) and message:find('\n', 1, true) then
			chatLine('info', message)
		end
		return
	end
	-- a speed the speed keys sent and the host refused: the strip's read-out goes back
	if OpxAdmin.Controls then OpxAdmin.Controls.answered(raw, false) end
	local name = raw:match('^/?(%S+)') or raw
	if message == 'unknown_command' then
		message = locale('admin.client.unknownCommand', { command = name })
	elseif message:find('permission_denied:', 1, true) == 1 then
		message = locale('admin.client.denied', { command = name })
	end
	underList(raw, false, message)
end)

--- This resource's own answer: under the list when the menu sent it, and besides that a chat
--- line for a report, a toast for an action's outcome, since the menu may be closed and a
--- typed command has no list.
RegisterNetEvent('opx77_admin:answer', function(raw, accepted, message, kind)
	if type(raw) ~= 'string' or type(message) ~= 'string' or message == '' then return end
	underList(raw, accepted == true, message)
	if kind == 'report' then return chatLine('info', message) end
	-- a speed the speed keys chose: the strip already shows it, and a toast per press is noise
	if OpxAdmin.Controls and OpxAdmin.Controls.answered(raw, accepted == true) then return end
	if kind ~= 'info' and kind ~= 'success' and kind ~= 'warning' and kind ~= 'error' then
		kind = accepted == true and 'success' or 'error'
	end
	Client.notice(kind, message)
end)

-- ---------------------------------------------------------------------------
-- Travel
-- ---------------------------------------------------------------------------

---@param name string
---@return function|nil
local function travelNative(name)
	local travel = Open77.travel
	if type(travel) ~= 'table' or type(travel[name]) ~= 'function' then return nil end
	return travel[name]
end

--- Whether map travel is armed here: a picked point is only sent back while it is.
local mapArmed = false

--- Whether this resource switched noclip on, so its stop only undoes its own switch.
local noclipOn = false

---@param name string
---@param value any
local function applyTravel(name, value)
	local native = travelNative(name)
	if native == nil then
		Open77.log.warn(('Open77.travel.%s is not in this client build'):format(name))
		Client.toast('admin.client.travelMissing', nil, 'error')
		return false
	end
	local ok, reason = native(value)
	if not ok then Open77.log.warn(('%s refused: %s'):format(name, tostring(reason))) end
	return ok == true
end

--- Delegated from an ACL-gated server command. Any client resource can raise this name
--- locally, which buys it nothing it could not do with its own travel grant; the clipboard
--- write is kept to the one line shape the server sends.
RegisterNetEvent('opx77_admin:travel', function(action, value)
	local Controls = OpxAdmin.Controls
	if action == 'noclip' then
		if applyTravel('setNoclip', value == true) then noclipOn = value == true end
		if Controls then Controls.noclip(noclipOn) end
	elseif action == 'speed' then
		local speed = Text.finite(value)
		if speed and speed >= 0.1 and speed <= 500 and applyTravel('setNoclipSpeed', speed)
			and Controls then
			Controls.speed(speed)
		end
	elseif action == 'mapPick' then
		mapArmed = value == true and applyTravel('setMapPick', true)
		if value ~= true then applyTravel('setMapPick', false) end
		if Controls then Controls.mapPick(mapArmed) end
	elseif action == 'copy' then
		if type(value) ~= 'string' or #value > 160 or not value:match('^{ NAME = ') then return end
		local clipboard = Open77.clipboard
		if type(clipboard) == 'table' and type(clipboard.setText) == 'function' then
			pcall(clipboard.setText, value)
		end
	end
end)

--- A point double-clicked on the world map, raised by the host while map picking is armed. It
--- goes back as a command line, so the ACL is resolved again on every jump.
AddEventHandler('open77:map:picked', function(x, y, z)
	if not mapArmed then return end
	x, y, z = Text.finite(x), Text.finite(y), Text.finite(z)
	if x == nil or y == nil or z == nil then return end
	Client.execute({ 'opx77.admin.self.maptravel', ('%.3f'):format(x), ('%.3f'):format(y),
		('%.3f'):format(z) })
end)

AddEventHandler('onClientResourceStop', function(name)
	if name ~= RESOURCE then return end
	-- fail safe: nothing is left flying, or with a map that teleports, once this code is gone
	if noclipOn and travelNative('setNoclip') then pcall(Open77.travel.setNoclip, false) end
	noclipOn = false
	if mapArmed and travelNative('setMapPick') then pcall(Open77.travel.setMapPick, false) end
	mapArmed = false
end)
