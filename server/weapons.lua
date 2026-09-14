--- Weapon commands. A weapon is an opx77_inventory item: a unit in a bag carrying a serial and its
--- rounds, which the player draws by using it. So a give adds that item, a refill raises the
--- rounds it carries, a removal takes the item, and a read lists the weapon items and which one is
--- drawn -- all through the inventory's server exports (server/inventory.lua), never by putting
--- a record in a game slot. The inventory takes off, every WEAPONS.SCAN_MS, any weapon a bag does
--- not back, so a weapon handed over any other way would not last, and would not be recorded.
---
--- Two things stay on `Open77.weapons`, the platform's relay to the target client's
--- open77_weapons half, because the inventory has no export for them and neither creates nor
--- removes a weapon: holstering, and stating the new rounds of the weapon the player has drawn,
--- whose item the inventory otherwise lowers again to what the engine reads back. A relay step
--- answers in two halves: `open77:weapons:completed` carries the client's verdict.

local Server = OpxAdmin.Server
local Catalog = OpxAdmin.Catalog
local Inventory = OpxAdmin.Inventory
local Text = OpxAdmin.Text

local answer, refuse, audit, tell = Server.answer, Server.refuse, Server.audit, Server.tell

--- tostring(requestId) -> the step a completion resumes.
local pending = {}

--- A relay that never answers is a timeout on the platform's side; this bounds the table in
--- case the completion never reaches this VM at all.
local PENDING_MS = 30000

---@return boolean
local function available()
  local weapons = Open77.weapons
  return type(weapons) == "table" and type(weapons.holster) == "function"
    and type(weapons.setAmmo) == "function" and type(weapons.requestSnapshot) == "function"
end

---@param requestId any
---@param step table
local function remember(requestId, step)
  step.atMs = Server.nowMs()
  pending[tostring(requestId)] = step
end

--- The rounds a weapon item carries after a give or a refill: what was typed, else the class's
--- ROUNDS for a give and a full load for a refill, never past its ammunition's MAX.
---@param catalog table
---@param entry table     a weapon item of the inventory's catalogue
---@param typed integer|nil
---@param full boolean    a refill: the ammunition's MAX when nothing was typed
---@return integer rounds, boolean takesAmmo
local function roundsFor(catalog, entry, typed, full)
  local ammo = entry.weapon and entry.weapon.ammo and catalog.byName[entry.weapon.ammo] or nil
  local max = ammo and ammo.ammoMax or nil
  if max == nil then return 0, false end
  local class = Catalog.weaponClass(entry.weapon.class)
  local wanted = typed or ((not full and class and class.rounds) or max)
  return math.max(0, math.min(wanted, max)), true
end

--- A typed round count: nil when omitted, false when it is not a whole number from 0.
---@param token any
---@return integer|false|nil
local function typedRounds(token)
  if token == nil then return nil end
  local rounds = Text.integer(token)
  if rounds == nil or rounds < 0 then return false end
  return rounds
end

---@param metadata table|nil
---@return table
local function copy(metadata)
  local out = {}
  for key, value in pairs(type(metadata) == "table" and metadata or {}) do out[key] = value end
  return out
end

--- The weapon drawn from this player's bag, or nil. Coroutine only.
---@param playerId integer|nil
---@return table|nil
local function drawnOf(playerId)
  if playerId == nil then return nil end
  local held = Inventory.call("GetHeldWeapon", playerId)
  local weapon = held and type(held.weapon) == "table" and held.weapon or nil
  if weapon == nil or weapon.drawn ~= true or type(weapon.serial) ~= "string" then return nil end
  return weapon
end

-- ---------------------------------------------------------------------------
-- The relay half of a refill
-- ---------------------------------------------------------------------------

--- Writes the refill of the drawn weapon's item, once the engine holds those rounds. Coroutine
--- only.
---@param step table
local function writeDrawn(step)
  local set, code, reason = Inventory.call("SetMetadata", step.target, step.slot, step.metadata)
  if not set then
    return Inventory.fail(step.source, step.raw, "admin.weapon.ammo", step.playerId, step.who, code,
      reason)
  end
  audit(step.source, "admin.weapon.ammo", true, step.playerId,
    ("%s drawn, slot %d, %d rounds"):format(step.name, step.slot, step.rounds))
  answer(step.source, step.raw, true, "admin.done.drawnRefilled",
    { label = step.label, who = step.who, rounds = step.rounds })
end

--- The drawn weapon's rounds are stated to the engine first and written to the item after:
--- the inventory lowers an item to what it reads back, never raises it, so an item raised first
--- would be lowered again by the next reading.
---@param step table
local function refillDrawn(step)
  local admitted = Server.admit(step.playerId)
  if not available() or not admitted then
    -- nothing can be drawn on a client that is not in the world: the item alone is the state
    return CreateThread(function() writeDrawn(step) end)
  end
  local requestId, reason = Open77.weapons.requestSnapshot(step.playerId)
  if requestId == nil then
    audit(step.source, "admin.weapon.ammo", false, step.playerId, tostring(reason))
    return refuse(step.source, step.raw, "refused", { reason = tostring(reason) })
  end
  step.kind = "drawnRead"
  remember(requestId, step)
end

AddEventHandler("open77:weapons:completed", function(playerId, requestId, operation, accepted,
                                                     reason, result)
  local key = tostring(requestId)
  local step = pending[key]
  if step == nil then return end
  pending[key] = nil
  if tonumber(playerId) ~= step.playerId then return end

  if accepted ~= true then
    local code = tostring(reason) == "request_timeout" and "weapon_no_answer" or "refused"
    audit(step.source, "admin.weapon." .. step.command, false, step.playerId,
      ("%s: %s"):format(step.kind, tostring(reason)))
    return refuse(step.source, step.raw, code, { reason = tostring(reason), id = step.playerId })
  end

  if step.kind == "holster" then
    audit(step.source, "admin.weapon.holster", true, step.playerId)
    return answer(step.source, step.raw, true, "admin.done.holstered", { id = step.playerId })
  end

  if step.kind == "drawnRead" then
    local row
    for _, each in ipairs(type(result) == "table" and result or {}) do
      if type(each) == "table" and each.equipped == true and type(each.record) == "string" and
        each.record:lower() == step.record:lower() then
        row = each
      end
    end
    local slot = row and Text.integer(row.slot) or nil
    if slot == nil then
      -- put away meanwhile: the item alone is the state again
      return CreateThread(function() writeDrawn(step) end)
    end
    local ammo = type(row.ammo) == "table" and row.ammo or {}
    local capacity = Text.integer(ammo.capacity)
    local amounts = { activate = true }
    if capacity and capacity > 0 then
      amounts.magazine = math.min(step.rounds, capacity)
      amounts.reserve = step.rounds - amounts.magazine
    else
      amounts.reserve = step.rounds
    end
    local loadId, loadReason = Open77.weapons.setAmmo(step.playerId, slot, amounts)
    if loadId == nil then
      audit(step.source, "admin.weapon.ammo", false, step.playerId, tostring(loadReason))
      return refuse(step.source, step.raw, "refused", { reason = tostring(loadReason) })
    end
    step.kind = "drawnLoad"
    return remember(loadId, step)
  end

  if step.kind == "drawnLoad" then
    return CreateThread(function() writeDrawn(step) end)
  end
end)

CreateThread(function()
  while true do
    Wait(10000)
    local atMs = Server.nowMs()
    for key, step in pairs(pending) do
      if atMs - (step.atMs or atMs) > PENDING_MS then pending[key] = nil end
    end
  end
end)

-- ---------------------------------------------------------------------------
-- The commands
-- ---------------------------------------------------------------------------

local TARGET = { name = "playerId|me|citizenId", help = "admin.help.holder" }

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

Server.command("opx77.admin.weapon.give", {
  help = "admin.help.giveWeapon",
  params = { TARGET,
             { name = "weapon", help = "admin.help.weaponName" },
             { name = "rounds", help = "admin.help.rounds", optional = true } },
  handler = function(source, args, raw)
    if Text.clean(args[2], 48) == nil then return refuse(source, raw, "unknown_weapon") end
    local typed = typedRounds(args[3])
    if typed == false then return refuse(source, raw, "bad_number") end
    local target, who, playerId = resolve(source, raw, args[1])
    if target == nil then return end
    CreateThread(function()
      local event = "admin.weapon.give"
      local catalog, code, reason = Inventory.catalog()
      if not catalog then return Inventory.fail(source, raw, event, playerId, who, code, reason) end
      local entry = Inventory.weapon(catalog, args[2])
      if entry == nil then
        return Inventory.fail(source, raw, event, playerId, who, "unknown_weapon",
          Text.clean(args[2], 48))
      end
      local rounds, takesAmmo = roundsFor(catalog, entry, typed or nil, false)
      -- the serial is the inventory's to give; the rounds are carried on the item
      local metadata = takesAmmo and { ammo = rounds } or nil
      if not Inventory.give(source, raw, event, target, who, playerId, entry.name, 1, metadata,
        entry.label) then
        return
      end
      audit(source, event, true, playerId, ("%s to %s, %d rounds"):format(entry.name, who, rounds))
      if playerId and playerId ~= source then
        tell(playerId, "admin.toast.weapon", { label = entry.label }, "success")
      end
      answer(source, raw, true, takesAmmo and "admin.done.weaponGiven" or "admin.done.meleeGiven",
        { label = entry.label, who = who, rounds = rounds })
    end)
  end,
})

Server.command("opx77.admin.weapon.ammo", {
  help = "admin.help.ammo",
  params = { TARGET,
             { name = "weapon|all", help = "admin.help.weaponOrAllOptional", optional = true },
             { name = "rounds", help = "admin.help.refillRounds", optional = true } },
  handler = function(source, args, raw)
    local all = args[2] == nil or tostring(args[2]):lower() == "all"
    local typed = typedRounds(args[3])
    if typed == false then return refuse(source, raw, "bad_number") end
    local target, who, playerId = resolve(source, raw, args[1])
    if target == nil then return end
    CreateThread(function()
      local event = "admin.weapon.ammo"
      local catalog, code, reason = Inventory.catalog()
      if not catalog then return Inventory.fail(source, raw, event, playerId, who, code, reason) end
      local only
      if not all then
        only = Inventory.weapon(catalog, args[2])
        if only == nil then
          return Inventory.fail(source, raw, event, playerId, who, "unknown_weapon",
            Text.clean(args[2], 48))
        end
      end
      local bag, bagCode, bagReason = Inventory.bag(target)
      if not bag then
        return Inventory.fail(source, raw, event, playerId, who, bagCode, bagReason)
      end
      local drawn = drawnOf(playerId)

      local refilled, drawnStep, failure = 0, nil, nil
      for _, row in ipairs(bag.items) do
        local entry = catalog.byName[row.name]
        if entry and entry.weapon and (only == nil or only.name == entry.name) then
          local rounds, takesAmmo = roundsFor(catalog, entry, typed or nil, true)
          if takesAmmo then
            local metadata = copy(row.metadata)
            metadata.ammo = rounds
            if drawn and metadata.serial == drawn.serial then
              drawnStep = { command = "ammo", source = source, raw = raw, target = target,
                            who = who, playerId = playerId, slot = row.slot, name = entry.name,
                            label = entry.label, record = tostring(drawn.record or ""),
                            rounds = rounds, metadata = metadata }
            else
              local set, setCode, setReason = Inventory.call("SetMetadata", target, row.slot,
                metadata)
              if set then
                refilled = refilled + 1
              else
                failure = { code = setCode, reason = setReason }
              end
            end
          end
        end
      end

      if refilled == 0 and drawnStep == nil then
        if failure then
          return Inventory.fail(source, raw, event, playerId, who, failure.code, failure.reason)
        end
        return answer(source, raw, false, "admin.done.nothingToRefill", { who = who }, "warning")
      end
      if refilled > 0 then
        audit(source, event, true, playerId, ("%d weapon item(s) of %s"):format(refilled, who))
        answer(source, raw, true, "admin.done.refilled", { count = refilled, who = who })
      end
      if drawnStep then refillDrawn(drawnStep) end
    end)
  end,
})

Server.command("opx77.admin.weapon.remove", {
  help = "admin.help.removeWeapon",
  params = { TARGET, { name = "weapon|all", help = "admin.help.weaponOrAll" } },
  handler = function(source, args, raw)
    -- no default: taking every weapon is never what a forgotten argument meant
    if Text.clean(args[2], 48) == nil then return refuse(source, raw, "unknown_weapon") end
    local all = tostring(args[2]):lower() == "all"
    local target, who, playerId = resolve(source, raw, args[1])
    if target == nil then return end
    CreateThread(function()
      local event = "admin.weapon.remove"
      local catalog, code, reason = Inventory.catalog()
      if not catalog then return Inventory.fail(source, raw, event, playerId, who, code, reason) end
      local only
      if not all then
        only = Inventory.weapon(catalog, args[2])
        if only == nil then
          return Inventory.fail(source, raw, event, playerId, who, "unknown_weapon",
            Text.clean(args[2], 48))
        end
      end
      local bag, bagCode, bagReason = Inventory.bag(target)
      if not bag then
        return Inventory.fail(source, raw, event, playerId, who, bagCode, bagReason)
      end

      -- by name and count, not by slot: a slot read a moment ago may hold something else now
      local counts, order = {}, {}
      for _, row in ipairs(bag.items) do
        local entry = catalog.byName[row.name]
        if entry and entry.weapon and (only == nil or only.name == entry.name) then
          if counts[row.name] == nil then order[#order + 1] = row.name end
          counts[row.name] = (counts[row.name] or 0) + row.count
        end
      end
      if #order == 0 then
        return answer(source, raw, false, "admin.done.noWeapons", { who = who }, "warning")
      end
      local removed, failure = 0, nil
      for _, name in ipairs(order) do
        local taken, takeCode, takeReason = Inventory.call("RemoveItem", target, name, counts[name])
        if taken then
          removed = removed + counts[name]
        else
          failure = { code = takeCode, reason = takeReason }
        end
      end
      if removed == 0 then
        return Inventory.fail(source, raw, event, playerId, who, failure.code, failure.reason)
      end
      -- the inventory puts a drawn weapon away itself once its item has left the bag
      audit(source, event, true, playerId, ("%d weapon(s) from %s%s"):format(removed, who,
        failure and (", then " .. tostring(failure.reason)) or ""))
      if playerId and playerId ~= source then
        tell(playerId, "admin.toast.weaponsTaken", { count = removed }, "warning")
      end
      answer(source, raw, true, "admin.done.weaponsRemoved", { count = removed, who = who })
    end)
  end,
})

Server.command("opx77.admin.weapon.holster", {
  help = "admin.help.holster",
  params = { { name = "playerId|me", help = "admin.help.playerOrMe" } },
  handler = function(source, args, raw)
    if not available() then return refuse(source, raw, "weapons_unavailable") end
    local playerId, code = Server.target(source, args[1])
    if playerId == nil then return refuse(source, raw, code) end
    -- asking an unincarnated client for its loadout is asking the menu puppet
    local admitted, gateCode = Server.admit(playerId)
    if not admitted then
      audit(source, "admin.weapon.holster", false, playerId, gateCode)
      return refuse(source, raw, gateCode, { id = playerId })
    end
    local requestId, reason = Open77.weapons.holster(playerId)
    if requestId == nil then
      return refuse(source, raw, "refused", { reason = tostring(reason) })
    end
    remember(requestId, { command = "holster", kind = "holster", source = source, raw = raw,
                          playerId = playerId })
  end,
})

Server.command("opx77.admin.weapon.read", {
  help = "admin.help.loadout", params = { TARGET }, read = true,
  handler = function(source, args, raw)
    local target, who, playerId = resolve(source, raw, args[1])
    if target == nil then return end
    CreateThread(function()
      local event = "admin.weapon.read"
      local catalog, code, reason = Inventory.catalog()
      if not catalog then return Inventory.fail(source, raw, event, playerId, who, code, reason) end
      local bag, bagCode, bagReason = Inventory.bag(target)
      if not bag then
        return Inventory.fail(source, raw, event, playerId, who, bagCode, bagReason)
      end
      local drawn = drawnOf(playerId)
      local lines = { locale("admin.loadout.header", { who = who }) }
      for _, row in ipairs(bag.items) do
        local entry = catalog.byName[row.name]
        if entry and entry.weapon then
          local metadata = type(row.metadata) == "table" and row.metadata or {}
          local serial = Text.clean(metadata.serial, 24) or "-"
          local rounds = entry.weapon.ammo and ("  " .. locale("admin.inventory.rounds",
            { rounds = Text.integer(metadata.ammo) or 0 })) or ""
          local mark = drawn and metadata.serial == drawn.serial and
            ("  " .. locale("admin.loadout.drawn")) or ""
          lines[#lines + 1] = locale("admin.loadout.row", { slot = row.slot, label = entry.label,
            serial = serial, rounds = rounds, drawn = mark })
        end
      end
      if #lines == 1 then lines[2] = locale("admin.loadout.empty") end
      answer(source, raw, true, "admin.text.lines", { lines = table.concat(lines, "\n") })
    end)
  end,
})

--- Whether the relay the holster and a drawn weapon's refill use exists on this host.
---@return boolean
function Server.weaponsAvailable()
  return available()
end

if not available() then
  Open77.log.warn("Open77.weapons is unavailable on this host: holster refuses, and a refill " ..
    "writes the drawn weapon's item without loading it in hand")
end
