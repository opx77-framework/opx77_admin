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

--- Index one data file into ordered classes and a lookup by name and by record.
---@param source table|nil        OPX_ADMIN_VEHICLES
---@param file string             for the problem lines
---@param list string             the key the rows live under
---@return table[] classes, table<string, CatalogEntry> byName, table<string, CatalogEntry> byRecord
local function build(source, file, list)
  local classes, classIndex, byName, byRecord = {}, {}, {}, {}
  if type(source) ~= "table" or type(source.CLASSES) ~= "table" then
    problem(file .. ": CLASSES must be a table")
    return classes, byName, byRecord
  end

  for position, row in ipairs(source.CLASSES) do
    local key = type(row) == "table" and Text.slug(row.KEY) or nil
    if key == nil or classIndex[key] ~= nil then
      problem(("%s: class #%d needs a unique KEY"):format(file, position))
    else
      local class = { key = key, label = Text.clean(row.LABEL, 48) or key, members = {} }
      classes[#classes + 1] = class
      classIndex[key] = class
    end
  end

  local rows = source[list]
  if type(rows) ~= "table" then
    problem(("%s: %s must be a table"):format(file, list))
    rows = {}
  end
  for position, row in ipairs(rows) do
    local where = ("%s: row #%d"):format(file, position)
    local name = type(row) == "table" and Text.slug(row.NAME) or nil
    local record = type(row) == "table" and type(row.RECORD) == "string"
      and row.RECORD:match("^[%w_%.]+$") and row.RECORD or nil
    local class = type(row) == "table" and classIndex[tostring(row.CLASS or "")] or nil
    if name == nil then
      problem(where .. ": NAME must be 1..32 letters, digits, _ or -")
    elseif record == nil then
      problem(where .. ": RECORD must be a TweakDB record name")
    elseif class == nil then
      problem(where .. ": CLASS is not a KEY in CLASSES")
    elseif byName[name] ~= nil or byRecord[record:lower()] ~= nil then
      problem(where .. ": NAME or RECORD is declared twice")
    else
      local entry = {
        name = name,
        label = Text.clean(row.LABEL, 48) or name,
        record = record,
        class = class.key,
      }
      class.members[#class.members + 1] = entry
      byName[name] = entry
      byRecord[record:lower()] = entry
    end
  end
  return classes, byName, byRecord
end

local vehicleClasses, vehiclesByName, vehiclesByRecord =
  build(OPX_ADMIN_VEHICLES, "data/vehicles.lua", "VEHICLES")

--- The weapon classes: an order, a label and the rounds a give loads. The weapons are
--- opx77_inventory's items and are read from it, so no row here names a record.
---@type WeaponClass[]
local weaponClasses = {}
local weaponClassIndex = {}
do
  local source = type(OPX_ADMIN_WEAPONS) == "table" and OPX_ADMIN_WEAPONS or nil
  if source == nil or type(source.CLASSES) ~= "table" then
    problem("data/weapons.lua: CLASSES must be a table")
  else
    for position, row in ipairs(source.CLASSES) do
      local key = type(row) == "table" and Text.slug(row.KEY) or nil
      if key == nil or weaponClassIndex[key] ~= nil then
        problem(("data/weapons.lua: class #%d needs a unique KEY"):format(position))
      else
        local class = {
          key = key,
          label = Text.clean(row.LABEL, 48) or key,
          rounds = row.ROUNDS ~= nil and math.max(0, Text.integer(row.ROUNDS) or 0) or nil,
        }
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
  if type(token) ~= "string" then return nil end
  local lowered = token:lower()
  return vehiclesByName[lowered] or vehiclesByRecord[lowered]
end

---@param key any
---@return WeaponClass|nil
function Catalog.weaponClass(key)
  return weaponClassIndex[tostring(key or "")]
end
