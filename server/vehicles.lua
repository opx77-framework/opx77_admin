--- Vehicle commands: spawn from the catalogue, deliver to a player, repair, flag, remove, and
--- clean up. The host scopes every mutation to the resource that created the vehicle, so this
--- file can only ever touch what it spawned, and says so rather than answering "0 removed".

local Config = OPX_ADMIN_CONFIG
local Server = OpxAdmin.Server
local Catalog = OpxAdmin.Catalog
local Text = OpxAdmin.Text

local answer, refuse, audit, tell = Server.Answer, Server.Refuse, Server.Audit, Server.Tell
local count = Server.Count

local Settings = Config.VEHICLES or {}

--- vehicleId -> { owner, record, label, atMs }. What this resource spawned and for whom.
local spawned = {}

local SCOPES = { glass = true, body = true, lights = true, tires = true, visual = true,
	mechanical = true, full = true }

---@return boolean
local function available()
	return type(Open77.vehicles) == 'table' and type(Open77.vehicles.create) == 'function'
end

--- The host's snapshot of one vehicle, or nil. The server shape carries x, y, z and bucket at
--- the top level; occupant ids may arrive as strings.
---@param vehicleId integer
---@return table|nil
local function snapshotOf(vehicleId)
	local read, snapshot = pcall(Open77.vehicles.get, vehicleId)
	if not read or type(snapshot) ~= 'table' then return nil end
	return snapshot
end

---@param snapshot table
---@return integer[]
local function occupantsOf(snapshot)
	local list = {}
	for _, occupant in ipairs(type(snapshot.occupants) == 'table' and snapshot.occupants or {}) do
		local playerId = tonumber(type(occupant) == 'table' and occupant.playerId or occupant)
		if playerId then list[#list + 1] = playerId end
	end
	return list
end

--- Forget ledger rows whose vehicle the host no longer knows, whoever removed it.
local function prune()
	for vehicleId in pairs(spawned) do
		if snapshotOf(vehicleId) == nil then spawned[vehicleId] = nil end
	end
end

---@param owner integer
---@return integer
local function ownedBy(owner)
	local total = 0
	for _, entry in pairs(spawned) do
		if entry.owner == owner then total = total + 1 end
	end
	return total
end

--- The vehicle a `near` token means for this operator: the one they sit in, otherwise the
--- nearest in their bucket within NEAR_RADIUS. Answered from the live snapshot, never from a
--- list a menu drew seconds ago.
---@param source integer
---@return integer|nil vehicleId, string|nil code
local function nearest(source)
	if source <= 0 then return nil, 'console_has_no_player' end
	local origin = Server.PositionOf(source)
	if origin == nil then return nil, 'no_position' end
	local read, all = pcall(Open77.vehicles.all)
	if not read or type(all) ~= 'table' then return nil, 'no_vehicle' end
	local radius = Server.Setting(Settings.NEAR_RADIUS, 30.0)
	local best, bestDistance
	for _, snapshot in ipairs(all) do
		local id = Text.Integer(snapshot.id)
		if id then
			for _, occupant in ipairs(occupantsOf(snapshot)) do
				if occupant == source then return id, nil end
			end
			local x, y, z = Text.Finite(snapshot.x), Text.Finite(snapshot.y), Text.Finite(snapshot.z)
			if x and y and z and (Text.Integer(snapshot.bucket) or 0) == origin.bucket then
				local dx, dy, dz = x - origin.x, y - origin.y, z - origin.z
				local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
				if distance <= radius and (bestDistance == nil or distance < bestDistance) then
					best, bestDistance = id, distance
				end
			end
		end
	end
	if best == nil then return nil, 'no_vehicle' end
	return best, nil
end

--- `near` or a vehicle id, resolved, or the refusal answered.
---@return integer|nil
local function vehicleOf(source, raw, token)
	if type(token) == 'string' and token:lower() == 'near' then
		local vehicleId, code = nearest(source)
		if vehicleId == nil then refuse(source, raw, code) end
		return vehicleId
	end
	local vehicleId = Text.Integer(token)
	if vehicleId == nil or vehicleId <= 0 or snapshotOf(vehicleId) == nil then
		refuse(source, raw, 'no_vehicle')
		return nil
	end
	return vehicleId
end

--- Spawn one catalogue row beside a player.
---@param source integer   who asked
---@param raw string
---@param owner integer    who it is for, and whose cap it counts against
---@param entry CatalogEntry
---@param event string
local function spawnFor(source, raw, owner, entry, event)
	-- a vehicle dropped beside a player still in the menu world lands beside nobody
	local admitted, code = Server.Admit(owner)
	if not admitted then
		audit(source, event, false, owner, code)
		return refuse(source, raw, code, { id = owner })
	end
	prune()
	local cap = math.max(1, math.floor(Server.Setting(Settings.PER_OWNER, 8)))
	if ownedBy(owner) >= cap then
		return refuse(source, raw, 'vehicle_cap', { cap = cap, id = owner })
	end
	local position = Server.PositionOf(owner)
	if position == nil then return refuse(source, raw, 'no_position') end

	local offset = Settings.SPAWN_OFFSET or {}
	local vehicleId, reason = Open77.vehicles.create({
		record = entry.record,
		position = {
			x = position.x + Server.Setting(offset.X, 3.0),
			y = position.y + Server.Setting(offset.Y, 0.0),
			z = position.z + Server.Setting(offset.Z, 0.25),
		},
		yaw = 0.0,
		bucket = position.bucket,
	})
	if vehicleId == nil then
		audit(source, event, false, owner, ('%s refused: %s'):format(entry.record, tostring(reason)))
		return refuse(source, raw, 'refused', { reason = tostring(reason) })
	end
	spawned[vehicleId] = { owner = owner, record = entry.record, label = entry.label,
		atMs = Server.NowMs() }
	audit(source, event, true, owner, ('%d %s'):format(vehicleId, entry.record))
	if owner ~= source then tell(owner, 'admin.toast.vehicle', { label = entry.label }) end
	answer(source, raw, true, 'admin.done.spawned',
		{ vehicle = vehicleId, label = entry.label, id = owner })
end

Server.Command('opx77.admin.vehicle.spawn', {
	help = 'admin.help.spawn', params = { { name = 'vehicle', help = 'admin.help.vehicleName' } },
	inGame = true,
	handler = function(source, args, raw)
		if not available() then return refuse(source, raw, 'vehicles_unavailable') end
		local entry = Catalog.Vehicle(args[1])
		if entry == nil then return refuse(source, raw, 'unknown_vehicle') end
		spawnFor(source, raw, source, entry, 'admin.vehicle.spawn')
	end,
})

Server.Command('opx77.admin.vehicle.give', {
	help = 'admin.help.giveVehicle',
	params = { { name = 'playerId|me', help = 'admin.help.playerOrMe' },
		{ name = 'vehicle', help = 'admin.help.vehicleName' } },
	handler = function(source, args, raw)
		if not available() then return refuse(source, raw, 'vehicles_unavailable') end
		local playerId, code = Server.Target(source, args[1])
		if playerId == nil then return refuse(source, raw, code) end
		local entry = Catalog.Vehicle(args[2])
		if entry == nil then return refuse(source, raw, 'unknown_vehicle') end
		spawnFor(source, raw, playerId, entry, 'admin.vehicle.give')
	end,
})

--- Remove one vehicle. Refused with somebody aboard: removing an occupied vehicle drops the
--- occupants wherever it was, and the case that matters is the one where somebody climbed in
--- after the menu was drawn.
---@return boolean removed, string|nil code
local function removeOne(vehicleId)
	local snapshot = snapshotOf(vehicleId)
	if snapshot == nil then
		spawned[vehicleId] = nil
		return false, 'no_vehicle'
	end
	if #occupantsOf(snapshot) > 0 then return false, 'occupied' end
	local read, removed = pcall(Open77.vehicles.remove, vehicleId)
	if not read or removed ~= true then return false, 'not_ours' end
	spawned[vehicleId] = nil
	return true
end

Server.Command('opx77.admin.vehicle.remove', {
	help = 'admin.help.removeVehicle',
	params = { { name = 'vehicleId|near|mine', help = 'admin.help.removeTarget', optional = true } },
	handler = function(source, args, raw)
		if not available() then return refuse(source, raw, 'vehicles_unavailable') end
		local token = type(args[1]) == 'string' and args[1]:lower() or 'near'
		if token == 'mine' then
			if source <= 0 then return refuse(source, raw, 'console_has_no_player') end
			local removed, kept = 0, 0
			for vehicleId, entry in pairs(spawned) do
				if entry.owner == source then
					if removeOne(vehicleId) then removed = removed + 1 else kept = kept + 1 end
				end
			end
			audit(source, 'admin.vehicle.remove', true, nil, ('mine: %d removed, %d kept'):format(
				removed, kept))
			return answer(source, raw, removed > 0, 'admin.done.removedMany',
				{ removed = removed, kept = kept })
		end

		local vehicleId = vehicleOf(source, raw, token)
		if vehicleId == nil then return end
		local removed, code = removeOne(vehicleId)
		audit(source, 'admin.vehicle.remove', removed, nil, ('%d %s'):format(vehicleId, code or ''))
		if not removed then return refuse(source, raw, code, { vehicle = vehicleId }) end
		answer(source, raw, true, 'admin.done.removed', { vehicle = vehicleId })
	end,
})

Server.Command('opx77.admin.vehicle.cleanup', {
	help = 'admin.help.cleanup',
	handler = function(source, _, raw)
		if not available() then return refuse(source, raw, 'vehicles_unavailable') end
		local removed, kept = 0, 0
		for vehicleId in pairs(spawned) do
			if removeOne(vehicleId) then removed = removed + 1 else kept = kept + 1 end
		end
		audit(source, 'admin.vehicle.cleanup', true, nil, ('%d removed, %d kept'):format(removed, kept))
		answer(source, raw, true, 'admin.done.removedMany', { removed = removed, kept = kept })
	end,
})

Server.Command('opx77.admin.vehicle.repair', {
	help = 'admin.help.repair',
	params = { { name = 'vehicleId|near', help = 'admin.help.repairTarget', optional = true },
		{ name = 'scope', help = 'admin.help.repairScope', optional = true } },
	handler = function(source, args, raw)
		if not available() then return refuse(source, raw, 'vehicles_unavailable') end
		local scope = type(args[2]) == 'string' and args[2]:lower() or 'full'
		if not SCOPES[scope] then return refuse(source, raw, 'bad_scope') end
		local vehicleId = vehicleOf(source, raw, args[1] or 'near')
		if vehicleId == nil then return end
		local snapshot = snapshotOf(vehicleId)
		local safe = Settings.OCCUPIED_REPAIRS or {}
		-- read at the moment of the call: `full` and `mechanical` may respawn the vehicle
		if snapshot and #occupantsOf(snapshot) > 0 and safe[scope] ~= true then
			return refuse(source, raw, 'unsafe_repair', { scope = scope })
		end
		local ok, reason = Open77.vehicles.repair(vehicleId, scope)
		audit(source, 'admin.vehicle.repair', ok == true, nil,
			('%d %s %s'):format(vehicleId, scope, ok and '' or tostring(reason)))
		if not ok then return refuse(source, raw, 'refused', { reason = tostring(reason) }) end
		answer(source, raw, true, 'admin.done.repaired', { vehicle = vehicleId, scope = scope })
	end,
})

--- The flags an operator may toggle, as configured, validated against the host's masks.
---@param name any
---@return integer|nil mask, string|nil flag
local function maskOf(name)
	if type(name) ~= 'string' then return nil end
	local masks = Open77.vehicles.flags
	for _, flag in ipairs(Settings.FLAGS or {}) do
		if flag:lower() == name:lower() and type(masks) == 'table' then
			local mask = Text.Integer(masks[flag])
			if mask then return mask, flag end
		end
	end
	return nil
end

Server.Command('opx77.admin.vehicle.flag', {
	help = 'admin.help.flag',
	params = { { name = 'vehicleId|near', help = 'admin.help.vehicleTarget' },
		{ name = 'flag', help = 'admin.help.flagName' },
		{ name = 'on|off', help = 'admin.help.toggle', optional = true } },
	handler = function(source, args, raw)
		if not available() then return refuse(source, raw, 'vehicles_unavailable') end
		if count(args) < 2 then return answer(source, raw, false, 'admin.usage.flag') end
		local mask, flag = maskOf(args[2])
		if mask == nil then
			return refuse(source, raw, 'unknown_flag',
				{ flags = table.concat(Settings.FLAGS or {}, ', ') })
		end
		local wanted, invalid = Text.Switch(args[3])
		if invalid then return refuse(source, raw, 'bad_switch') end
		local vehicleId = vehicleOf(source, raw, args[1])
		if vehicleId == nil then return end
		local snapshot = snapshotOf(vehicleId)
		if snapshot == nil then return refuse(source, raw, 'no_vehicle') end
		-- read-modify-write on the live bits: the patch replaces the whole set
		local bits = Text.Integer(snapshot.flags) or 0
		if wanted == nil then wanted = (bits & mask) == 0 end
		local nextBits = wanted and (bits | mask) or (bits & ~mask)
		local ok, reason = Open77.vehicles.update(vehicleId, { flags = nextBits })
		audit(source, 'admin.vehicle.flag', ok == true, nil,
			('%d %s=%s %s'):format(vehicleId, flag, wanted and 'on' or 'off',
				ok and '' or tostring(reason)))
		if not ok then return refuse(source, raw, 'refused', { reason = tostring(reason) }) end
		answer(source, raw, true, wanted and 'admin.done.flagOn' or 'admin.done.flagOff',
			{ vehicle = vehicleId, flag = flag })
	end,
})

--- For the status readout.
---@return integer
function OpxAdmin.Server.SpawnedCount()
	prune()
	local total = 0
	for _ in pairs(spawned) do total = total + 1 end
	return total
end

if not available() then
	Open77.log.warn('Open77.vehicles is unavailable on this host: every vehicle command refuses')
end
