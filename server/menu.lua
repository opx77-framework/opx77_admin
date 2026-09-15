--- @author DemiAutomatic
--- @file server/menu.lua
--- @description The staff menu server half: the opener command and list refreshes.

local Config = OPX_ADMIN_CONFIG
local Server = OpxAdmin.Server
local Inventory = OpxAdmin.Inventory

--- @author DemiAutomatic
--- @type {string}
--- @description The opener command, whose grant the refresh event requires.
local OPENER = 'opx77.admin'

--- @author DemiAutomatic
--- @type {integer}
--- @description Rows per roster, destination, catalogue or bag event.
local ROSTER_CHUNK = 20

--- @author DemiAutomatic
--- @method menuCommands
--- @description Lists every command name the menu may issue, linked ones included.
--- @returns {string[]}
local function menuCommands()
	local names = {}
	for _, command in ipairs(Server.Commands()) do names[#names + 1] = command.name end
	for _, name in pairs(type(Config.LINKS) == 'table' and Config.LINKS or {}) do
		if type(name) == 'string' and name ~= '' then names[#names + 1] = name end
	end
	return names
end

--- @author DemiAutomatic
--- @method accessOf
--- @description Answers which menu commands this operator's ACL grants, a drawing hint.
--- @param playerId {integer}
--- @returns {table<string, boolean>, boolean}
local function accessOf(playerId)
	local access, known = {}, true
	for _, name in ipairs(menuCommands()) do
		local allowed = Server.Permitted(playerId, name)
		if allowed == nil then known = false end
		if allowed == true then access[name] = true end
	end
	return access, known
end

--- @author DemiAutomatic
--- @method pushChunks
--- @description Sends rows to one client in chunks under the event size limit.
--- @param playerId {integer}
--- @param event {string}
--- @param rows {table[]}
--- @param extra {table|nil} Copied into every chunk.
local function pushChunks(playerId, event, rows, extra)
	local offset = 0
	repeat
		local chunk = {}
		for index = offset + 1, math.min(offset + ROSTER_CHUNK, #rows) do
			chunk[#chunk + 1] = rows[index]
		end
		local payload = { rows = chunk, offset = offset, total = #rows,
			done = offset + #chunk >= #rows }
		for key, value in pairs(extra or {}) do payload[key] = value end
		TriggerClientEvent(event, playerId, payload)
		offset = offset + #chunk
	until offset >= #rows
end

--- @author DemiAutomatic
--- @method pushRoster
--- @description Sends the roster, as seen from the operator, to the operator.
--- @param playerId {integer}
local function pushRoster(playerId)
	local origin = Server.PositionOf(playerId)
	local rows = {}
	for _, id in ipairs(Server.PlayerIds()) do
		local row = Server.RosterRow(id, origin)
		if row then rows[#rows + 1] = row end
	end
	pushChunks(playerId, 'opx77_admin:roster', rows)
end

--- @author DemiAutomatic
--- @method pushLocations
--- @description Sends the destination list to the operator, in chunks.
--- @param playerId {integer}
local function pushLocations(playerId)
	local rows = {}
	for _, row in ipairs(Server.Locations()) do
		rows[#rows + 1] = { name = row.name, label = row.label, runtime = row.runtime }
	end
	pushChunks(playerId, 'opx77_admin:locations', rows)
end

--- @author DemiAutomatic
--- @method pushItems
--- @description Sends the inventory catalogue for the pickers, coroutine only.
--- @param playerId {integer}
local function pushItems(playerId)
	local catalog, code = Inventory.Catalog()
	local rows = {}
	for _, entry in ipairs(catalog and catalog.items or {}) do
		rows[#rows + 1] = { name = entry.name, label = entry.label, category = entry.category,
			class = entry.weapon and entry.weapon.class or nil, max = entry.ammoMax }
	end
	pushChunks(playerId, 'opx77_admin:items', rows, { error = code })
end

--- @author DemiAutomatic
--- @method pushBag
--- @description Sends one bag's stacks for the removal picker, coroutine only.
--- @param playerId {integer}
--- @param token {string}
local function pushBag(playerId, token)
	local target, _, _, targetCode = Inventory.Target(playerId, token)
	local bag, code
	if target ~= nil then bag, code = Inventory.Bag(target) end
	local catalog = bag and Inventory.Catalog() or nil
	local rows = {}
	for _, row in ipairs(bag and bag.items or {}) do
		rows[#rows + 1] = { slot = row.slot, name = row.name, count = row.count,
			label = Inventory.LabelOf(catalog, row.name) }
	end
	pushChunks(playerId, 'opx77_admin:bag', rows, { target = token, error = targetCode or code })
end

--- @author DemiAutomatic
--- @command /opx77.admin
--- @description Opens the staff menu with the access map and its lists.
Server.Command(OPENER, {
	help = 'admin.help.menu', inGame = true, read = true,
	handler = function(source)
		local access, known = accessOf(source)
		TriggerClientEvent('opx77_admin:open', source, {
			access = access,
			aclKnown = known,
			weapons = Server.WeaponsAvailable(),
			inventory = Inventory.Running(),
		})
		Server.PushBodies(source)
		pushRoster(source)
		pushLocations(source)
		if Inventory.Running() then CreateThread(function() pushItems(source) end) end
	end,
})

--- @author DemiAutomatic
--- @event opx77_admin:refresh
--- @description Sends a menu list again, re-checked against the opener's grant.
--- @param topic {string} roster, locations, access, items or bag.
--- @param arg {string|nil} The holder, for a bag.
RegisterNetEvent('opx77_admin:refresh', function(topic, arg)
	local player = tonumber(source) or 0
	if player <= 0 then return end
	if topic ~= 'roster' and topic ~= 'locations' and topic ~= 'access' and topic ~= 'items' and
		topic ~= 'bag' then
		return
	end
	if topic == 'bag' and (type(arg) ~= 'string' or #arg > 32) then return end

	if Server.Cooled(player, 'refresh:' .. topic, Server.Setting((Config.RATE or {}).REFRESH_MS, 750)) then
		return
	end

	if Server.Permitted(player, OPENER) ~= true then
		-- An empty map, so a client that drew staff rows takes them down.
		if topic == 'access' then
			TriggerClientEvent('opx77_admin:access', player, { access = {}, aclKnown = true, inventory = false })
		end
		return
	end

	if topic == 'roster' then
		pushRoster(player)
	elseif topic == 'locations' then
		pushLocations(player)
	elseif topic == 'items' then
		CreateThread(function() pushItems(player) end)
	elseif topic == 'bag' then
		if Server.Permitted(player, 'opx77.admin.inventory.view') ~= true and
			Server.Permitted(player, 'opx77.admin.inventory.remove') ~= true then
			return
		end
		CreateThread(function() pushBag(player, arg) end)
	else
		local access, known = accessOf(player)
		TriggerClientEvent('opx77_admin:access', player, { access = access, aclKnown = known,
			inventory = Inventory.Running() })
		Server.PushBodies(player)
	end
end)

--- @author DemiAutomatic
--- @event opx77_admin:targetReport
--- @description Writes how a staff client's rows on opx77_target registered into the server log.
--- @param text {string}
RegisterNetEvent('opx77_admin:targetReport', function(text)
	local player = tonumber(source) or 0
	if player <= 0 or type(text) ~= 'string' or Server.Cooled(player, 'target:report', 1000) then return end
	if Server.Permitted(player, OPENER) ~= true then return end
	Open77.log.info(('target rows, player %d: %s'):format(player, OpxAdmin.Text.Clean(text, 160) or '?'))
end)

Open77.log.info(('ready -- %d restricted commands; grant command.%s to open the menu')
	:format(#Server.Commands(), OPENER))
