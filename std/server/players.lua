---@meta

--- Switches a player's noclip and remembers which command's grant keeps it on; sends the default
--- speed the first time unless the player chose one.
---@type fun(playerId: integer, on: boolean, grant: string|nil)
OpxAdmin.Server.Noclip = nil
