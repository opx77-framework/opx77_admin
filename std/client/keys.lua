---@meta

--- The key mapping helpers: RegisterKeyMapping, the effective key, rebind listeners.
OpxAdmin.Keys = {}

--- A configured key: a key name, false for none; anything else is the default, with a warning.
---@param path string how the warning names it, e.g. "KEYS.MENU"
---@param value any
---@param default string
---@return string|false
function OpxAdmin.Keys.Setting(path, value, default) end

--- Declares one mapping. A press while another surface holds the keyboard does nothing; a
--- release is never swallowed. A refusal is one log line.
---@param id string stable mapping id a rebind is stored under
---@param nameKey string catalogue key of the name the pause menu lists
---@param key string|false
---@param onPressed fun()
---@param onReleased fun()|nil makes it a hold mapping
---@return boolean registered
function OpxAdmin.Keys.Register(id, nameKey, key, onPressed, onReleased) end

--- The key a mapping answers to now, a player's rebind included; nil when off or refused.
---@param id string
---@return string|nil
function OpxAdmin.Keys.Effective(id) end

--- Runs `listener` whenever a player rebinds or resets a mapping.
---@param listener fun()
function OpxAdmin.Keys.OnChanged(listener) end
