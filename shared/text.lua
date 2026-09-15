--- Coercions and text helpers for both halves. Everything a command reads arrives as a string
--- typed by a person, so every number goes through `finite` and every sentence through `clean`.

OpxAdmin = OpxAdmin or {}

OpxAdmin.Text = {}
local Text = OpxAdmin.Text

--- The widest magnitude accepted anywhere: past it `%d` has no integer form.
local MAGNITUDE = 2 ^ 53

--- A real number, or nil. NaN and both infinities are nil, and so is anything past MAGNITUDE.
---@param value any
---@return number|nil
function OpxAdmin.Text.Finite(value)
	value = tonumber(value)
	-- `value ~= value` is the NaN test: NaN is the one value unequal to itself
	if value == nil or value ~= value or value > MAGNITUDE or value < -MAGNITUDE then return nil end
	return value
end

--- A whole number, or nil.
---@param value any
---@return integer|nil
function OpxAdmin.Text.Integer(value)
	local parsed = Text.Finite(value)
	if parsed == nil or parsed % 1 ~= 0 then return nil end
	return math.floor(parsed)
end

--- The byte length of the first `maximum` characters. Bounded in bytes too, at four per
--- character, so a run of continuation bytes cannot make the scan unbounded.
---@param text string
---@param maximum integer
---@return integer
local function span(text, maximum)
	local size = math.min(#text, maximum * 4)
	local characters = 0
	for index = 1, size do
		local byte = text:byte(index)
		-- 0x80..0xBF continues a character, so it does not start one
		if byte < 0x80 or byte > 0xBF then
			if characters >= maximum then return index - 1 end
			characters = characters + 1
		end
	end
	return size
end

--- Display text: control characters become spaces, the ends are trimmed, and the rest is cut to
--- `maximum` characters. Nil for anything that is neither a string nor a number, or is empty.
---@param value any
---@param maximum integer
---@return string|nil
function OpxAdmin.Text.Clean(value, maximum)
	if type(value) == 'number' then value = tostring(value) end
	if type(value) ~= 'string' then return nil end
	-- a newline in a name or a reason would forge a whole log line
	value = value:gsub('%c', ' '):gsub('^%s+', ''):gsub('%s+$', '')
	if value == '' then return nil end
	if #value > maximum then value = value:sub(1, span(value, maximum)) end
	return value
end

--- Cut to at most `limit` BYTES without splitting a character: the platform measures a kick
--- reason in bytes and refuses the whole call past its limit.
---@param text string
---@param limit integer
---@return string
function OpxAdmin.Text.Bytes(text, limit)
	if #text <= limit then return text end
	local cut = limit
	-- back off while the byte after the cut continues the character before it
	while cut > 0 do
		local following = text:byte(cut + 1)
		if following == nil or following < 0x80 or following > 0xBF then break end
		cut = cut - 1
	end
	return text:sub(1, cut)
end

--- The typed words from position `first` on, joined back into one sentence.
---@param args table
---@param first integer
---@return string|nil
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

--- `on` / `off` and their synonyms. Nil for an absent value, false plus "invalid" for garbage.
---@param value any
---@return boolean|nil, string|nil
function OpxAdmin.Text.Switch(value)
	if value == nil then return nil end
	local word = tostring(value):lower()
	if word == 'on' or word == 'true' or word == '1' or word == 'yes' then return true end
	if word == 'off' or word == 'false' or word == '0' or word == 'no' then return false end
	return nil, 'invalid'
end

--- A name staff type: letters, digits, `_` and `-`, lower-cased, 1..32 of them.
---@param value any
---@return string|nil
function OpxAdmin.Text.Slug(value)
	if type(value) ~= 'string' then return nil end
	local lowered = value:lower()
	if #lowered > 32 or lowered:match('^[%w_%-]+$') == nil then return nil end
	return lowered
end
