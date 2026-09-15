--- @author DemiAutomatic
--- @file shared/locale.lua
--- @description Locale catalogues and the global locale lookup shorthand.

OpxAdmin = OpxAdmin or {}

--- @author DemiAutomatic
--- @type {table<string, table<string, string>>}
--- @description Every registered catalogue, by language code.
local catalogs = {}

--- @author DemiAutomatic
--- @type {string}
--- @description The language code player-facing text is read from.
local active = 'en'

--- @author DemiAutomatic
--- @type {string}
--- @description The catalogue a missing translation falls back to.
local FALLBACK = 'en'

--- @author DemiAutomatic
--- @type {table}
--- @description Catalogue registration, selection and lookup.
OpxAdmin.Locale = {}
local Locale = OpxAdmin.Locale

--- @author DemiAutomatic
--- @method interpolate
--- @description Fills named placeholders, leaving unknown ones as written.
--- @param text {string}
--- @param params {table<string, string|number>|nil}
--- @returns {string}
local function interpolate(text, params)
	if not params then return text end
	return (text:gsub('{(%w+)}', function(name)
		local value = params[name]
		return value ~= nil and tostring(value) or ('{' .. name .. '}')
	end))
end

--- @author DemiAutomatic
--- @method OpxAdmin.Locale.register
--- @description Merges strings into the catalogue for one language code.
--- @param code {string}
--- @param strings {table<string, string>}
function OpxAdmin.Locale.register(code, strings)
	local catalog = catalogs[code]
	if not catalog then
		catalog = {}
		catalogs[code] = catalog
	end
	for key, text in pairs(strings) do catalog[key] = text end
end

--- @author DemiAutomatic
--- @method OpxAdmin.Locale.Set
--- @description Selects the catalogue, accepting codes registered later.
--- @param code {string}
--- @returns {boolean}
function OpxAdmin.Locale.Set(code)
	if type(code) ~= 'string' or code == '' then return false end
	active = code
	return true
end

--- @author DemiAutomatic
--- @method OpxAdmin.Locale.Current
--- @description Answers the selected language code.
--- @returns {string}
function OpxAdmin.Locale.Current()
	return active
end

--- @author DemiAutomatic
--- @method OpxAdmin.Locale.Exists
--- @description Whether the active or fallback catalogue carries a key.
--- @param key {string}
--- @returns {boolean}
function OpxAdmin.Locale.Exists(key)
	return (catalogs[active] and catalogs[active][key] ~= nil)
		or (catalogs[FALLBACK] and catalogs[FALLBACK][key] ~= nil)
end

--- @author DemiAutomatic
--- @method OpxAdmin.Locale.Get
--- @description Renders a key, falling back to English, then the key.
--- @param key {string}
--- @param params {table<string, string|number>|nil}
--- @returns {string}
function OpxAdmin.Locale.Get(key, params)
	local catalog = catalogs[active]
	local text = (catalog and catalog[key])
		or (catalogs[FALLBACK] and catalogs[FALLBACK][key])
		or key
	return interpolate(text, params)
end

--- @author DemiAutomatic
--- @method OpxAdmin.Locale.English
--- @description Renders a key in English, for the server log.
--- @param key {string}
--- @param params {table<string, string|number>|nil}
--- @returns {string}
function OpxAdmin.Locale.English(key, params)
	local catalog = catalogs[FALLBACK]
	return interpolate((catalog and catalog[key]) or key, params)
end

--- @author DemiAutomatic
--- @method OpxAdmin.Locale.Keys
--- @description Answers every key of one catalogue, for the boot parity check.
--- @param code {string}
--- @returns {table<string, true>}
function OpxAdmin.Locale.Keys(code)
	local keys = {}
	for key in pairs(catalogs[code] or {}) do keys[key] = true end
	return keys
end

--- @author DemiAutomatic
--- @type {fun(key: string, params: table|nil): string}
--- @description The global lookup shorthand every file below the catalogues uses.
locale = Locale.Get

Locale.Set(OPX_ADMIN_CONFIG and OPX_ADMIN_CONFIG.LOCALE)
