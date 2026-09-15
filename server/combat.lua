--- @author DemiAutomatic
--- @file server/combat.lua
--- @description Global player-versus-player damage: on at start from COMBAT.PVP, switched by staff.

local Config = OPX_ADMIN_CONFIG
local Server = OpxAdmin.Server
local Text = OpxAdmin.Text

local answer, refuse, audit = Server.Answer, Server.Refuse, Server.Audit

--- @author DemiAutomatic
--- @type {string}
--- @description The command that switches PvP, and the ACL name that grants it.
local COMMAND = 'opx77.admin.world.pvp'

--- @author DemiAutomatic
--- @type {boolean}
--- @description Whether the host last accepted PvP on.
local pvp = false

--- @author DemiAutomatic
--- @method apply
--- @description Switches global PvP on the host and tells every client the result.
--- @param on {boolean}
--- @returns {boolean, string|nil}
local function apply(on)
	local combat = Open77.combat
	if type(combat) ~= 'table' or type(combat.setFriendlyFire) ~= 'function' then
		return false, 'combat_unavailable'
	end
	local called, ok, reason = pcall(combat.setFriendlyFire, on == true)
	if not called then return false, tostring(ok) end
	if ok ~= true then return false, tostring(reason or 'refused') end
	pvp = on == true
	TriggerClientEvent('opx77_admin:pvpState', -1, pvp)
	return true
end

--- @author DemiAutomatic
--- @command /opx77.admin.world.pvp
--- @description Switches damage between players for everyone, toggling when no word is typed.
Server.Command(COMMAND, {
	help = 'admin.help.pvp',
	params = { { name = 'on|off', help = 'admin.help.toggle', optional = true } },
	handler = function(source, args, raw)
		local wanted, invalid = Text.Switch(args[1])
		if invalid then return refuse(source, raw, 'bad_switch') end
		if wanted == nil then wanted = not pvp end
		local ok, reason = apply(wanted)
		if not ok then
			audit(source, 'admin.world.pvp', false, nil, tostring(reason))
			return refuse(source, raw, 'refused', { reason = reason })
		end
		audit(source, 'admin.world.pvp', true, nil, wanted and 'on' or 'off')
		answer(source, raw, true, wanted and 'admin.done.pvpOn' or 'admin.done.pvpOff')
	end,
})

--- @author DemiAutomatic
--- @event opx77_admin:pvpRequest
--- @description Tells one client whether PvP is on, for its menu row.
RegisterNetEvent('opx77_admin:pvpRequest', function()
	local playerId = tonumber(source) or 0
	if playerId <= 0 or Server.Cooled(playerId, 'pvpRequest', 1000) then return end
	TriggerClientEvent('opx77_admin:pvpState', playerId, pvp)
end)

CreateThread(function()
	local settings = type(Config.COMBAT) == 'table' and Config.COMBAT or {}
	local wanted = settings.PVP ~= false
	local ok, reason = apply(wanted)
	if not ok then
		Open77.log.error(('PvP could not be switched %s at start: %s'):format(wanted and 'on' or 'off', tostring(reason)))
		return
	end
	Open77.log.info(('PvP %s at start (COMBAT.PVP)'):format(wanted and 'on' or 'off'))
end)
