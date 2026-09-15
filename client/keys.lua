--- @author DemiAutomatic
--- @file client/keys.lua
--- @description Rebindable key mappings declared to the host and their rebinds.

OpxAdmin = OpxAdmin or {}

--- @author DemiAutomatic
--- @type {table}
--- @description The key mapping helpers the other client files call.
OpxAdmin.Keys = {}
local Keys = OpxAdmin.Keys

--- @author DemiAutomatic
--- @type {table<string, string>}
--- @description Mapping id to the key the host answered at registration.
local registered = {}

--- @author DemiAutomatic
--- @type {fun()[]}
--- @description Functions run whenever a player rebinds or resets a mapping.
local listeners = {}

--- @author DemiAutomatic
--- @method OpxAdmin.Keys.Setting
--- @description A configured key name, false for none, else the default.
--- @param path {string} How the warning names it, e.g. KEYS.MENU.
--- @param value {any}
--- @param default {string}
--- @returns {string|false}
function OpxAdmin.Keys.Setting(path, value, default)
	if value == false then return false end
	if value == nil then return default end
	if type(value) == 'string' and #value > 0 and #value <= 32 and not value:find('[%s%c]') then
		return value
	end
	Open77.log.warn(('config: %s must be a key name or false; using %q'):format(path, default))
	return default
end

--- @author DemiAutomatic
--- @method OpxAdmin.Keys.Captured
--- @description Whether another surface holds the keyboard right now.
--- @returns {boolean}
function OpxAdmin.Keys.Captured()
	local input = Open77.input
	if type(input) ~= 'table' or type(input.isCaptured) ~= 'function' then return false end
	local read, answer = pcall(input.isCaptured)
	return read and answer == true
end

--- @author DemiAutomatic
--- @method OpxAdmin.Keys.Register
--- @description Declares one key mapping, logging a refusal once.
--- @param id {string} Stable mapping id a rebind is stored under.
--- @param nameKey {string} Catalogue key of the pause menu name.
--- @param key {string|false}
--- @param onPressed {fun()}
--- @param onReleased {fun()|nil} Makes it a hold mapping.
--- @returns {boolean}
function OpxAdmin.Keys.Register(id, nameKey, key, onPressed, onReleased)
	if key == false then return false end
	if type(RegisterKeyMapping) ~= 'function' then
		Open77.log.warn(('key mapping %s not registered: this client build has no ' ..
			'RegisterKeyMapping'):format(id))
		return false
	end
	local function pressed()
		if Keys.Captured() then return end
		local ran, failure = pcall(onPressed)
		if not ran then Open77.log.error(('key %s: %s'):format(id, tostring(failure))) end
	end
	local called, ok, answer
	if onReleased == nil then
		called, ok, answer = pcall(RegisterKeyMapping, id, locale(nameKey), key, pressed)
	else
		local function released()
			local ran, failure = pcall(onReleased)
			if not ran then Open77.log.error(('key %s: %s'):format(id, tostring(failure))) end
		end
		called, ok, answer = pcall(RegisterKeyMapping, id, locale(nameKey), key, pressed, released)
	end
	local effective = type(ok) == 'string' and ok ~= '' and ok or
		(ok == true and type(answer) == 'string' and answer ~= '' and answer) or nil
	if not called or (ok ~= true and effective == nil) then
		Open77.log.warn(('key mapping %s (%s) not registered: %s'):format(id, key,
			tostring(called and answer or ok)))
		return false
	end
	registered[id] = effective or key
	return true
end

--- @author DemiAutomatic
--- @method OpxAdmin.Keys.Effective
--- @description The key a mapping answers to now, rebinds included.
--- @param id {string}
--- @returns {string|nil}
function OpxAdmin.Keys.Effective(id)
	local known = registered[id]
	if known == nil then return nil end
	local input = Open77.input
	if type(input) == 'table' and type(input.keyFor) == 'function' then
		local read, key = pcall(input.keyFor, id)
		if read and type(key) == 'string' and key ~= '' then return key end
	end
	return known
end

--- @author DemiAutomatic
--- @method OpxAdmin.Keys.OnChanged
--- @description Runs a listener whenever a player rebinds or resets a mapping.
--- @param listener {fun()}
function OpxAdmin.Keys.OnChanged(listener)
	listeners[#listeners + 1] = listener
end

--- @author DemiAutomatic
--- @event open77:keybinds:changed
--- @description Runs every rebind listener, each under its own pcall.
AddEventHandler('open77:keybinds:changed', function()
	for index = 1, #listeners do
		local ran, failure = pcall(listeners[index])
		if not ran then Open77.log.error('keybinds changed: ' .. tostring(failure)) end
	end
end)
