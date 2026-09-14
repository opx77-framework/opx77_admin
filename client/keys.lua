--- The rebindable keys. Each one is declared to the host with RegisterKeyMapping, so the pause
--- menu's keybinds tab lists it under the localised name given here and a player rebinds it
--- there. Nothing here reads a key or decides anything: a key does what its command does.

OpxAdmin = OpxAdmin or {}

local Keys = {}
OpxAdmin.Keys = Keys

--- id -> the key the host answered at registration. Absent: switched off, or refused.
---@type table<string, string>
local registered = {}

---@type fun()[]
local listeners = {}

--- A configured key: a key name, or false for none. Anything else is the default, said once.
---@param path string  how the warning names it, e.g. "KEYS.MENU"
---@param value any
---@param default string
---@return string|false
function Keys.setting(path, value, default)
  if value == false then return false end
  if value == nil then return default end
  if type(value) == "string" and #value > 0 and #value <= 32 and not value:find("[%s%c]") then
    return value
  end
  Open77.log.warn(("config: %s must be a key name or false; using %q"):format(path, default))
  return default
end

--- Whether another surface holds the keyboard: chat's composer, an opx77_input form, the pause
--- menu. A key typed into one of them must not open anything behind it.
---@return boolean
local function captured()
  local input = type(Open77) == "table" and Open77.input or nil
  if type(input) ~= "table" or type(input.isCaptured) ~= "function" then return false end
  local read, answer = pcall(input.isCaptured)
  return read and answer == true
end

--- Declare one mapping. A refusal is one log line; the command it stands for still works.
---@param id string       namespaced by this resource, and stable: a rebind is stored under it
---@param nameKey string  catalogue key of the name the pause menu lists
---@param key string|false
---@param onPressed fun()
---@param onReleased? fun()  makes it a hold mapping: the host calls this on key-up
---@return boolean registered
function Keys.register(id, nameKey, key, onPressed, onReleased)
  if key == false then return false end
  if type(RegisterKeyMapping) ~= "function" then
    Open77.log.warn(("key mapping %s not registered: this client build has no " ..
      "RegisterKeyMapping"):format(id))
    return false
  end
  local function pressed()
    if captured() then return end
    local ran, failure = pcall(onPressed)
    if not ran then Open77.log.error(("key %s: %s"):format(id, tostring(failure))) end
  end
  local called, ok, answer
  if onReleased == nil then
    called, ok, answer = pcall(RegisterKeyMapping, id, locale(nameKey), key, pressed)
  else
    -- a release is never swallowed: a key let go behind a surface must not stay held here.
    -- Only passed when there is one: a fifth argument is what makes a mapping a hold mapping.
    local function released()
      local ran, failure = pcall(onReleased)
      if not ran then Open77.log.error(("key %s: %s"):format(id, tostring(failure))) end
    end
    called, ok, answer = pcall(RegisterKeyMapping, id, locale(nameKey), key, pressed, released)
  end
  if not called or ok ~= true then
    Open77.log.warn(("key mapping %s (%s) not registered: %s"):format(id, key,
      tostring(called and answer or ok)))
    return false
  end
  registered[id] = type(answer) == "string" and answer ~= "" and answer or key
  return true
end

--- The key a mapping answers to now, a player's rebind included. Nil when it is off or was
--- refused, so a hint that has no key to name says nothing.
---@param id string
---@return string|nil
function Keys.effective(id)
  local known = registered[id]
  if known == nil then return nil end
  local input = Open77.input
  if type(input) == "table" and type(input.keyFor) == "function" then
    local read, key = pcall(input.keyFor, id)
    if read and type(key) == "string" and key ~= "" then return key end
  end
  return known
end

--- Run `listener` whenever a player rebinds or resets a mapping, so a hint on screen follows.
---@param listener fun()
function Keys.onChanged(listener)
  listeners[#listeners + 1] = listener
end

AddEventHandler("open77:keybinds:changed", function()
  for index = 1, #listeners do
    local ran, failure = pcall(listeners[index])
    if not ran then Open77.log.error("keybinds changed: " .. tostring(failure)) end
  end
end)
