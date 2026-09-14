--- Weapon commands: give a catalogue weapon loaded, refill, clear a slot, holster, and read a
--- loadout back.
---
--- A loadout is the target client's own engine state. `Open77.weapons.*` on the server relays a
--- request to that one client and later raises `open77:weapons:completed` in this VM with the
--- answer, so every command here answers in two halves: "asked" now, the verdict when the
--- client replies. The client half that does the work belongs to the platform's
--- `open77_weapons` resource; without it running, every request completes as a timeout.
---
--- The server decides (only catalogue records are ever forwarded) and remembers what it asked
--- for. It cannot verify the client: the counts that come back are that client's own reading.

local Config = OPX_ADMIN_CONFIG
local Server = OpxAdmin.Server
local Catalog = OpxAdmin.Catalog
local Text = OpxAdmin.Text

local answer, refuse, audit, tell = Server.answer, Server.refuse, Server.audit, Server.tell

local Settings = Config.WEAPONS or {}
local SLOTS = 3

--- tostring(requestId) -> the step a completion resumes.
local pending = {}

--- A relay that never answers is a timeout on the platform's side; this bounds the table in
--- case the completion never reaches this VM at all.
local PENDING_MS = 30000

---@return boolean
local function available()
  local weapons = Open77.weapons
  return type(weapons) == "table" and type(weapons.assign) == "function"
    and type(weapons.setAmmo) == "function" and type(weapons.requestSnapshot) == "function"
end

---@param requestId any
---@param step table
local function remember(requestId, step)
  step.atMs = Server.nowMs()
  pending[tostring(requestId)] = step
end

--- A typed reserve, clamped to MAX_RESERVE, or the class's own.
---@param typed any
---@param class table|nil
---@return integer|nil reserve, boolean valid
local function reserveOf(typed, class)
  local ceiling = math.max(0, math.floor(Server.setting(Settings.MAX_RESERVE, 2000)))
  if typed ~= nil then
    local amount = Text.integer(typed)
    if amount == nil or amount < 0 then return nil, false end
    return math.min(amount, ceiling), true
  end
  return math.min(class and class.reserve or 0, ceiling), true
end

--- `1`..`3`, or `auto`.
---@param token any
---@return integer|string|nil
local function slotOf(token)
  if token == nil or tostring(token):lower() == "auto" then return "auto" end
  local slot = Text.integer(token)
  if slot == nil or slot < 1 or slot > SLOTS then return nil end
  return slot
end

--- The first empty unlocked slot, or the active one when all three are full. A give never
--- silently displaces a weapon the player was not holding.
---@param rows table
---@return integer
local function chooseSlot(rows)
  local empty, active
  for _, row in ipairs(type(rows) == "table" and rows or {}) do
    local slot = Text.integer(row.slot)
    if slot and slot >= 1 and slot <= SLOTS and row.locked ~= true then
      if row.equipped ~= true and empty == nil then empty = slot end
      if row.active == true and active == nil then active = slot end
    end
  end
  return empty or active or 1
end

--- "12/30 +300" from the engine's own ammo reading, or "".
---@param ammo any
---@return string
local function ammoText(ammo)
  if type(ammo) ~= "table" then return "" end
  local magazine, capacity, reserve = Text.integer(ammo.magazine), Text.integer(ammo.capacity),
    Text.integer(ammo.reserve)
  if magazine and capacity and reserve then
    return ("%d/%d +%d"):format(magazine, capacity, reserve)
  end
  local total = Text.integer(ammo.total)
  return total and tostring(total) or ""
end

---@param step table
---@param ammo table|nil
local function finishGive(step, ammo)
  audit(step.source, "admin.weapon.give", true, step.target,
    ("%s slot %d %s"):format(step.entry.record, step.slot, ammoText(ammo)))
  if step.target ~= step.source then
    tell(step.target, "admin.toast.weapon", { label = step.entry.label }, "success")
  end
  answer(step.source, step.raw, true, "admin.done.weaponGiven", {
    label = step.entry.label, id = step.target, slot = step.slot,
    ammo = ammoText(ammo) ~= "" and ammoText(ammo) or "-",
  })
end

---@param step table
---@param code string
---@param reason any
local function failStep(step, code, reason)
  audit(step.source, "admin.weapon." .. step.command, false, step.target,
    ("%s: %s"):format(step.kind, tostring(reason)))
  refuse(step.source, step.raw, code, { reason = tostring(reason), id = step.target })
end

---@param step table
local function assign(step)
  local requestId, reason = Open77.weapons.assign(step.target, step.entry.record, step.slot,
    { active = true, addToInventory = true })
  if requestId == nil then return failStep(step, "refused", reason) end
  step.kind = "assign"
  remember(requestId, step)
end

---@param step table
---@param magazine integer|nil
local function loadAmmo(step, magazine)
  local amounts = { reserve = step.reserve, activate = true }
  if magazine then amounts.magazine = magazine end
  local requestId, reason = Open77.weapons.setAmmo(step.target, step.slot, amounts)
  if requestId == nil then return failStep(step, "refused", reason) end
  step.kind = magazine and (step.command == "give" and "magazine" or "refillMagazine")
    or (step.command == "give" and "reserve" or "refill")
  remember(requestId, step)
end

--- Top the magazine up once, from the capacity the engine just reported; asking for more than
--- the weapon holds is refused, so it is never guessed.
---@return boolean asked
local function topUp(step, ammo)
  if Settings.FILL_MAGAZINE == false or step.toppedUp or type(ammo) ~= "table" then
    return false
  end
  local capacity, magazine = Text.integer(ammo.capacity), Text.integer(ammo.magazine)
  if capacity == nil or capacity <= 0 or magazine == nil or magazine >= capacity then
    return false
  end
  step.toppedUp = true
  loadAmmo(step, capacity)
  return true
end

--- Every step of every chain resumes here. The relay has already matched the request id to
--- the session that answered, so a row found in `pending` is ours.
AddEventHandler("open77:weapons:completed", function(playerId, requestId, operation, accepted,
                                                     reason, result)
  local key = tostring(requestId)
  local step = pending[key]
  if step == nil then return end
  pending[key] = nil
  if tonumber(playerId) ~= step.target then return end
  result = type(result) == "table" and result or {}

  if accepted ~= true then
    if step.kind == "magazine" then
      -- the spare rounds are already in and the weapon fires; only the last rounds were refused
      return finishGive(step, result.ammo)
    end
    local code = tostring(reason) == "request_timeout" and "weapon_no_answer" or "refused"
    return failStep(step, code, reason)
  end

  if step.kind == "pick" then
    step.slot = chooseSlot(result)
    return assign(step)
  end

  if step.kind == "assign" then
    -- the slot the engine reports wins over the one asked for: the ammo follows the weapon
    step.slot = Text.integer(result.slot) or step.slot
    if not step.class.ammo or step.reserve <= 0 then return finishGive(step, nil) end
    return loadAmmo(step, nil)
  end

  if step.kind == "reserve" then
    if topUp(step, result.ammo) then return end
    return finishGive(step, result.ammo)
  end

  if step.kind == "magazine" then return finishGive(step, result.ammo) end

  if step.kind == "refill" or step.kind == "refillMagazine" then
    if step.kind == "refill" and topUp(step, result.ammo) then return end
    audit(step.source, "admin.weapon.ammo", true, step.target,
      ("slot %d %s"):format(step.slot, ammoText(result.ammo)))
    return answer(step.source, step.raw, true, "admin.done.refilled",
      { id = step.target, slot = step.slot, ammo = ammoText(result.ammo) })
  end

  if step.kind == "refillPick" then
    local asked = 0
    for _, row in ipairs(result) do
      local slot = Text.integer(row.slot)
      if slot and row.equipped == true and (step.only == nil or step.only == slot) then
        local _, class = Catalog.weapon(type(row.record) == "string" and row.record or nil)
        -- a weapon outside the catalogue has no known class: a typed reserve still loads it
        if (class and class.ammo) or (class == nil and step.typedReserve ~= nil) then
          local reserve = reserveOf(step.typedReserve, class)
          loadAmmo({ command = "ammo", kind = "refill", source = step.source, raw = step.raw,
                 target = step.target, slot = slot, reserve = reserve }, nil)
          asked = asked + 1
        end
      end
    end
    if asked == 0 then
      return answer(step.source, step.raw, false, "admin.done.nothingToRefill",
        { id = step.target })
    end
    return
  end

  if step.kind == "remove" then
    audit(step.source, "admin.weapon.remove", true, step.target, ("slot %d"):format(step.slot))
    if step.quiet then return end
    return answer(step.source, step.raw, true, "admin.done.slotCleared",
      { id = step.target, slot = step.slot })
  end

  if step.kind == "holster" then
    audit(step.source, "admin.weapon.holster", true, step.target)
    return answer(step.source, step.raw, true, "admin.done.holstered", { id = step.target })
  end

  if step.kind == "read" then
    local lines = { locale("admin.loadout.header",
      { id = step.target, name = Server.nameOf(step.target) or "?" }) }
    for slot = 1, SLOTS do
      local found
      for _, row in ipairs(result) do
        if Text.integer(row.slot) == slot then found = row end
      end
      if found == nil or found.equipped ~= true then
        lines[#lines + 1] = locale("admin.loadout.empty", { slot = slot })
      else
        local record = type(found.record) == "string" and found.record ~= "" and found.record or nil
        local entry = record and Catalog.weapon(record) or nil
        lines[#lines + 1] = locale(found.active and "admin.loadout.active" or "admin.loadout.row", {
          slot = slot,
          label = entry and entry.label or record or tostring(found.tweakDbId or "?"),
          ammo = ammoText(found.ammo),
        })
      end
    end
    return answer(step.source, step.raw, true, "admin.text.lines",
      { lines = table.concat(lines, "\n") })
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

--- Resolve target and gate for a weapon command, or answer why not.
---@return integer|nil
local function armable(source, raw, token, event)
  if not available() then
    refuse(source, raw, "weapons_unavailable")
    return nil
  end
  local playerId, code = Server.target(source, token)
  if playerId == nil then
    refuse(source, raw, code)
    return nil
  end
  -- asking an unincarnated client for its loadout is asking the menu puppet
  local admitted, gateCode = Server.admit(playerId)
  if not admitted then
    audit(source, event, false, playerId, gateCode)
    refuse(source, raw, gateCode, { id = playerId })
    return nil
  end
  return playerId
end

Server.command("opx77.admin.weapon.give", {
  help = "admin.help.giveWeapon",
  params = { { name = "playerId|me" }, { name = "weapon", help = "admin.help.weaponName" },
             { name = "slot", help = "admin.help.slot" }, { name = "reserve" } },
  handler = function(source, args, raw)
    local entry, class = Catalog.weapon(args[2])
    if entry == nil then return refuse(source, raw, "unknown_weapon") end
    local slot = slotOf(args[3])
    if slot == nil then return refuse(source, raw, "bad_slot") end
    local reserve, valid = reserveOf(args[4], class)
    if not valid then return refuse(source, raw, "bad_number") end
    local playerId = armable(source, raw, args[1], "admin.weapon.give")
    if playerId == nil then return end

    local step = { command = "give", source = source, raw = raw, target = playerId,
                   entry = entry, class = class, reserve = reserve }
    if slot == "auto" then
      local requestId, reason = Open77.weapons.requestSnapshot(playerId)
      if requestId == nil then return failStep(step, "refused", reason) end
      step.kind = "pick"
      remember(requestId, step)
    else
      step.slot = slot
      assign(step)
    end
    answer(source, raw, true, "admin.done.weaponAsked", { label = entry.label, id = playerId })
  end,
})

Server.command("opx77.admin.weapon.ammo", {
  help = "admin.help.ammo",
  params = { { name = "playerId|me" }, { name = "slot|all" }, { name = "reserve" } },
  handler = function(source, args, raw)
    local all = args[2] == nil or tostring(args[2]):lower() == "all"
    local slot = not all and Text.integer(args[2]) or nil
    if not all and (slot == nil or slot < 1 or slot > SLOTS) then
      return refuse(source, raw, "bad_slot")
    end
    local typed = args[3]
    if typed ~= nil and select(2, reserveOf(typed, nil)) == false then
      return refuse(source, raw, "bad_number")
    end
    local playerId = armable(source, raw, args[1], "admin.weapon.ammo")
    if playerId == nil then return end

    -- the loadout is read first either way: the class, and so the reserve, follows the record
    local requestId, reason = Open77.weapons.requestSnapshot(playerId)
    local step = { command = "ammo", kind = "refillPick", source = source, raw = raw,
                   target = playerId, typedReserve = typed }
    if requestId == nil then return failStep(step, "refused", reason) end
    step.only = slot -- nil for every slot; the snapshot is filtered on the way back
    remember(requestId, step)
  end,
})

Server.command("opx77.admin.weapon.remove", {
  help = "admin.help.removeWeapon",
  params = { { name = "playerId|me" }, { name = "slot|all" } },
  handler = function(source, args, raw)
    -- no default: clearing all three slots is never what a forgotten argument meant
    if args[2] == nil then return refuse(source, raw, "bad_slot") end
    local all = tostring(args[2]):lower() == "all"
    local slot = not all and Text.integer(args[2]) or nil
    if not all and (slot == nil or slot < 1 or slot > SLOTS) then
      return refuse(source, raw, "bad_slot")
    end
    local playerId = armable(source, raw, args[1], "admin.weapon.remove")
    if playerId == nil then return end
    local slots = all and { 1, 2, 3 } or { slot }
    for _, each in ipairs(slots) do
      -- the item stays in the inventory: this clears the slot, it does not confiscate
      local requestId, reason = Open77.weapons.remove(playerId, each)
      if requestId == nil then
        refuse(source, raw, "refused", { reason = tostring(reason) })
      else
        remember(requestId, { command = "remove", kind = "remove", source = source, raw = raw,
                              target = playerId, slot = each, quiet = all })
      end
    end
    if all then answer(source, raw, true, "admin.done.slotsCleared", { id = playerId }) end
  end,
})

Server.command("opx77.admin.weapon.holster", {
  help = "admin.help.holster", params = { { name = "playerId|me" } },
  handler = function(source, args, raw)
    local playerId = armable(source, raw, args[1], "admin.weapon.holster")
    if playerId == nil then return end
    local requestId, reason = Open77.weapons.holster(playerId)
    if requestId == nil then
      return refuse(source, raw, "refused", { reason = tostring(reason) })
    end
    remember(requestId, { command = "holster", kind = "holster", source = source, raw = raw,
                          target = playerId })
  end,
})

Server.command("opx77.admin.weapon.read", {
  help = "admin.help.loadout", params = { { name = "playerId|me" } }, read = true,
  handler = function(source, args, raw)
    local playerId = armable(source, raw, args[1], "admin.weapon.read")
    if playerId == nil then return end
    local requestId, reason = Open77.weapons.requestSnapshot(playerId)
    if requestId == nil then
      return refuse(source, raw, "refused", { reason = tostring(reason) })
    end
    remember(requestId, { command = "read", kind = "read", source = source, raw = raw,
                          target = playerId })
  end,
})

---@return boolean
function Server.weaponsAvailable()
  return available()
end

if not available() then
  Open77.log.warn("Open77.weapons is unavailable on this host: every weapon command refuses")
end

--- In a thread, not at file scope: a resource listed after this one is not running yet here.
CreateThread(function()
  Wait(5000)
  local read, state = pcall(GetResourceState, "open77_weapons")
  state = read and tostring(state or ""):lower() or ""
  if state ~= "running" and state ~= "starting" then
    Open77.log.warn("open77_weapons is not running: its client half answers weapon requests, " ..
      "so every weapon command will time out")
  end
end)
