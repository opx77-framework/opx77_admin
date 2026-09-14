--- The bridge to opx77_inventory, and the staff commands on a character's bag.
---
--- opx77_inventory is the only authority on what a character carries, weapons included. Its
--- server exports take a player id or a citizen id, check every argument again, and write through
--- opx77_core; this resource is listed in its EXPORTS.WRITERS. So a staff action on a bag is a
--- command of this resource, gated by the host on `command.<name>` like every other one, whose
--- handler calls those exports and answers in this resource's own toasts and reports. Opening a
--- bag on a staff screen and listing an item's holders have no export: the menu drives the
--- inventory's own commands for those (LINKS), as it drives opx77_core's for a job or money.
---
--- Every call here awaits, so it runs in a thread of its own: a yield is not safe under the pcall
--- a command handler runs in.

local Config = OPX_ADMIN_CONFIG
local Server = OpxAdmin.Server
local Text = OpxAdmin.Text

local answer, refuse, audit, tell = Server.answer, Server.refuse, Server.audit, Server.tell

local Settings = type(Config.INVENTORY) == "table" and Config.INVENTORY or {}
local RESOURCE = type(Settings.RESOURCE) == "string" and Settings.RESOURCE:match("^[%w_%-%.]+$")
  and Settings.RESOURCE or "opx77_inventory"
local MAX_COUNT = math.max(1, math.floor(Server.setting(Settings.MAX_COUNT, 10000)))

local Inventory = {}
OpxAdmin.Inventory = Inventory

Inventory.RESOURCE = RESOURCE
Inventory.MAX_COUNT = MAX_COUNT

--- Host reasons that mean the inventory is not there to answer, rather than that it refused.
local UNAVAILABLE = {
  export_not_found = true,
  export_resource_unavailable = true,
  export_resource_stopped = true,
  resource_preparing = true,
  resource_stopping = true,
  export_timeout = true,
  promise_cancelled = true,
  not_running = true,
}

--- The inventory's refusal codes this resource answers in its own words. Any other one is
--- `refused`, with the inventory's code as the reason.
local CODES = {
  caller_denied = "inventory_denied",
  no_room = "bag_no_room",
  too_heavy = "bag_too_heavy",
  not_loaded = "no_character",
  no_character = "unknown_citizen",
  bad_target = "bad_holder",
  unknown_item = "unknown_item",
  not_enough = "not_enough",
  core_unavailable = "core_unavailable",
  bad_count = "bad_count",
}

---@return boolean
function Inventory.running()
  local read, state = pcall(GetResourceState, RESOURCE)
  return read and state == "running"
end

--- One call to an inventory server export. Coroutine only. Answers the result, or nil with this
--- resource's refusal code and the raw reason for the audit.
---@param name string
---@return table|nil result, string|nil code, string|nil reason
function Inventory.call(name, ...)
  if not Inventory.running() then return nil, "inventory_unavailable", "not_running" end
  local exported = Open77.exports
  if type(exported) ~= "table" or type(exported.call) ~= "function" then
    return nil, "inventory_unavailable", "no_exports"
  end
  -- the dispatch only: `await` below yields, and a yield is not safe under a pcall
  local dispatched, promise, reason = pcall(exported.call, RESOURCE, name, ...)
  if not dispatched then return nil, "refused", Text.clean(promise, 64) end
  -- tested for presence, never for its Lua type: the host's promise is userdata
  if not promise then
    reason = tostring(reason or "not_dispatched")
    return nil, UNAVAILABLE[reason] and "inventory_unavailable" or "refused", reason
  end
  local result, callError = promise:await()
  if callError then
    callError = tostring(callError)
    return nil, UNAVAILABLE[callError] and "inventory_unavailable" or "refused",
      Text.clean(callError, 64)
  end
  if type(result) ~= "table" then return nil, "refused", "malformed_answer" end
  if result.ok ~= true then
    local code = Text.clean(result.error, 64) or "refused"
    return nil, CODES[code] or "refused", code
  end
  return result, nil, nil
end

-- ---------------------------------------------------------------------------
-- Targets
-- ---------------------------------------------------------------------------

--- `name [id]` for a connected player, the citizen id otherwise.
---@param playerId integer
---@return string
local function playerLabel(playerId)
  return ("%s [%d]"):format(Server.nameOf(playerId) or "?", playerId)
end

--- What was typed for a bag: `me`, a connected player id, or a citizen id, which also reaches a
--- character that is not in the world. The inventory resolves and checks the citizen id itself.
---@param source integer
---@param token any
---@return integer|string|nil target, string|nil who, integer|nil playerId, string|nil code
function Inventory.target(source, token)
  if token == nil then return nil, nil, nil, "no_target" end
  local word = tostring(token)
  local lowered = word:lower()
  if lowered == "me" or lowered == "self" then
    if source <= 0 then return nil, nil, nil, "console_has_no_player" end
    return source, playerLabel(source), source, nil
  end
  local playerId = Text.integer(word)
  if playerId ~= nil then
    if playerId <= 0 then return nil, nil, nil, "bad_holder" end
    if Server.nameOf(playerId) == nil then return nil, nil, nil, "not_connected" end
    return playerId, playerLabel(playerId), playerId, nil
  end
  if #word > 32 or not word:match("^[%w_%-]+$") then return nil, nil, nil, "bad_holder" end
  return word, word, nil, nil
end

--- A typed count: 1 when omitted, otherwise a whole number in 1..MAX_COUNT.
---@param token any
---@return integer|nil
function Inventory.count(token)
  if token == nil then return 1 end
  local count = Text.integer(token)
  if count == nil or count < 1 or count > MAX_COUNT then return nil end
  return count
end

-- ---------------------------------------------------------------------------
-- The catalogue
-- ---------------------------------------------------------------------------

--- The inventory's catalogue, read through GetItems and kept until the inventory starts or stops
--- again. It is data/items.lua and data/weapons.lua of that resource and changes only with it.
---@type { items: table[], byName: table<string, table>, atMs: integer }|nil
local cache
local CACHE_MS = 300000

local function forget(name)
  if name == RESOURCE then cache = nil end
end
AddEventHandler("open77:resource:started", forget)
AddEventHandler("open77:resource:stopped", forget)

--- Coroutine only.
---@return { items: table[], byName: table<string, table> }|nil, string|nil code, string|nil reason
function Inventory.catalog()
  if cache and Server.nowMs() - cache.atMs < CACHE_MS and Inventory.running() then return cache end
  local items, byName, offset = {}, {}, 0
  for _ = 1, 64 do
    local page, code, reason = Inventory.call("GetItems", { offset = offset })
    if not page then return nil, code, reason end
    for _, item in ipairs(type(page.items) == "table" and page.items or {}) do
      local name = type(item) == "table" and Text.clean(item.name, 48) or nil
      if name and byName[name] == nil then
        local weapon = type(item.weapon) == "table" and item.weapon or nil
        local entry = {
          name = name,
          label = Text.clean(item.label, 48) or name,
          category = Text.clean(item.category, 32) or "misc",
          weight = math.max(0, Text.integer(item.weight) or 0),
          weapon = weapon and {
            class = Text.clean(weapon.class, 32) or "other",
            ammo = Text.clean(weapon.ammo, 48),
          } or nil,
          ammoMax = type(item.ammo) == "table" and Text.integer(item.ammo.max) or nil,
        }
        items[#items + 1] = entry
        byName[name] = entry
      end
    end
    local nextOffset = Text.integer(page.nextOffset)
    if nextOffset == nil or nextOffset <= offset then break end
    offset = nextOffset
  end
  table.sort(items, function(left, right) return left.label < right.label end)
  cache = { items = items, byName = byName, atMs = Server.nowMs() }
  return cache, nil, nil
end

--- A catalogue item by its exact name, without case.
---@param catalog table
---@param token any
---@return table|nil
function Inventory.item(catalog, token)
  if type(token) ~= "string" then return nil end
  return catalog.byName[token:lower()]
end

--- A weapon item by its name, or by the name without its `weapon_` prefix.
---@param catalog table
---@param token any
---@return table|nil
function Inventory.weapon(catalog, token)
  if type(token) ~= "string" then return nil end
  local lowered = token:lower()
  local entry = catalog.byName[lowered] or catalog.byName["weapon_" .. lowered]
  if entry == nil or entry.weapon == nil then return nil end
  return entry
end

--- A label for a stored item the catalogue may no longer carry.
---@param catalog table|nil
---@param name string
---@return string
function Inventory.labelOf(catalog, name)
  local entry = catalog and catalog.byName[name]
  return entry and entry.label or name
end

-- ---------------------------------------------------------------------------
-- A bag
-- ---------------------------------------------------------------------------

--- Every stack of a bag, page by page, in slot order. Coroutine only.
---@param target integer|string
---@return table|nil bag, string|nil code, string|nil reason
function Inventory.bag(target)
  local bag, offset = nil, 0
  for _ = 1, 64 do
    local page, code, reason = Inventory.call("GetInventory", target, { offset = offset })
    if not page then return nil, code, reason end
    bag = bag or {
      citizenId = Text.clean(page.citizenId, 32) or "?",
      slots = Text.integer(page.slots) or 0,
      maxWeight = Text.integer(page.maxWeight) or 0,
      weight = Text.integer(page.weight) or 0,
      items = {},
    }
    for _, row in ipairs(type(page.items) == "table" and page.items or {}) do
      local slot, name = type(row) == "table" and Text.integer(row.slot) or nil,
        type(row) == "table" and Text.clean(row.name, 48) or nil
      if slot and name then
        bag.items[#bag.items + 1] = {
          slot = slot, name = name, count = Text.integer(row.count) or 0,
          metadata = type(row.metadata) == "table" and row.metadata or nil,
        }
      end
    end
    local nextOffset = Text.integer(page.nextOffset)
    if nextOffset == nil or nextOffset <= offset then break end
    offset = nextOffset
  end
  return bag, nil, nil
end

--- A refusal, audited. `params` may carry the words the refusal is answered with.
---@param source integer
---@param raw string
---@param event string
---@param playerId integer|nil
---@param who string|nil
---@param code string
---@param reason string|nil
---@param params table|nil
function Inventory.fail(source, raw, event, playerId, who, code, reason, params)
  audit(source, event, false, playerId, ("%s: %s"):format(who or "-", tostring(reason or code)))
  params = params or {}
  params.who = params.who or who or "?"
  params.reason = reason
  params.max = params.max or MAX_COUNT
  refuse(source, raw, code, params)
end

--- CanCarry. Coroutine only. True when the bag takes those items; otherwise false, this
--- resource's refusal code and the raw reason.
---@return boolean carried, string|nil code, string|nil reason
function Inventory.carry(target, name, count, metadata)
  local carry, code, reason = Inventory.call("CanCarry", target, name, count, metadata)
  if not carry then return false, code, reason end
  if carry.result ~= true then
    return false, carry.reason == "too_heavy" and "bag_too_heavy" or "bag_no_room",
      Text.clean(carry.reason, 32)
  end
  return true, nil, nil
end

--- CanCarry, then AddItem, answering nothing. Coroutine only.
---@return boolean added, string|nil code, string|nil reason
function Inventory.add(target, name, count, metadata)
  local carried, code, reason = Inventory.carry(target, name, count, metadata)
  if not carried then return false, code, reason end
  local added, addCode, addReason = Inventory.call("AddItem", target, name, count, metadata)
  if not added then return false, addCode, addReason end
  return true, nil, nil
end

--- CanCarry, then AddItem. Coroutine only. True once the items are in the bag; otherwise the
--- refusal has been answered and audited.
---@return boolean
function Inventory.give(source, raw, event, target, who, playerId, name, count, metadata, label)
  local added, code, reason = Inventory.add(target, name, count, metadata)
  if not added then
    Inventory.fail(source, raw, event, playerId, who, code, reason, { item = label })
    return false
  end
  return true
end

-- ---------------------------------------------------------------------------
-- The commands
-- ---------------------------------------------------------------------------

local TARGET = { name = "playerId|me|citizenId", help = "admin.help.holder" }
local ITEM = { name = "item", help = "admin.help.itemName" }
local COUNT = { name = "count", help = "admin.help.count", optional = true }

--- The refusals that need no call, answered before a thread is started.
---@return integer|string|nil target, string|nil who, integer|nil playerId
local function resolve(source, raw, token)
  local target, who, playerId, code = Inventory.target(source, token)
  if target == nil then
    refuse(source, raw, code)
    return nil
  end
  if not Inventory.running() then
    refuse(source, raw, "inventory_unavailable")
    return nil
  end
  return target, who, playerId
end

---@param metadata table|nil
---@return string
local function extraOf(metadata)
  if type(metadata) ~= "table" then return "" end
  local parts = {}
  local ammo = Text.integer(metadata.ammo)
  if ammo then parts[#parts + 1] = locale("admin.inventory.rounds", { rounds = ammo }) end
  local serial = Text.clean(metadata.serial, 24)
  if serial then parts[#parts + 1] = "#" .. serial end
  return #parts > 0 and ("  " .. table.concat(parts, "  ")) or ""
end

---@param grams integer
---@return string
local function kilograms(grams)
  return ("%.1f"):format(grams / 1000)
end

Server.command("opx77.admin.inventory.view", {
  help = "admin.help.invView", params = { TARGET }, read = true,
  handler = function(source, args, raw)
    local target, who, playerId = resolve(source, raw, args[1])
    if target == nil then return end
    CreateThread(function()
      local bag, code, reason = Inventory.bag(target)
      if not bag then
        return Inventory.fail(source, raw, "admin.inventory.view", playerId, who, code, reason)
      end
      local catalog = Inventory.catalog()
      local lines = { locale("admin.inventory.header", {
        who = who, citizenId = bag.citizenId, used = #bag.items, slots = bag.slots,
        weight = kilograms(bag.weight), maxWeight = kilograms(bag.maxWeight),
      }) }
      for _, row in ipairs(bag.items) do
        lines[#lines + 1] = locale("admin.inventory.row", {
          slot = row.slot, label = Inventory.labelOf(catalog, row.name), name = row.name,
          count = row.count, extra = extraOf(row.metadata),
        })
      end
      if #bag.items == 0 then lines[#lines + 1] = locale("admin.inventory.empty") end
      -- somebody's belongings were read: that is worth a line, as the inventory's own search is
      audit(source, "admin.inventory.view", true, playerId, bag.citizenId)
      answer(source, raw, true, "admin.text.lines", { lines = table.concat(lines, "\n") })
    end)
  end,
})

Server.command("opx77.admin.inventory.give", {
  help = "admin.help.invGive", params = { TARGET, ITEM, COUNT },
  handler = function(source, args, raw)
    if Text.clean(args[2], 48) == nil then
      return refuse(source, raw, "unknown_item", { item = "?" })
    end
    local count = Inventory.count(args[3])
    if count == nil then return refuse(source, raw, "bad_count", { max = MAX_COUNT }) end
    local target, who, playerId = resolve(source, raw, args[1])
    if target == nil then return end
    CreateThread(function()
      local event = "admin.inventory.give"
      local catalog, code, reason = Inventory.catalog()
      if not catalog then return Inventory.fail(source, raw, event, playerId, who, code, reason) end
      local item = Inventory.item(catalog, args[2])
      if item == nil then
        return Inventory.fail(source, raw, event, playerId, who, "unknown_item",
          Text.clean(args[2], 48), { item = Text.clean(args[2], 48) })
      end
      if not Inventory.give(source, raw, event, target, who, playerId, item.name, count, nil,
        item.label) then
        return
      end
      audit(source, event, true, playerId, ("%dx %s to %s"):format(count, item.name, who))
      if playerId and playerId ~= source then
        tell(playerId, "admin.toast.itemGiven", { count = count, label = item.label }, "info")
      end
      answer(source, raw, true, "admin.done.itemGiven",
        { count = count, label = item.label, who = who })
    end)
  end,
})

Server.command("opx77.admin.inventory.remove", {
  help = "admin.help.invRemove", params = { TARGET, ITEM, COUNT },
  handler = function(source, args, raw)
    -- not only catalogue names: an item taken out of the catalogue stays in bags until removed
    local name = type(args[2]) == "string" and args[2]:lower() or nil
    if name == nil or #name > 48 or not name:match("^[%w_%-%.]+$") then
      return refuse(source, raw, "unknown_item", { item = Text.clean(args[2], 48) or "?" })
    end
    local count = Inventory.count(args[3])
    if count == nil then return refuse(source, raw, "bad_count", { max = MAX_COUNT }) end
    local target, who, playerId = resolve(source, raw, args[1])
    if target == nil then return end
    CreateThread(function()
      local event = "admin.inventory.remove"
      local label = Inventory.labelOf(Inventory.catalog(), name)
      local removed, code, reason = Inventory.call("RemoveItem", target, name, count)
      if not removed then
        return Inventory.fail(source, raw, event, playerId, who, code, reason,
          { item = label, count = count })
      end
      audit(source, event, true, playerId, ("%dx %s from %s"):format(count, name, who))
      if playerId and playerId ~= source then
        tell(playerId, "admin.toast.itemTaken", { count = count, label = label }, "warning")
      end
      answer(source, raw, true, "admin.done.itemRemoved",
        { count = count, label = label, who = who })
    end)
  end,
})

Server.command("opx77.admin.inventory.clear", {
  help = "admin.help.invClear", params = { TARGET },
  handler = function(source, args, raw)
    local target, who, playerId = resolve(source, raw, args[1])
    if target == nil then return end
    CreateThread(function()
      local event = "admin.inventory.clear"
      local cleared, code, reason = Inventory.call("ClearInventory", target)
      if not cleared then
        return Inventory.fail(source, raw, event, playerId, who, code, reason)
      end
      audit(source, event, true, playerId, who)
      if playerId and playerId ~= source then
        tell(playerId, "admin.toast.bagCleared", nil, "warning")
      end
      answer(source, raw, true, "admin.done.bagCleared", { who = who })
    end)
  end,
})

--- In a thread, not at file scope: a resource listed after this one is not running yet here.
CreateThread(function()
  Wait(5000)
  if not Inventory.running() then
    Open77.log.warn(("%s is not running: the weapon and inventory commands refuse until it is")
      :format(RESOURCE))
  end
end)
