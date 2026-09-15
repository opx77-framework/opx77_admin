---@meta

--- Number and text coercions for what staff type. Every number goes through `Finite` and every
--- sentence through `Clean`.
OpxAdmin.Text = {}

--- A real number, or nil. NaN, both infinities and anything past 2^53 are nil.
---@param value any
---@return number|nil
function OpxAdmin.Text.Finite(value) end

--- A whole number, or nil.
---@param value any
---@return integer|nil
function OpxAdmin.Text.Integer(value) end

--- Display text: control characters become spaces, the ends are trimmed, and the rest is cut to
--- `maximum` characters. Nil for anything that is neither a string nor a number, or is empty.
---@param value any
---@param maximum integer characters
---@return string|nil
function OpxAdmin.Text.Clean(value, maximum) end

--- Cut to at most `limit` bytes without splitting a UTF-8 character.
---@param text string
---@param limit integer bytes
---@return string
function OpxAdmin.Text.Bytes(text, limit) end

--- The typed words from position `first` on, joined with single spaces. Reads `args.n`.
---@param args table
---@param first integer
---@return string|nil
function OpxAdmin.Text.Rest(args, first) end

--- `on`/`true`/`1`/`yes` and `off`/`false`/`0`/`no`. Nil for an absent value, nil plus
--- `"invalid"` for anything else.
---@param value any
---@return boolean|nil
---@return string|nil
function OpxAdmin.Text.Switch(value) end

--- A lower-cased name of 1..32 letters, digits, `_` and `-`, or nil.
---@param value any
---@return string|nil
function OpxAdmin.Text.Slug(value) end
