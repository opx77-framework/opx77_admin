---@meta

--- Every destination, configured and added in game, sorted by name, as the menu draws it.
---@return AdminLocation[]
function OpxAdmin.Server.Locations() end

--- One roster row as the server sees the player: no character, which lives in opx77_core's VM.
--- Nil when the player is not connected.
---@param playerId integer
---@param origin table|nil the operator's position, for the distance (same bucket only)
---@return AdminRosterRow|nil
function OpxAdmin.Server.RosterRow(playerId, origin) end

--- Every connected player id, sorted.
---@return integer[]
function OpxAdmin.Server.PlayerIds() end
