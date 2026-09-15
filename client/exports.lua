--- The public export surface. Every call answers a table carrying `ok` and never raises.
--- Nothing here authorises anything: `open` sends the opener command, which the host resolves
--- against the caller's player's ACL like a typed one.

local Client = OpxAdmin.Client
local Menu = OpxAdmin.Menu

--- Who is calling, asked of the host: a caller cannot claim to be another resource.
---@return string|nil
local function caller()
	local owner = GetInvokingResource()
	if type(owner) ~= 'string' or owner == '' or #owner > 64 or
		owner:match('^[%w_%-%.]+$') == nil then
		return nil
	end
	return owner
end

--- Ask for the staff menu. `ok = true` means asked: a player the ACL refuses gets the host's
--- refusal, which opx77_chat toasts, and no menu.
---@return AdminResponse
exports('open', function()
	if caller() == nil then return { ok = false, error = 'export_call_required' } end
	if not Client.Running('opx77_menu') then return { ok = false, error = 'menu_not_running' } end
	if Menu.IsOpen() then return { ok = true, open = true } end
	if not Client.Execute({ 'opx77.admin' }) then return { ok = false, error = 'not_sent' } end
	return { ok = true, queued = true }
end)

--- Take the staff menu, and any form it put up, down.
---@return AdminResponse
exports('close', function()
	if caller() == nil then return { ok = false, error = 'export_call_required' } end
	Menu.Close()
	return { ok = true }
end)

--- Whether the staff menu is up, and which screen.
---@return AdminState
exports('state', function()
	if caller() == nil then return { ok = false, error = 'export_call_required' } end
	return { ok = true, open = Menu.IsOpen(), screen = Menu.Screen() }
end)
