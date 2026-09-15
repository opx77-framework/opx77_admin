---@meta

--- The travel controls: noclip speed keys and opx77_prompts' strip, told by client/main.lua.
OpxAdmin.Controls = {}

--- Noclip was switched on or off by a server command, and the native took it.
---@param on boolean
function OpxAdmin.Controls.Noclip(on) end

--- Map travel was armed or disarmed by a server command.
---@param on boolean
function OpxAdmin.Controls.MapPick(on) end

--- The server applied a noclip speed.
---@param speed number
function OpxAdmin.Controls.Speed(speed) end

--- A command answer. True when it accepts a speed the keys sent: the strip already shows it, so
--- it stays off a toast. A refusal puts the read-out back and answers false.
---@param raw string
---@param accepted boolean
---@return boolean quiet
function OpxAdmin.Controls.Answered(raw, accepted) end
