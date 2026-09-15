--- @author DemiAutomatic
--- @file server/tags.lua
--- @description Staff name tags: the switch, and the name list only staff receive.

local Config = OPX_ADMIN_CONFIG
local Server = OpxAdmin.Server
local Text = OpxAdmin.Text

local answer, refuse, audit = Server.Answer, Server.Refuse, Server.Audit

--- @author DemiAutomatic
--- @type {string}
--- @description The switch command, whose grant every name list is checked against.
local COMMAND = 'opx77.admin.self.tags'

--- @author DemiAutomatic
--- @type {string}
--- @description The opener command, whose grant marks a player as staff.
local STAFF = 'opx77.admin'

--- @author DemiAutomatic
--- @type {integer}
--- @description Rows per name list event.
local CHUNK = 40

--- @author DemiAutomatic
--- @type {table}
--- @description The TAGS config table, or an empty one.
local TAGS = type(Config.TAGS) == 'table' and Config.TAGS or {}

--- @author DemiAutomatic
--- @type {integer}
--- @description Milliseconds between two name lists, at least half a second.
local REFRESH_MS = math.max(500, math.floor(Server.Setting(TAGS.REFRESH_MS, 2000)))

--- @author DemiAutomatic
--- @type {table<integer, string|false>}
--- @description Players with tags on, to the last list they were sent.
local watching = {}

--- @author DemiAutomatic
--- @method granted
--- @description Whether the ACL grants the switch, failing closed when unreadable.
--- @param playerId {integer}
--- @returns {boolean}
local function granted(playerId)
	return Server.Permitted(playerId, COMMAND) == true
end

--- @author DemiAutomatic
--- @method nameRows
--- @description Every connected player's id, verified name and staff mark.
--- @returns {table[]}
local function nameRows()
	local rows = {}
	local badge = TAGS.BADGE ~= false
	for _, id in ipairs(Server.PlayerIds()) do
		local name = Server.NameOf(id)
		if name then
			rows[#rows + 1] = { id = id, name = name,
				staff = badge and Server.Permitted(id, STAFF) == true or nil }
		end
	end
	return rows
end

--- @author DemiAutomatic
--- @method signature
--- @description One string per list, so an unchanged list is not sent again.
--- @param rows {table[]}
--- @returns {string}
local function signature(rows)
	local parts = {}
	for index, row in ipairs(rows) do
		parts[index] = ('%d\t%s\t%d'):format(row.id, row.name, row.staff and 1 or 0)
	end
	return table.concat(parts, '\n')
end

--- @author DemiAutomatic
--- @method push
--- @description Sends the name list to one staff member when it changed.
--- @param playerId {integer}
--- @param rows {table[]}
--- @param sent {string}
local function push(playerId, rows, sent)
	if watching[playerId] == sent then return end
	local offset = 0
	repeat
		local chunk = {}
		for index = offset + 1, math.min(offset + CHUNK, #rows) do chunk[#chunk + 1] = rows[index] end
		TriggerClientEvent('opx77_admin:tagRows', playerId, { rows = chunk, offset = offset,
			done = offset + #chunk >= #rows })
		offset = offset + #chunk
	until offset >= #rows
	watching[playerId] = sent
end

--- @author DemiAutomatic
--- @method setShown
--- @description Switches a player's tags and tells the client half.
--- @param playerId {integer}
--- @param on {boolean}
--- @param persist {boolean} Whether the client saves it as its preference.
local function setShown(playerId, on, persist)
	if on then
		watching[playerId] = false
	else
		watching[playerId] = nil
	end
	TriggerClientEvent('opx77_admin:tagsState', playerId, on == true, persist == true)
	if on then
		local rows = nameRows()
		push(playerId, rows, signature(rows))
	end
end

--- @author DemiAutomatic
--- @command /opx77.admin.self.tags
--- @description Switches name tags for the operator, toggling when no word is typed.
Server.Command(COMMAND, {
	help = 'admin.help.tags',
	params = { { name = 'on|off', help = 'admin.help.toggle', optional = true } },
	inGame = true,
	handler = function(source, args, raw)
		local wanted, invalid = Text.Switch(args[1])
		if invalid then return refuse(source, raw, 'bad_switch') end
		if wanted == nil then wanted = watching[source] == nil end
		if wanted and not granted(source) then
			return refuse(source, raw, 'refused', { reason = 'acl_unreadable' })
		end
		setShown(source, wanted, true)
		audit(source, 'admin.self.tags', true, nil, wanted and 'on' or 'off')
		answer(source, raw, true, wanted and 'admin.done.tagsOn' or 'admin.done.tagsOff')
	end,
})

--- @author DemiAutomatic
--- @event opx77_admin:tagsRestore
--- @description Turns tags back on for staff whose client saved them on.
RegisterNetEvent('opx77_admin:tagsRestore', function()
	local player = tonumber(source) or 0
	if player <= 0 or Server.Cooled(player, 'tags:restore', 2000) then return end
	if not granted(player) then
		return TriggerClientEvent('opx77_admin:tagsState', player, false, false)
	end
	if watching[player] == nil then audit(player, 'admin.self.tags', true, nil, 'restored') end
	setShown(player, true, false)
end)

CreateThread(function()
	while true do
		Wait(REFRESH_MS)
		local swept, failure = pcall(function()
			local rows, sent
			for playerId in pairs(watching) do
				if not granted(playerId) then
					watching[playerId] = nil
					TriggerClientEvent('opx77_admin:tagsState', playerId, false, false)
					Open77.log.info(('name tags off for player %d: %s is no longer granted')
						:format(playerId, COMMAND))
				else
					if rows == nil then
						rows = nameRows()
						sent = signature(rows)
					end
					push(playerId, rows, sent)
				end
			end
		end)
		if not swept then Open77.log.warn('name tag sweep failed: ' .. tostring(failure)) end
	end
end)

--- @author DemiAutomatic
--- @event onPlayerDisconnected
--- @description Forgets a departing player's name tag switch.
--- @param playerId {integer|string}
AddEventHandler('onPlayerDisconnected', function(playerId)
	watching[tonumber(playerId) or 0] = nil
end)
