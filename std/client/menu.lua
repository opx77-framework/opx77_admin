---@meta

--- The staff menu: a stack of screens, each its own opx77_menu `open`.
OpxAdmin.Menu = {}

--- Writes the line under the list (its first line, cut to 116 bytes without splitting a
--- character), or keeps it for the next screen when none is up.
---@param text string
---@param ok boolean
function OpxAdmin.Menu.Status(text, ok) end

--- Runs a command line from a row or a form, and asks for a list again 1.2 s later.
---@param tokens table
---@param refresh string|nil roster | locations | items | bag
function OpxAdmin.Menu.Run(tokens, refresh) end

--- Pushes the confirmation screen, Cancel first, for a command line.
---@param tokens table
---@param key string catalogue key of the question
function OpxAdmin.Menu.Confirm(tokens, key) end

--- Takes the menu down for a form, keeping the stack.
function OpxAdmin.Menu.Suspend() end

--- Brings the menu back after a form, with a line under it when given.
---@param text string|nil
---@param ok boolean|nil
function OpxAdmin.Menu.Resume(text, ok) end

--- Takes the menu and any form down, and empties the stack.
function OpxAdmin.Menu.Close() end

--- Redraws the open screen in place, for text that changed under it.
function OpxAdmin.Menu.Refresh() end

--- Whether the menu or one of its forms is up.
---@return boolean
function OpxAdmin.Menu.IsOpen() end

--- The name of the screen at the top of the stack, nil when closed.
---@return string|nil
function OpxAdmin.Menu.Screen() end
