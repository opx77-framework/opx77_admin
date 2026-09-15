--- @author DemiAutomatic
--- @file shared/catalog.lua
--- @description The index over the vehicle and weapon class data files.

OpxAdmin = OpxAdmin or {}

local Text = OpxAdmin.Text

--- @author DemiAutomatic
--- @type {table}
--- @description Vehicle and weapon class index, with the boot problems found.
OpxAdmin.Catalog = {
	problems = {},
}
local Catalog = OpxAdmin.Catalog

--- @author DemiAutomatic
--- @method problem
--- @description Records one malformed data row for the boot log.
--- @param line {string}
local function problem(line)
	Catalog.problems[#Catalog.problems + 1] = line
end

--- @author DemiAutomatic
--- @type {CatalogClass[]}
--- @description The vehicle classes, in menu order.
local vehicleClasses = {}

--- @author DemiAutomatic
--- @type {table<string, CatalogClass>}
--- @description The vehicle classes by key.
local vehicleClassIndex = {}

--- @author DemiAutomatic
--- @type {table<string, CatalogEntry>, table<string, CatalogEntry>}
--- @description Indexed vehicle rows by name and by lower-cased record.
local vehiclesByName, vehiclesByRecord = {}, {}

--- @author DemiAutomatic
--- @type {table[]}
--- @description The raw vehicle rows the catalogue parts index.
local vehicleRows = {}
do
	local source = OPX_ADMIN_VEHICLES
	if type(source) ~= 'table' or type(source.CLASSES) ~= 'table' then
		problem('data/vehicles.lua: CLASSES must be a table')
	else
		for position, row in ipairs(source.CLASSES) do
			local key = type(row) == 'table' and Text.Slug(row.KEY) or nil
			if key == nil or vehicleClassIndex[key] ~= nil then
				problem(('data/vehicles.lua: class #%d needs a unique KEY'):format(position))
			else
				local class = { key = key, label = Text.Clean(row.LABEL, 48) or key, members = {} }
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

--- @author DemiAutomatic
--- @type {integer}
--- @description Vehicle rows each catalogue part indexes at load.
local PART = 68

--- @author DemiAutomatic
--- @type {integer}
--- @description The next vehicle row to index.
local nextRow = 1

--- @author DemiAutomatic
--- @method OpxAdmin.Catalog.IndexVehicles
--- @description Indexes the next rows into their classes and both lookups.
--- @param count {integer}
function OpxAdmin.Catalog.IndexVehicles(count)
	local last = math.min(#vehicleRows, nextRow + count - 1)
	for position = nextRow, last do
		local row = vehicleRows[position]
		local name = type(row) == 'table' and Text.Slug(row.NAME) or nil
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
				label = Text.Clean(row.LABEL, 48) or name,
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

--- @author DemiAutomatic
--- @method OpxAdmin.Catalog.FinishVehicles
--- @description Indexes every row left, naming an overloaded last part.
function OpxAdmin.Catalog.FinishVehicles()
	local left = #vehicleRows - nextRow + 1
	if left > PART then
		problem(('data/vehicles.lua: %d rows were left to the last catalogue part; add a ' ..
			'shared/catalog-<n>.lua part to open77.lua for every %d rows past it'):format(left, PART))
	end
	Catalog.IndexVehicles(left)
end

Catalog.PART = PART

--- @author DemiAutomatic
--- @type {WeaponClass[]}
--- @description The weapon classes, in menu order.
local weaponClasses = {}

--- @author DemiAutomatic
--- @type {table<string, WeaponClass>}
--- @description The weapon classes by key.
local weaponClassIndex = {}
do
	local source = type(OPX_ADMIN_WEAPONS) == 'table' and OPX_ADMIN_WEAPONS or nil
	if source == nil or type(source.CLASSES) ~= 'table' then
		problem('data/weapons.lua: CLASSES must be a table')
	else
		for position, row in ipairs(source.CLASSES) do
			local key = type(row) == 'table' and Text.Slug(row.KEY) or nil
			if key == nil or weaponClassIndex[key] ~= nil then
				problem(('data/weapons.lua: class #%d needs a unique KEY'):format(position))
			else
				local class = { key = key, label = Text.Clean(row.LABEL, 48) or key }
				weaponClasses[#weaponClasses + 1] = class
				weaponClassIndex[key] = class
			end
		end
	end
end

Catalog.vehicleClasses = vehicleClasses
Catalog.weaponClasses = weaponClasses

--- @author DemiAutomatic
--- @method OpxAdmin.Catalog.Vehicle
--- @description Finds a vehicle row by name or exact record, without case.
--- @param token {any}
--- @returns {CatalogEntry|nil}
function OpxAdmin.Catalog.Vehicle(token)
	if type(token) ~= 'string' then return nil end
	local lowered = token:lower()
	return vehiclesByName[lowered] or vehiclesByRecord[lowered]
end
