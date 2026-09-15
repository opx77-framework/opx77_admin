--- The travel modes while they are on: the two keys that change the noclip speed, and the
--- controls drawn in opx77_prompts' strip. Nothing here moves anybody or sets a speed. A key
--- only chooses a number; the number goes to the server as /opx77.admin.self.speed, so the ACL
--- resolves it like a typed one, and the native is only ever set by the server's answer.
---
--- Not the mouse wheel. Open77.input.isDown reads A-Z, 0-9, F1-F12 and a closed list of named
--- keys, RegisterKeyMapping takes the same vocabulary, and no client call reports a wheel.

OpxAdmin = OpxAdmin or {}

local Config = OPX_ADMIN_CONFIG
local Client = OpxAdmin.Client
local Keys = OpxAdmin.Keys
local Text = OpxAdmin.Text

local Controls = {}
OpxAdmin.Controls = Controls

local PROMPTS = 'opx77_prompts'
local SPEED_COMMAND = 'opx77.admin.self.speed'

--- Mapping ids. Stable: a player's rebind is stored under them.
local KEY_FASTER = 'opx77_admin.noclipFaster'
local KEY_SLOWER = 'opx77_admin.noclipSlower'
local KEY_MENU = 'opx77_admin.menu'

--- The group ids in the strip, and where noclip sits in it: above anything a gameplay resource
--- puts up, because staff flying about is the one thing that must be read first.
local GROUP_NOCLIP = 'noclip'
local GROUP_MAP = 'maptravel'
local NOCLIP_PRIORITY = 50

--- How a held key repeats: the first repeat after a pause, then steady.
local REPEAT_DELAY_MS = 350
local REPEAT_MS = 110

--- How often the native state and the body are looked at while noclip is on, and how many
--- reads of "off", how long after switching on, before the strip believes the native.
local TICK_MS = 100
local OFF_READS = 3
local OFF_SETTLE_MS = 1000

--- How long after a keyed send its answer is taken as the keys' own, and kept off a toast.
local ANSWER_WINDOW_MS = 5000

-- ---------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------

local noclipConfig = type(Config.NOCLIP) == 'table' and Config.NOCLIP or {}
local rate = type(Config.RATE) == 'table' and Config.RATE or {}

---@param path string
---@param value any
---@param low number
---@param high number
---@param default number
---@return number
local function bounded(path, value, low, high, default)
	if value == nil then return default end
	local number = Text.finite(value)
	if number ~= nil and number >= low and number <= high then return number end
	Open77.log.warn(('config: %s must be a number in %s..%s; using %s'):format(path, low, high,
		default))
	return default
end

local MIN_SPEED = bounded('NOCLIP.MIN_SPEED', noclipConfig.MIN_SPEED, 0.1, 500, 1.0)
local MAX_SPEED = bounded('NOCLIP.MAX_SPEED', noclipConfig.MAX_SPEED, MIN_SPEED, 500, 500.0)
local STEP = bounded('NOCLIP.STEP', noclipConfig.STEP, 0.01, 1, 0.15)
local DEFAULT_SPEED = bounded('NOCLIP.SPEED', noclipConfig.SPEED, 0.1, 500, 40.0)
-- the server refuses a second mutating command inside RATE.ACTION_MS; a send never lands in it
local SEND_FLOOR_MS = math.floor(bounded('RATE.ACTION_MS', rate.ACTION_MS, 0, 60000, 400)) + 100
local SEND_AFTER_MS = math.max(SEND_FLOOR_MS,
	math.floor(bounded('NOCLIP.SEND_AFTER_MS', noclipConfig.SEND_AFTER_MS, 0, 10000, 500)))
local SHOW_PROMPTS = noclipConfig.PROMPTS ~= false

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------

--- Whether a server command switched noclip on here, and map travel; when noclip went on, and
--- how many ticks in a row the native has said it is off.
local noclipOn = false
local mapOn = false
local noclipSinceMs = 0
local offReads = 0

--- The speed the server last applied, the one the keys have chosen and not yet had applied,
--- and the one on its way.
local applied = nil
local wanted = nil
local sent = nil
local sentAtMs = -math.huge
local lastStepMs = 0

--- +1 or -1 while a speed key is held, and when it next repeats.
local held = 0
local nextRepeatMs = 0

--- What is up in the strip: nil, or the signature of what was last put there.
local shownNoclip = nil
local shownMap = false

--- Whether a tick thread is running.
local ticking = false

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

---@param speed number
---@return string
local function format(speed)
	return ('%g'):format(speed)
end

---@return number
local function current()
	return wanted or applied or DEFAULT_SPEED
end

--- One step up or down: a fraction of the speed, so the low end tunes finely and the high end
--- crosses the range in a few seconds of holding. Half a metre a second at the least.
---@param speed number
---@param direction integer
---@return number
local function stepped(speed, direction)
	local nextSpeed = direction > 0 and speed * (1 + STEP) or speed / (1 + STEP)
	if math.abs(nextSpeed - speed) < 0.5 then nextSpeed = speed + 0.5 * direction end
	if nextSpeed < 10 then
		nextSpeed = math.floor(nextSpeed * 2 + 0.5) / 2
	else
		nextSpeed = math.floor(nextSpeed + 0.5)
	end
	return math.max(MIN_SPEED, math.min(MAX_SPEED, nextSpeed))
end

---@param name string
---@return function|nil
local function travelNative(name)
	local travel = Open77.travel
	if type(travel) ~= 'table' or type(travel[name]) ~= 'function' then return nil end
	return travel[name]
end

--- Whether the native still has noclip on. A client without the read counts as on: the server
--- command is what says so.
---@return boolean
local function nativeNoclip()
	local read = travelNative('isNoclip')
	if read == nil then return true end
	local ok, on = pcall(read)
	return not ok or on == true
end

---@return boolean
local function alive()
	local character = Open77.character
	if type(character) ~= 'table' or type(character.state) ~= 'function' then return true end
	local ok, state = pcall(character.state)
	if not ok or type(state) ~= 'table' then return true end
	return state.alive ~= false
end

---@return boolean
local function captured()
	local input = Open77.input
	if type(input) ~= 'table' or type(input.isCaptured) ~= 'function' then return false end
	local ok, answer = pcall(input.isCaptured)
	return ok and answer == true
end

-- ---------------------------------------------------------------------------
-- The strip
-- ---------------------------------------------------------------------------

--- Whether a missing opx77_prompts has been said: one line, not one per mode switch.
local promptsReported = false

---@return boolean
local function promptsUp()
	if not SHOW_PROMPTS then return false end
	if Client.running(PROMPTS) then return true end
	if not promptsReported then
		promptsReported = true
		Open77.log.info(PROMPTS .. ' is not running; the travel controls are not drawn')
	end
	return false
end

---@return table
local function noclipSpec()
	local rows = {
		{ keys = 'W A S D', label = locale('admin.prompt.move') },
		{ keys = { 'SPACE', 'CTRL' }, label = locale('admin.prompt.upDown') },
	}
	local speedKeys = {}
	if Keys.effective(KEY_FASTER) then speedKeys[#speedKeys + 1] = { mapping = KEY_FASTER } end
	if Keys.effective(KEY_SLOWER) then speedKeys[#speedKeys + 1] = { mapping = KEY_SLOWER } end
	if #speedKeys > 0 then
		rows[#rows + 1] = { id = 'speed', keys = speedKeys, label = locale('admin.prompt.speed'),
			value = locale('admin.prompt.speedValue', { speed = format(current()) }) }
	end
	rows[#rows + 1] = { keys = 'SHIFT', hold = true, label = locale('admin.prompt.fast') }
	rows[#rows + 1] = { keys = 'ALT', hold = true, label = locale('admin.prompt.slow') }
	if Keys.effective(KEY_MENU) then
		rows[#rows + 1] = { keys = { mapping = KEY_MENU }, label = locale('admin.prompt.off') }
	end
	return { title = locale('admin.prompt.noclip'), priority = NOCLIP_PRIORITY, rows = rows }
end

---@return table
local function mapSpec()
	return { title = locale('admin.prompt.map'), priority = NOCLIP_PRIORITY - 1, rows = {
		{ keys = locale('admin.prompt.doubleClick'), label = locale('admin.prompt.mapTravel') },
	} }
end

--- Bring the strip in line with the modes: up, down, or the speed read-out changed. The calls
--- run in a thread of their own, because an export call is awaited.
local function sync()
	local body = alive()
	local wantNoclip = noclipOn and body
	local wantMap = mapOn and body
	-- which rows exist hangs on which keys are registered; the keys' names are opx77_prompts'
	local signature = wantNoclip and table.concat({ format(current()),
		tostring(Keys.effective(KEY_FASTER) ~= nil), tostring(Keys.effective(KEY_SLOWER) ~= nil),
		tostring(Keys.effective(KEY_MENU) ~= nil) }, '|') or nil
	if signature == shownNoclip and wantMap == shownMap then return end
	if not promptsUp() then
		shownNoclip, shownMap = nil, false
		return
	end
	-- marked before the call lands, so the next tick does not send the same group again; a
	-- refusal is logged once and not retried every tick
	local noclipChanged, mapChanged = signature ~= shownNoclip, wantMap ~= shownMap
	shownNoclip, shownMap = signature, wantMap
	local spec = signature and noclipSpec() or nil
	-- Every change is sent, in order: each thread dispatches its call before the next one runs,
	-- so a hide queued behind a show is never skipped.
	CreateThread(function()
		if noclipChanged then
			local _, failure
			if spec == nil then
				_, failure = Client.call(PROMPTS, 'hide', GROUP_NOCLIP)
			else
				_, failure = Client.call(PROMPTS, 'show', GROUP_NOCLIP, spec)
			end
			if failure and not promptsReported then
				promptsReported = true
				Open77.log.warn('noclip prompts refused: ' .. failure)
			end
		end
		if mapChanged then
			if wantMap then
				Client.call(PROMPTS, 'show', GROUP_MAP, mapSpec())
			else
				Client.call(PROMPTS, 'hide', GROUP_MAP)
			end
		end
	end)
end

-- ---------------------------------------------------------------------------
-- Speed
-- ---------------------------------------------------------------------------

---@param direction integer
local function step(direction)
	local nextSpeed = stepped(current(), direction)
	lastStepMs = Client.nowMs()
	if nextSpeed == current() then return end
	wanted = nextSpeed
	sync()
end

--- Send the chosen speed once the keys have been quiet for SEND_AFTER_MS.
local function flush(atMs)
	if wanted == nil or held ~= 0 or atMs - lastStepMs < SEND_AFTER_MS then return end
	if applied ~= nil and math.abs(wanted - applied) < 0.001 then
		wanted = nil
		return
	end
	if sent ~= nil and math.abs(wanted - sent) < 0.001 and atMs - sentAtMs < ANSWER_WINDOW_MS then
		return -- on its way already
	end
	if Client.execute({ SPEED_COMMAND, format(wanted) }) then
		sent, sentAtMs = wanted, atMs
	else
		wanted = nil
		sync()
	end
end

local function tick()
	local atMs = Client.nowMs()
	if noclipOn and not nativeNoclip() then
		-- Switched off under us, by another resource, a death or the native itself. Several reads
		-- and a settle time first: the native may not report a switch the same frame it took it.
		offReads = offReads + 1
		if offReads >= OFF_READS and atMs - noclipSinceMs >= OFF_SETTLE_MS then
			noclipOn, held, wanted = false, 0, nil
		end
	else
		offReads = 0
	end
	if captured() then held = 0 end
	if held ~= 0 and atMs >= nextRepeatMs then
		nextRepeatMs = atMs + REPEAT_MS
		step(held)
	end
	flush(atMs)
	sync()
end

local function startTicking()
	if ticking then return end
	ticking = true
	CreateThread(function()
		while noclipOn or mapOn or wanted ~= nil do
			local ok, failure = pcall(tick)
			if not ok then Open77.log.error('travel controls: ' .. tostring(failure)) end
			Wait(TICK_MS)
		end
		ticking = false
		sync()
	end)
end

---@param direction integer
local function pressed(direction)
	if not noclipOn then return end
	held = direction
	nextRepeatMs = Client.nowMs() + REPEAT_DELAY_MS
	step(direction)
	startTicking()
end

---@param direction integer
local function released(direction)
	if held == direction then held = 0 end
end

-- ---------------------------------------------------------------------------
-- What client/main.lua reports
-- ---------------------------------------------------------------------------

--- Noclip was switched on or off by a server command, and the native took it.
---@param on boolean
function Controls.noclip(on)
	noclipOn = on == true
	noclipSinceMs, offReads = Client.nowMs(), 0
	if not noclipOn then held, wanted = 0, nil end
	sync()
	if noclipOn then startTicking() end
end

--- Map travel was armed or disarmed.
---@param on boolean
function Controls.mapPick(on)
	mapOn = on == true
	sync()
	if mapOn then startTicking() end
end

--- The server applied a speed.
---@param speed number
function Controls.speed(speed)
	applied = speed
	-- `sent` stays: the command's answer is sent after this push, and is matched against it
	if wanted ~= nil and math.abs(wanted - speed) < 0.001 then wanted = nil end
	sync()
end

--- A command answer. True when it answers a speed the keys sent and was accepted: the strip
--- already shows that number, so it is kept off a toast. A refusal puts the read-out back to
--- the speed the server has, and is toasted as usual.
---@param raw string
---@param accepted boolean
---@return boolean quiet
function Controls.answered(raw, accepted)
	local name = (raw:match('^/?(%S+)') or ''):lower()
	if name ~= SPEED_COMMAND or sent == nil then return false end
	if Client.nowMs() - sentAtMs > ANSWER_WINDOW_MS then return false end
	if accepted then return true end
	sent, wanted = nil, nil
	sync()
	return false
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

AddEventHandler('onClientResourceStart', function(name)
	if name == PROMPTS then
		-- a restarted strip lost every group: put ours back
		shownNoclip, shownMap = nil, false
		promptsReported = false
		return sync()
	end
	if name ~= Client.RESOURCE then return end
	local keys = type(Config.KEYS) == 'table' and Config.KEYS or {}
	Keys.register(KEY_FASTER, 'admin.key.speedUp',
		Keys.setting('KEYS.SPEED_UP', keys.SPEED_UP, 'PAGEUP'),
		function() pressed(1) end, function() released(1) end)
	Keys.register(KEY_SLOWER, 'admin.key.speedDown',
		Keys.setting('KEYS.SPEED_DOWN', keys.SPEED_DOWN, 'PAGEDOWN'),
		function() pressed(-1) end, function() released(-1) end)
end)

AddEventHandler('onClientResourceStop', function(name)
	if name == PROMPTS then
		shownNoclip, shownMap = nil, false
	end
	-- this resource's own stop: opx77_prompts drops a stopped owner's groups by itself
end)

-- a rebind changes the keys the strip names; opx77_prompts follows it, but a speed key switched
-- on or off is a different set of rows
Keys.onChanged(sync)
