--- @author DemiAutomatic
--- @file client/exports.lua
--- @description The three client exports, each answering a table with ok.

local Client = OpxAdmin.Client
local Menu = OpxAdmin.Menu

--- @author DemiAutomatic
--- @method caller
--- @description Reads the invoking resource name from the host.
--- @returns {string|nil}
local function caller()
	local owner = GetInvokingResource()
	if type(owner) ~= 'string' or owner == '' or #owner > 64 or
		owner:match('^[%w_%-%.]+$') == nil then
		return nil
	end
	return owner
end

--- @author DemiAutomatic
--- @export open
--- @description Sends the opener command; ok means asked, not allowed.
--- @returns {AdminResponse}
exports('open', function()
	if caller() == nil then return { ok = false, error = 'export_call_required' } end
	if not Client.Running('opx77_menu') then return { ok = false, error = 'menu_not_running' } end
	if Menu.IsOpen() then return { ok = true, open = true } end
	if not Client.Execute({ 'opx77.admin' }) then return { ok = false, error = 'not_sent' } end
	return { ok = true, queued = true }
end)

--- @author DemiAutomatic
--- @export close
--- @description Takes the staff menu and any form it opened down.
--- @returns {AdminResponse}
exports('close', function()
	if caller() == nil then return { ok = false, error = 'export_call_required' } end
	Menu.Close()
	return { ok = true }
end)

--- @author DemiAutomatic
--- @export state
--- @description Whether the staff menu is up, and which screen.
--- @returns {AdminState}
exports('state', function()
	if caller() == nil then return { ok = false, error = 'export_call_required' } end
	return { ok = true, open = Menu.IsOpen(), screen = Menu.Screen() }
end)
