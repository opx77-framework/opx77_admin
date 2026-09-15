--- @author DemiAutomatic
--- @file shared/text.lua
--- @description Coercions and text helpers for typed command arguments.

OpxAdmin = OpxAdmin or {}

--- @author DemiAutomatic
--- @type {table}
--- @description Number and text coercions both halves share.
OpxAdmin.Text = {}
local Text = OpxAdmin.Text

--- @author DemiAutomatic
--- @type {number}
--- @description Widest magnitude accepted, past which integers lose precision.
local MAGNITUDE = 2 ^ 53

--- @author DemiAutomatic
--- @method OpxAdmin.Text.Finite
--- @description Answers a finite number within MAGNITUDE, or nil.
--- @param value {any}
--- @returns {number|nil}
function OpxAdmin.Text.Finite(value)
	value = tonumber(value)
	if value == nil or value ~= value or value > MAGNITUDE or value < -MAGNITUDE then return nil end
	return value
end

--- @author DemiAutomatic
--- @method OpxAdmin.Text.Integer
--- @description Answers a whole number, or nil.
--- @param value {any}
--- @returns {integer|nil}
function OpxAdmin.Text.Integer(value)
	local parsed = Text.Finite(value)
	if parsed == nil or parsed % 1 ~= 0 then return nil end
	return math.floor(parsed)
end

--- @author DemiAutomatic
--- @method span
--- @description Byte length of the first characters, bounded at four bytes each.
--- @param text {string}
--- @param maximum {integer} Characters to keep.
--- @returns {integer}
local function span(text, maximum)
	local size = math.min(#text, maximum * 4)
	local characters = 0
	for index = 1, size do
		local byte = text:byte(index)
		if byte < 0x80 or byte > 0xBF then
			if characters >= maximum then return index - 1 end
			characters = characters + 1
		end
	end
	return size
end

--- @author DemiAutomatic
--- @method OpxAdmin.Text.Clean
--- @description Display text without control characters, trimmed and cut to length.
--- @param value {any}
--- @param maximum {integer} Characters to keep.
--- @returns {string|nil}
function OpxAdmin.Text.Clean(value, maximum)
	if type(value) == 'number' then value = tostring(value) end
	if type(value) ~= 'string' then return nil end
	value = value:gsub('%c', ' '):gsub('^%s+', ''):gsub('%s+$', '')
	if value == '' then return nil end
	if #value > maximum then value = value:sub(1, span(value, maximum)) end
	return value
end

--- @author DemiAutomatic
--- @method OpxAdmin.Text.Bytes
--- @description Cuts text to a byte limit without splitting a character.
--- @param text {string}
--- @param limit {integer} Bytes to keep.
--- @returns {string}
function OpxAdmin.Text.Bytes(text, limit)
	if #text <= limit then return text end
	local cut = limit
	while cut > 0 do
		local following = text:byte(cut + 1)
		if following == nil or following < 0x80 or following > 0xBF then break end
		cut = cut - 1
	end
	return text:sub(1, cut)
end

--- @author DemiAutomatic
--- @method OpxAdmin.Text.Rest
--- @description Joins the typed words from one position on into a sentence.
--- @param args {table}
--- @param first {integer}
--- @returns {string|nil}
function OpxAdmin.Text.Rest(args, first)
	local words = {}
	local count = Text.Integer(args.n) or #args
	for index = first, count do
		local word = args[index]
		if word ~= nil then words[#words + 1] = tostring(word) end
	end
	if #words == 0 then return nil end
	return table.concat(words, ' ')
end

--- @author DemiAutomatic
--- @method OpxAdmin.Text.Switch
--- @description Reads on or off and their synonyms; nil when absent.
--- @param value {any}
--- @returns {boolean|nil, string|nil}
function OpxAdmin.Text.Switch(value)
	if value == nil then return nil end
	local word = tostring(value):lower()
	if word == 'on' or word == 'true' or word == '1' or word == 'yes' then return true end
	if word == 'off' or word == 'false' or word == '0' or word == 'no' then return false end
	return nil, 'invalid'
end

--- @author DemiAutomatic
--- @method OpxAdmin.Text.Slug
--- @description Answers a lower-cased name of letters, digits, underscores and hyphens.
--- @param value {any}
--- @returns {string|nil}
function OpxAdmin.Text.Slug(value)
	if type(value) ~= 'string' then return nil end
	local lowered = value:lower()
	if #lowered > 32 or lowered:match('^[%w_%-]+$') == nil then return nil end
	return lowered
end
