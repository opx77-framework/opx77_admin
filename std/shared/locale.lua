---@meta

--- Player-facing text catalogues. Log lines and console answers stay English.
OpxAdmin.Locale = {}

--- Merges `strings` into the catalogue for `code`. Operators' own locale files call it: its name
--- stays lowercase.
---@param code string
---@param strings table<string, string>
function OpxAdmin.Locale.register(code, strings) end

--- Selects the catalogue player-facing text is read from. An unknown code is accepted: the
--- catalogues register after the selection, and a missing key falls back to `en`.
---@param code string
---@return boolean applied
function OpxAdmin.Locale.Set(code) end

--- The selected language code.
---@return string
function OpxAdmin.Locale.Current() end

--- Whether the active catalogue or the `en` fallback carries `key`.
---@param key string
---@return boolean
function OpxAdmin.Locale.Exists(key) end

--- Renders `key` with `{name}` placeholders filled. Never nil: falls back to `en`, then to the key.
---@param key string
---@param params table<string, string|number>|nil
---@return string
function OpxAdmin.Locale.Get(key, params) end

--- The same rendering in English, for an answer that goes to the server log.
---@param key string
---@param params table<string, string|number>|nil
---@return string
function OpxAdmin.Locale.English(key, params) end

--- Every key of one catalogue, for the parity check at boot.
---@param code string
---@return table<string, true>
function OpxAdmin.Locale.Keys(code) end

--- The global shorthand for `OpxAdmin.Locale.Get`.
---@type fun(key: string, params?: table<string, string|number>): string
locale = OpxAdmin.Locale.Get
