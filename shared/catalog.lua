--- The index over data/vehicles.lua and data/weapons.lua. Both halves read it: the server to
--- refuse a vehicle that is not a row, both to group weapons, the client to draw the lists. A
--- malformed row is dropped and named in `problems`, which the server logs at boot, rather than
--- raising at load.

OpxAdmin = OpxAdmin or {}

local Text = OpxAdmin.Text

local Catalog = {
	problems = {},
}
OpxAdmin.Catalog = Catalog

---@param line string
local function problem(line)
	Catalog.problems[#Catalog.problems + 1] = line
end

--- The vehicle classes, in menu order, with a lookup by key.
---@type table[]
local vehicleClasses = {}
local vehicleClassIndex = {}
---@type table<string, CatalogEntry>
local vehiclesByName, vehiclesByRecord = {}, {}

local vehicleRows = {}
do
	local source = OPX_ADMIN_VEHICLES
	if type(source) ~= 'table' or type(source.CLASSES) ~= 'table' then
		problem('data/vehicles.lua: CLASSES must be a table')
	else
		for position, row in ipairs(source.CLASSES) do
			local key = type(row) == 'table' and Text.slug(row.KEY) or nil
			if key == nil or vehicleClassIndex[key] ~= nil then
				problem(('data/vehicles.lua: class #%d needs a unique KEY'):format(position))
			else
				local class = { key = key, label = Text.clean(row.LABEL, 48) or key, members = {} }
				vehicleClasses[#vehicleClasses + 1] = class
				vehicleClassIndex[key] = class
			end
		end
		if type(source.VEHICLES) == 'table' then
			vehicleRows = source.VEHICLES
		else
			problem('data/vehicles.lua: VEHICLES must be a table')
		end
	end
end

--- Rows one catalogue file indexes. The host checks a script's load time every 10 000 VM
--- instructions and rolls the whole resource set back when a check lands past its deadline,
--- so no file here may reach one: a row costs about 110 instructions, and each
--- shared/catalog-<n>.lua part indexes this many of them. This file indexes none.
local PART = 68

--- The next row of data/vehicles.lua to index.
local nextRow = 1

--- Index the next `count` rows into their classes and the lookups by name and by record.
---@param count integer
function Catalog.indexVehicles(count)
	local last = math.min(#vehicleRows, nextRow + count - 1)
	for position = nextRow, last do
		local row = vehicleRows[position]
		local name = type(row) == 'table' and Text.slug(row.NAME) or nil
		local record = type(row) == 'table' and type(row.RECORD) == 'string'
			and row.RECORD:match('^[%w_%.]+$') and row.RECORD or nil
		local class = type(row) == 'table' and vehicleClassIndex[tostring(row.CLASS or '')] or nil
		local lowered = record and record:lower()
		local wrong = name == nil and 'NAME must be 1..32 letters, digits, _ or -'
			or record == nil and 'RECORD must be a TweakDB record name'
			or class == nil and 'CLASS is not a KEY in CLASSES'
			or (vehiclesByName[name] ~= nil or vehiclesByRecord[lowered] ~= nil)
				and 'NAME or RECORD is declared twice'
			or nil
		if wrong then
			problem(('data/vehicles.lua: row #%d: %s'):format(position, wrong))
		else
			local entry = {
				name = name,
				label = Text.clean(row.LABEL, 48) or name,
				record = record,
				class = class.key,
			}
			class.members[#class.members + 1] = entry
			vehiclesByName[name] = entry
			vehiclesByRecord[lowered] = entry
		end
	end
	nextRow = last + 1
end

--- The last part: whatever is left, so a missing part costs load time, never a vehicle.
function Catalog.finishVehicles()
	local left = #vehicleRows - nextRow + 1
	if left > PART then
		problem(('data/vehicles.lua: %d rows were left to the last catalogue part; add a ' ..
			'shared/catalog-<n>.lua part to open77.lua for every %d rows past it'):format(left, PART))
	end
	Catalog.indexVehicles(left)
end

Catalog.PART = PART

--- The weapon classes: an order and a label. The weapons are opx77_inventory's items and are
--- read from it, so no row here names a record.
---@type WeaponClass[]
local weaponClasses = {}
local weaponClassIndex = {}
do
	local source = type(OPX_ADMIN_WEAPONS) == 'table' and OPX_ADMIN_WEAPONS or nil
	if source == nil or type(source.CLASSES) ~= 'table' then
		problem('data/weapons.lua: CLASSES must be a table')
	else
		for position, row in ipairs(source.CLASSES) do
			local key = type(row) == 'table' and Text.slug(row.KEY) or nil
			if key == nil or weaponClassIndex[key] ~= nil then
				problem(('data/weapons.lua: class #%d needs a unique KEY'):format(position))
			else
				local class = { key = key, label = Text.clean(row.LABEL, 48) or key }
				weaponClasses[#weaponClasses + 1] = class
				weaponClassIndex[key] = class
			end
		end
	end
end

Catalog.vehicleClasses = vehicleClasses
Catalog.weaponClasses = weaponClasses

--- A vehicle row by the name staff type or by its exact record, without case.
---@param token any
---@return CatalogEntry|nil
function Catalog.vehicle(token)
	if type(token) ~= 'string' then return nil end
	local lowered = token:lower()
	return vehiclesByName[lowered] or vehiclesByRecord[lowered]
end
