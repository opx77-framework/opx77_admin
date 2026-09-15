---@meta

--- The index over data/vehicles.lua and data/weapons.lua, read by both halves.
OpxAdmin.Catalog = {}

--- Malformed data rows, one English line each, logged by the server at boot.
---@type string[]
OpxAdmin.Catalog.problems = {}

--- Vehicle rows each shared/catalog-<n>.lua part indexes.
---@type integer
OpxAdmin.Catalog.PART = 68

--- The vehicle classes in menu order, each with its indexed members.
---@type CatalogClass[]
OpxAdmin.Catalog.vehicleClasses = {}

--- The weapon classes in menu order.
---@type WeaponClass[]
OpxAdmin.Catalog.weaponClasses = {}

--- Indexes the next `count` vehicle rows into their classes and the name and record lookups.
---@param count integer
function OpxAdmin.Catalog.IndexVehicles(count) end

--- Indexes every vehicle row left; names it in `problems` when that is more than one part.
function OpxAdmin.Catalog.FinishVehicles() end

--- A vehicle row by the name staff type or by its exact record, without case.
---@param token any
---@return CatalogEntry|nil
function OpxAdmin.Catalog.Vehicle(token) end
