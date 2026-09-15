--- @author DemiAutomatic
--- @file client/combat.lua
--- @description Global PvP as the server last announced it, for the World switch.

OpxAdmin = OpxAdmin or {}

OpxAdmin.Combat = {}

--- @author DemiAutomatic
--- @type {boolean}
--- @description Whether the server last said PvP is on.
local pvp = false

--- @author DemiAutomatic
--- @method OpxAdmin.Combat.IsPvp
--- @description Answers whether the server last said damage between players is on.
--- @returns {boolean}
function OpxAdmin.Combat.IsPvp()
	return pvp
end

--- @author DemiAutomatic
--- @event opx77_admin:pvpState
--- @description Adopts the PvP state the server announced and redraws an open menu.
--- @param on {boolean}
RegisterNetEvent('opx77_admin:pvpState', function(on)
	pvp = on == true
	if OpxAdmin.Menu and type(OpxAdmin.Menu.Refresh) == 'function' then OpxAdmin.Menu.Refresh() end
end)

--- @author DemiAutomatic
--- @event onClientResourceStart
--- @description Asks the server for the PvP state once this resource runs.
--- @param name {string}
AddEventHandler('onClientResourceStart', function(name)
	if name ~= GetCurrentResourceName() then return end
	TriggerServerEvent('opx77_admin:pvpRequest')
end)
