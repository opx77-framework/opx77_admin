--- @author DemiAutomatic
--- @file client/controls.lua
--- @description Noclip speed keys and the travel controls in opx77_prompts' strip.

OpxAdmin = OpxAdmin or {}

local Config = OPX_ADMIN_CONFIG
local Client = OpxAdmin.Client
local Keys = OpxAdmin.Keys
local Text = OpxAdmin.Text

--- @author DemiAutomatic
--- @type {table}
--- @description What client/main.lua reports travel changes and answers to.
OpxAdmin.Controls = {}
local Controls = OpxAdmin.Controls

--- @author DemiAutomatic
--- @type {string}
--- @description The resource that draws the controls strip.
local PROMPTS = 'opx77_prompts'

--- @author DemiAutomatic
--- @type {string}
--- @description The command a chosen noclip speed is sent as.
local SPEED_COMMAND = 'opx77.admin.self.speed'

--- @author DemiAutomatic
--- @type {string}
--- @description Stable mapping id of the noclip faster key.
local KEY_FASTER = 'opx77_admin.noclipFaster'

--- @author DemiAutomatic
--- @type {string}
--- @description Stable mapping id of the noclip slower key.
local KEY_SLOWER = 'opx77_admin.noclipSlower'

--- @author DemiAutomatic
--- @type {string}
--- @description Stable mapping id of the menu key.
local KEY_MENU = 'opx77_admin.menu'

--- @author DemiAutomatic
--- @type {string}
--- @description Strip group id of the noclip controls.
local GROUP_NOCLIP = 'noclip'

--- @author DemiAutomatic
--- @type {string}
--- @description Strip group id of the map travel hint.
local GROUP_MAP = 'maptravel'

--- @author DemiAutomatic
--- @type {integer}
--- @description Strip priority of noclip, above gameplay groups.
local NOCLIP_PRIORITY = 50

--- @author DemiAutomatic
--- @type {integer}
--- @description Milliseconds before a held speed key first repeats.
local REPEAT_DELAY_MS = 350

--- @author DemiAutomatic
--- @type {integer}
--- @description Milliseconds between repeats of a held speed key.
local REPEAT_MS = 110

--- @author DemiAutomatic
--- @type {integer}
--- @description Milliseconds between two looks at the native and body.
local TICK_MS = 100

--- @author DemiAutomatic
--- @type {integer}
--- @description Consecutive off readings before the strip believes the native.
local OFF_READS = 3

--- @author DemiAutomatic
--- @type {integer}
--- @description Milliseconds after switching on before an off reading counts.
local OFF_SETTLE_MS = 1000

--- @author DemiAutomatic
--- @type {integer}
--- @description Milliseconds a keyed send's answer is taken as the keys'.
local ANSWER_WINDOW_MS = 5000

--- @author DemiAutomatic
--- @type {table}
--- @description The NOCLIP config table, or an empty one.
local noclipConfig = type(Config.NOCLIP) == 'table' and Config.NOCLIP or {}

--- @author DemiAutomatic
--- @type {table}
--- @description The RATE config table, or an empty one.
local rate = type(Config.RATE) == 'table' and Config.RATE or {}

--- @author DemiAutomatic
--- @method bounded
--- @description A configured number inside its range, else the default, logged.
--- @param path {string}
--- @param value {any}
--- @param low {number}
--- @param high {number}
--- @param default {number}
--- @returns {number}
local function bounded(path, value, low, high, default)
	if value == nil then return default end
	local number = Text.Finite(value)
	if number ~= nil and number >= low and number <= high then return number end
	Open77.log.warn(('config: %s must be a number in %s..%s; using %s'):format(path, low, high,
		default))
	return default
end

--- @author DemiAutomatic
--- @type {number}
--- @description The lowest speed the keys choose.
local MIN_SPEED = bounded('NOCLIP.MIN_SPEED', noclipConfig.MIN_SPEED, 0.1, 500, 1.0)

--- @author DemiAutomatic
--- @type {number}
--- @description The highest speed the keys choose.
local MAX_SPEED = bounded('NOCLIP.MAX_SPEED', noclipConfig.MAX_SPEED, MIN_SPEED, 500, 500.0)

--- @author DemiAutomatic
--- @type {number}
--- @description Fraction of the speed one press changes.
local STEP = bounded('NOCLIP.STEP', noclipConfig.STEP, 0.01, 1, 0.15)

--- @author DemiAutomatic
--- @type {number}
--- @description The speed shown before the server applied one.
local DEFAULT_SPEED = bounded('NOCLIP.SPEED', noclipConfig.SPEED, 0.1, 500, 40.0)

--- @author DemiAutomatic
--- @type {integer}
--- @description The server's action floor plus 100 milliseconds.
local SEND_FLOOR_MS = math.floor(bounded('RATE.ACTION_MS', rate.ACTION_MS, 0, 60000, 400)) + 100

--- @author DemiAutomatic
--- @type {integer}
--- @description Quiet milliseconds after the last press before sending.
local SEND_AFTER_MS = math.max(SEND_FLOOR_MS,
	math.floor(bounded('NOCLIP.SEND_AFTER_MS', noclipConfig.SEND_AFTER_MS, 0, 10000, 500)))

--- @author DemiAutomatic
--- @type {boolean}
--- @description Whether the travel controls are drawn in the strip.
local SHOW_PROMPTS = noclipConfig.PROMPTS ~= false

--- @author DemiAutomatic
--- @type {boolean}
--- @description Whether a server command switched noclip on here.
local noclipOn = false

--- @author DemiAutomatic
--- @type {boolean}
--- @description Whether a server command armed map travel here.
local mapOn = false

--- @author DemiAutomatic
--- @type {integer}
--- @description When noclip was last switched, in milliseconds.
local noclipSinceMs = 0

--- @author DemiAutomatic
--- @type {integer}
--- @description Consecutive ticks the native has reported noclip off.
local offReads = 0

--- @author DemiAutomatic
--- @type {number|nil}
--- @description The speed the server last applied.
local applied = nil

--- @author DemiAutomatic
--- @type {number|nil}
--- @description The speed the keys chose and the server has not applied.
local wanted = nil

--- @author DemiAutomatic
--- @type {number|nil}
--- @description The speed on its way to the server.
local sent = nil

--- @author DemiAutomatic
--- @type {number}
--- @description When the last speed was sent, in milliseconds.
local sentAtMs = -math.huge

--- @author DemiAutomatic
--- @type {integer}
--- @description When a speed key last stepped, in milliseconds.
local lastStepMs = 0

--- @author DemiAutomatic
--- @type {integer}
--- @description Plus or minus one while a speed key is held.
local held = 0

--- @author DemiAutomatic
--- @type {integer}
--- @description When the held speed key next repeats, in milliseconds.
local nextRepeatMs = 0

--- @author DemiAutomatic
--- @type {string|nil}
--- @description Signature of the noclip group last put in the strip.
local shownNoclip = nil

--- @author DemiAutomatic
--- @type {boolean}
--- @description Whether the map travel group is in the strip.
local shownMap = false

--- @author DemiAutomatic
--- @type {boolean}
--- @description Whether a tick thread is running.
local ticking = false

--- @author DemiAutomatic
--- @method format
--- @description A speed written the way commands and the strip show it.
--- @param speed {number}
--- @returns {string}
local function format(speed)
	return ('%g'):format(speed)
end

--- @author DemiAutomatic
--- @method current
--- @description The speed to show: chosen, applied, or the default.
--- @returns {number}
local function current()
	return wanted or applied or DEFAULT_SPEED
end

--- @author DemiAutomatic
--- @method stepped
--- @description One proportional speed step up or down, rounded and bounded.
--- @param speed {number}
--- @param direction {integer}
--- @returns {number}
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

--- @author DemiAutomatic
--- @method travelNative
--- @description One Open77.travel function, or nil when this build lacks it.
--- @param name {string}
--- @returns {function|nil}
local function travelNative(name)
	local travel = Open77.travel
	if type(travel) ~= 'table' or type(travel[name]) ~= 'function' then return nil end
	return travel[name]
end

--- @author DemiAutomatic
--- @method nativeNoclip
--- @description Whether the native still reports noclip on, true without the read.
--- @returns {boolean}
local function nativeNoclip()
	local read = travelNative('isNoclip')
	if read == nil then return true end
	local ok, on = pcall(read)
	return not ok or on == true
end

--- @author DemiAutomatic
--- @method alive
--- @description Whether the character is alive, true when it cannot be read.
--- @returns {boolean}
local function alive()
	local character = Open77.character
	if type(character) ~= 'table' or type(character.state) ~= 'function' then return true end
	local ok, state = pcall(character.state)
	if not ok or type(state) ~= 'table' then return true end
	return state.alive ~= false
end

--- @author DemiAutomatic
--- @method captured
--- @description Whether another surface holds the keyboard right now.
--- @returns {boolean}
local function captured()
	local input = Open77.input
	if type(input) ~= 'table' or type(input.isCaptured) ~= 'function' then return false end
	local ok, answer = pcall(input.isCaptured)
	return ok and answer == true
end

--- @author DemiAutomatic
--- @type {boolean}
--- @description Whether a missing or refusing strip was logged.
local promptsReported = false

--- @author DemiAutomatic
--- @method promptsUp
--- @description Whether the strip is wanted and running, logging its absence once.
--- @returns {boolean}
local function promptsUp()
	if not SHOW_PROMPTS then return false end
	if Client.Running(PROMPTS) then return true end
	if not promptsReported then
		promptsReported = true
		Open77.log.info(PROMPTS .. ' is not running; the travel controls are not drawn')
	end
	return false
end

--- @author DemiAutomatic
--- @method noclipSpec
--- @description The noclip group rows for the registered keys and speed.
--- @returns {table}
local function noclipSpec()
	local rows = {
		{ keys = 'W A S D', label = locale('admin.prompt.move') },
		{ keys = { 'SPACE', 'CTRL' }, label = locale('admin.prompt.upDown') },
	}
	local speedKeys = {}
	if Keys.Effective(KEY_FASTER) then speedKeys[#speedKeys + 1] = { mapping = KEY_FASTER } end
	if Keys.Effective(KEY_SLOWER) then speedKeys[#speedKeys + 1] = { mapping = KEY_SLOWER } end
	if #speedKeys > 0 then
		rows[#rows + 1] = { id = 'speed', keys = speedKeys, label = locale('admin.prompt.speed'),
			value = locale('admin.prompt.speedValue', { speed = format(current()) }) }
	end
	rows[#rows + 1] = { keys = 'SHIFT', hold = true, label = locale('admin.prompt.fast') }
	rows[#rows + 1] = { keys = 'ALT', hold = true, label = locale('admin.prompt.slow') }
	if Keys.Effective(KEY_MENU) then
		rows[#rows + 1] = { keys = { mapping = KEY_MENU }, label = locale('admin.prompt.off') }
	end
	return { title = locale('admin.prompt.noclip'), priority = NOCLIP_PRIORITY, rows = rows }
end

--- @author DemiAutomatic
--- @method mapSpec
--- @description The map travel group telling a double-click travels.
--- @returns {table}
local function mapSpec()
	return { title = locale('admin.prompt.map'), priority = NOCLIP_PRIORITY - 1, rows = {
		{ keys = locale('admin.prompt.doubleClick'), label = locale('admin.prompt.mapTravel') },
	} }
end

--- @author DemiAutomatic
--- @method sync
--- @description Brings the strip groups in line with the modes and speed.
local function sync()
	local body = alive()
	local wantNoclip = noclipOn and body
	local wantMap = mapOn and body
	local signature = wantNoclip and table.concat({ format(current()),
		tostring(Keys.Effective(KEY_FASTER) ~= nil), tostring(Keys.Effective(KEY_SLOWER) ~= nil),
		tostring(Keys.Effective(KEY_MENU) ~= nil) }, '|') or nil
	if signature == shownNoclip and wantMap == shownMap then return end
	if not promptsUp() then
		shownNoclip, shownMap = nil, false
		return
	end
	local noclipChanged, mapChanged = signature ~= shownNoclip, wantMap ~= shownMap
	shownNoclip, shownMap = signature, wantMap
	local spec = signature and noclipSpec() or nil
	CreateThread(function()
		if noclipChanged then
			local _, failure
			if spec == nil then
				_, failure = Client.Call(PROMPTS, 'hide', GROUP_NOCLIP)
			else
				_, failure = Client.Call(PROMPTS, 'show', GROUP_NOCLIP, spec)
			end
			if failure and not promptsReported then
				promptsReported = true
				Open77.log.warn('noclip prompts refused: ' .. failure)
			end
		end
		if mapChanged then
			if wantMap then
				Client.Call(PROMPTS, 'show', GROUP_MAP, mapSpec())
			else
				Client.Call(PROMPTS, 'hide', GROUP_MAP)
			end
		end
	end)
end

--- @author DemiAutomatic
--- @method step
--- @description Chooses the next speed in one direction and redraws.
--- @param direction {integer}
local function step(direction)
	local nextSpeed = stepped(current(), direction)
	lastStepMs = Client.NowMs()
	if nextSpeed == current() then return end
	wanted = nextSpeed
	sync()
end

--- @author DemiAutomatic
--- @method flush
--- @description Sends the chosen speed once the keys have been quiet.
--- @param atMs {integer}
local function flush(atMs)
	if wanted == nil or held ~= 0 or atMs - lastStepMs < SEND_AFTER_MS then return end
	if applied ~= nil and math.abs(wanted - applied) < 0.001 then
		wanted = nil
		return
	end
	if sent ~= nil and math.abs(wanted - sent) < 0.001 and atMs - sentAtMs < ANSWER_WINDOW_MS then
		return
	end
	if Client.Execute({ SPEED_COMMAND, format(wanted) }) then
		sent, sentAtMs = wanted, atMs
	else
		wanted = nil
		sync()
	end
end

--- @author DemiAutomatic
--- @method tick
--- @description Follows the native, repeats a held key, sends and redraws.
local function tick()
	local atMs = Client.NowMs()
	if noclipOn and not nativeNoclip() then
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

--- @author DemiAutomatic
--- @method startTicking
--- @description Starts the tick thread unless one already runs.
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

--- @author DemiAutomatic
--- @method pressed
--- @description A speed key went down while noclip is on.
--- @param direction {integer}
local function pressed(direction)
	if not noclipOn then return end
	held = direction
	nextRepeatMs = Client.NowMs() + REPEAT_DELAY_MS
	step(direction)
	startTicking()
end

--- @author DemiAutomatic
--- @method released
--- @description A speed key went up.
--- @param direction {integer}
local function released(direction)
	if held == direction then held = 0 end
end

--- @author DemiAutomatic
--- @method OpxAdmin.Controls.Noclip
--- @description Noclip was switched by a server command and the native took it.
--- @param on {boolean}
function OpxAdmin.Controls.Noclip(on)
	noclipOn = on == true
	noclipSinceMs, offReads = Client.NowMs(), 0
	if not noclipOn then held, wanted = 0, nil end
	sync()
	if noclipOn then startTicking() end
end

--- @author DemiAutomatic
--- @method OpxAdmin.Controls.MapPick
--- @description Map travel was armed or disarmed by a server command.
--- @param on {boolean}
function OpxAdmin.Controls.MapPick(on)
	mapOn = on == true
	sync()
	if mapOn then startTicking() end
end

--- @author DemiAutomatic
--- @method OpxAdmin.Controls.Speed
--- @description The server applied a noclip speed.
--- @param speed {number}
function OpxAdmin.Controls.Speed(speed)
	applied = speed
	if wanted ~= nil and math.abs(wanted - speed) < 0.001 then wanted = nil end
	sync()
end

--- @author DemiAutomatic
--- @method OpxAdmin.Controls.Answered
--- @description Whether an accepted answer to a keyed speed stays off toasts.
--- @param raw {string}
--- @param accepted {boolean}
--- @returns {boolean}
function OpxAdmin.Controls.Answered(raw, accepted)
	local name = (raw:match('^/?(%S+)') or ''):lower()
	if name ~= SPEED_COMMAND or sent == nil then return false end
	if Client.NowMs() - sentAtMs > ANSWER_WINDOW_MS then return false end
	if accepted then return true end
	sent, wanted = nil, nil
	sync()
	return false
end

--- @author DemiAutomatic
--- @event onClientResourceStart
--- @description Restores groups for a restarted strip, or registers the speed keys.
--- @param name {string}
AddEventHandler('onClientResourceStart', function(name)
	if name == PROMPTS then
		shownNoclip, shownMap = nil, false
		promptsReported = false
		return sync()
	end
	if name ~= Client.RESOURCE then return end
	local keys = type(Config.KEYS) == 'table' and Config.KEYS or {}
	Keys.Register(KEY_FASTER, 'admin.key.speedUp',
		Keys.Setting('KEYS.SPEED_UP', keys.SPEED_UP, 'PAGEUP'),
		function() pressed(1) end, function() released(1) end)
	Keys.Register(KEY_SLOWER, 'admin.key.speedDown',
		Keys.Setting('KEYS.SPEED_DOWN', keys.SPEED_DOWN, 'PAGEDOWN'),
		function() pressed(-1) end, function() released(-1) end)
end)

--- @author DemiAutomatic
--- @event onClientResourceStop
--- @description Forgets what a stopped strip was showing.
--- @param name {string}
AddEventHandler('onClientResourceStop', function(name)
	if name == PROMPTS then
		shownNoclip, shownMap = nil, false
	end
end)

Keys.OnChanged(sync)
