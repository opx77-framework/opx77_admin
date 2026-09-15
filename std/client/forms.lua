---@meta

--- The forms opx77_input draws for values a menu row cannot hold.
OpxAdmin.Forms = {}

--- Takes the menu down and puts one form up; its answer becomes a command line.
---@param kind string a key of the form table
---@param arg any the row's argument: a player id, or a picker row
---@return boolean asked
function OpxAdmin.Forms.Open(kind, arg) end

--- Whether a form of this resource is up.
---@return boolean
function OpxAdmin.Forms.IsOpen() end

--- Takes the open form down, if there is one.
function OpxAdmin.Forms.Close() end
