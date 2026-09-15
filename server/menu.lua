--- The menu's server half: the opener command, and the one inbound event, which asks for the
--- roster, the destination list, the access map, the inventory's catalogue or a bag again.
---
--- The menu decides nothing. What it shows comes from here, and everything it does is a command
--- line sent through open77:command:execute -- the path the chat box uses -- so the host
--- resolves `command.<name>` for every row exactly as it would for a typed command. A client
--- that forges a row gets the answer a typed command would get.

local Config = OPX_ADMIN_CONFIG
local Server = OpxAdmin.Server
local Inventory = OpxAdmin.Inventory

--- The permission the refresh event is re-checked against: whoever may open the menu may read
--- what it draws. Net events carry no authorisation of their own on this platform.
local OPENER = 'opx77.admin'

--- Rows per roster, catalogue or bag event. The host drops an event past 1024 value nodes
--- without a word, and a row is about a dozen.
local ROSTER_CHUNK = 20

local lastRefresh = {}

--- Every command name the menu may issue, this resource's and the linked ones.
---@return string[]
local function menuCommands()
	local names = {}
	for _, command in ipairs(Server.Commands()) do names[#names + 1] = command.name end
	for _, name in pairs(type(Config.LINKS) == 'table' and Config.LINKS or {}) do
		if type(name) == 'string' and name ~= '' then names[#names + 1] = name end
	end
	return names
end

--- What this operator's ACL grants, so the menu can grey out a row the host would refuse. A
--- hint for drawing and nothing more: the host still resolves every command line.
---@param playerId integer
---@return table<string, true> access, boolean known
local function accessOf(playerId)
	local access, known = {}, true
	for _, name in ipairs(menuCommands()) do
		local allowed = Server.Permitted(playerId, name)
		if allowed == nil then known = false end
		-- only the grants travel: a false costs two value nodes and says nothing a nil does not
		if allowed == true then access[name] = true end
	end
	return access, known
end

--- Rows in chunks: the host drops an event past 1024 value nodes without a word.
---@param playerId integer
---@param event string
---@param rows table[]
---@param extra table|nil  copied into every chunk
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

---@param playerId integer
local function pushRoster(playerId)
	local origin = Server.PositionOf(playerId)
	local rows = {}
	for _, id in ipairs(Server.PlayerIds()) do
		local row = Server.RosterRow(id, origin)
		if row then rows[#rows + 1] = row end
	end
	pushChunks(playerId, 'opx77_admin:roster', rows)
end

---@param playerId integer
local function pushLocations(playerId)
	local rows = {}
	for _, row in ipairs(Server.Locations()) do
		rows[#rows + 1] = { name = row.name, label = row.label, runtime = row.runtime }
	end
	TriggerClientEvent('opx77_admin:locations', playerId, { rows = rows })
end

--- opx77_inventory's catalogue, for the item, weapon and ammunition pickers. `max` is an ammo
--- item's full load, the count its form starts at. Coroutine only.
---@param playerId integer
local function pushItems(playerId)
	local catalog, code = Inventory.Catalog()
	local rows = {}
	for _, entry in ipairs(catalog and catalog.items or {}) do
		rows[#rows + 1] = { name = entry.name, label = entry.label, category = entry.category,
			class = entry.weapon and entry.weapon.class or nil, max = entry.ammoMax }
	end
	pushChunks(playerId, 'opx77_admin:items', rows, { error = code })
end

--- The stacks of one bag, for the remove picker. Coroutine only.
---@param playerId integer
---@param token string
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

Server.Command(OPENER, {
	help = 'admin.help.menu', inGame = true, read = true,
	handler = function(source)
		local access, known = accessOf(source)
		TriggerClientEvent('opx77_admin:open', source, {
			you = source,
			access = access,
			aclKnown = known,
			weapons = Server.WeaponsAvailable(),
			inventory = Inventory.Running(),
		})
		pushRoster(source)
		pushLocations(source)
		if Inventory.Running() then CreateThread(function() pushItems(source) end) end
		-- no command result: the menu opening is the answer, and a chat line per open is noise
	end,
})

--- The menu asks for a list again. Re-checked against the opener's grant with the same ACL the
--- host uses for commands, because anybody can send a net event. A bag's stacks are somebody's
--- belongings, so they also need the grant to view or to remove from one.
RegisterNetEvent('opx77_admin:refresh', function(topic, arg)
	local player = tonumber(source) or 0
	if player <= 0 then return end
	if topic ~= 'roster' and topic ~= 'locations' and topic ~= 'access' and topic ~= 'items' and
		topic ~= 'bag' then
		return
	end
	if topic == 'bag' and (type(arg) ~= 'string' or #arg > 32) then return end

	local atMs = Server.NowMs()
	local slot = player .. ':' .. topic
	local floor = Server.Setting((Config.RATE or {}).REFRESH_MS, 750)
	if lastRefresh[slot] ~= nil and atMs - lastRefresh[slot] < floor then return end
	lastRefresh[slot] = atMs

	-- fails closed: without an ACL reader there is no way to tell staff from anybody else here,
	-- and the opener command itself still works to refresh everything
	if Server.Permitted(player, OPENER) ~= true then return end

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
	end
end)

AddEventHandler('onPlayerDisconnected', function(playerId)
	local prefix = tostring(tonumber(playerId) or 0) .. ':'
	for slot in pairs(lastRefresh) do
		if slot:sub(1, #prefix) == prefix then lastRefresh[slot] = nil end
	end
end)

local names = {}
for _, command in ipairs(Server.Commands()) do names[#names + 1] = command.name end
Open77.log.info(('ready -- %d restricted commands; grant command.%s to open the menu')
	:format(#names, OPENER))
