--- The staff menu, drawn by opx77_menu. Every row that does something is a command line sent
--- through Client.execute, so the host resolves the ACL for it exactly as for a typed command.
--- The access map the server sends only greys out what would be refused; it decides nothing.
---
--- Each screen is its own opx77_menu `open`, not a submenu of one big tree: opx77_menu refuses a
--- spec past 400 rows across the whole tree, and a roster of thirty players with twenty actions
--- each is past it. The stack of screens is kept here instead.

OpxAdmin = OpxAdmin or {}

local Config = OPX_ADMIN_CONFIG
local Client = OpxAdmin.Client
local Catalog = OpxAdmin.Catalog
local Forms = OpxAdmin.Forms
local Keys = OpxAdmin.Keys

local Menu = {}
OpxAdmin.Menu = Menu

local MENU = "opx77_menu"
local EVENT = "opx77_admin:row"
local LINKS = type(Config.LINKS) == "table" and Config.LINKS or {}

--- The mapping that opens and closes the menu, and the command it sends. The id is stable: a
--- player's rebind is stored under it.
local KEY_MENU = "opx77_admin.menu"
local OPENER = "opx77.admin"

--- opx77_menu refuses a level past 200 rows; the navigation rows need room.
local MAX_LISTED = 190

--- What the server said at open: `you`, `access`, `aclKnown`, `weapons`.
---@type table|nil
local session

local roster, rosterById, incoming = {}, {}, {}
local locations = {}

--- { screen, arg, cursor } from the root down.
local stack = {}

--- The open menu's handle, and whether it was taken down on purpose to put a form up.
local handle
local suspended = false

--- A status line to write when the next screen opens.
local queuedStatus

--- Bumped by every draw, so a slow `open` that lost the race does not claim the handle.
local drawn = 0

-- ---------------------------------------------------------------------------
-- Rows
-- ---------------------------------------------------------------------------

--- Whether the ACL grants a command, as far as the server could tell. Without an ACL reader on
--- the host every row is drawn enabled and the host answers for each one.
---@param name any
---@return boolean
local function permitted(name)
  if session == nil or type(name) ~= "string" or name == "" then return false end
  if not session.aclKnown then return true end
  return session.access[name] == true
end

--- A catalogue key, or `{ text = ... }` for words that are data rather than this resource's.
---@param label string|table
---@return string
local function text(label)
  if type(label) == "table" then return tostring(label.text) end
  return locale(label)
end

---@param id string
---@param label string
---@param data table|nil
---@param extra table|nil
---@return table
local function row(id, label, data, extra)
  local item = { id = id, label = label, data = data }
  for key, value in pairs(extra or {}) do item[key] = value end
  return item
end

--- A row that runs a command line. Greyed, with the reason beside it, when the ACL refuses it.
---@param id string
---@param label string|table
---@param tokens table
---@param refresh string|nil  roster | locations: what to ask for again after it ran
---@param extra table|nil
local function command(id, label, tokens, refresh, extra)
  local item = row(id, text(label), { run = tokens, refresh = refresh }, extra)
  if not permitted(tokens[1]) then
    item.disabled = true
    item.value = locale("admin.menu.denied")
  end
  return item
end

--- A row that asks before it runs: kill, kick, ban and anything that reaches everybody.
local function guarded(id, labelKey, tokens, confirmKey)
  local item = command(id, labelKey, tokens)
  item.data = { confirm = tokens, key = confirmKey }
  return item
end

--- A row that opens a form. `name` is the command the form ends in, for the grey-out.
local function form(id, labelKey, kind, arg, name)
  local item = row(id, locale(labelKey), { form = kind, arg = arg })
  if not permitted(name) then
    item.disabled = true
    item.value = locale("admin.menu.denied")
  end
  return item
end

---@param id string
---@param label string|table
---@param screen string
---@param arg any
---@param extra table|nil
local function go(id, label, screen, arg, extra)
  return row(id, text(label), { go = screen, arg = arg }, extra)
end

---@param labelKey string|nil
local function section(labelKey)
  return { separator = true, label = labelKey and locale(labelKey) or nil }
end

--- The name of a roster player, for a title.
---@param id integer
---@return string
local function nameOf(id)
  local entry = rosterById[id]
  return entry and ("%s [%d]"):format(entry.name, id) or ("[%s]"):format(tostring(id))
end

-- ---------------------------------------------------------------------------
-- Screens: each answers a title and its rows
-- ---------------------------------------------------------------------------

local SCREENS = {}

SCREENS.root = function()
  return locale("admin.menu.title"), {
    go("players", "admin.menu.players", "players", nil, { value = tostring(#roster) }),
    go("self", "admin.menu.self", "self"),
    go("vehicles", "admin.menu.vehicles", "vehicles"),
    go("weapons", "admin.menu.weapons", "weapons"),
    go("world", "admin.menu.world", "world"),
    go("server", "admin.menu.server", "server"),
  }
end

SCREENS.players = function()
  local items = {}
  for index = 1, math.min(#roster, MAX_LISTED) do
    local entry = roster[index]
    local value = locale("admin.state." .. entry.state)
    if entry.bucket ~= 0 then value = value .. " b" .. entry.bucket end
    if entry.distance then value = value .. " " .. entry.distance .. "m" end
    items[#items + 1] = go("player_" .. entry.id,
      { text = ("[%d] %s"):format(entry.id, entry.name) }, "player", entry.id, { value = value })
  end
  if #items == 0 then
    items[1] = row("empty", locale("admin.menu.nobody"), nil, { disabled = true })
  end
  return locale("admin.menu.players"), items
end

SCREENS.player = function(id)
  local target = tostring(id)
  local items = {
    section("admin.menu.section.movement"),
    command("goto", "admin.menu.goto", { "opx77.admin.player.goto", target }),
    command("bring", "admin.menu.bring", { "opx77.admin.player.bring", target }, "roster"),
    go("send", "admin.menu.send", "locations", id),
    form("coords", "admin.menu.coords", "coords", id, "opx77.admin.player.tp"),
    command("observe", "admin.menu.observe", { "opx77.admin.player.observe", target }),

    section("admin.menu.section.health"),
    command("heal", "admin.menu.heal", { "opx77.admin.player.heal", target }, "roster"),
    command("revive", "admin.menu.revive", { "opx77.admin.player.revive", target }, "roster"),
    command("god", "admin.menu.god", { "opx77.admin.player.god", target }),
    form("health", "admin.menu.health", "health", id, "opx77.admin.player.health"),
    form("armor", "admin.menu.armor", "armor", id, "opx77.admin.player.armor"),
    guarded("kill", "admin.menu.kill", { "opx77.admin.player.kill", target }, "admin.confirm.kill"),
  }

  if Client.running("opx77_core") then
    items[#items + 1] = section("admin.menu.section.character")
    if LINKS.WHERE then
      items[#items + 1] = command("record", "admin.menu.record", { LINKS.WHERE, target })
    end
    if LINKS.JOB then
      items[#items + 1] = form("job", "admin.menu.job", "job", id, LINKS.JOB)
    end
    if LINKS.GANG then
      items[#items + 1] = form("gang", "admin.menu.gang", "gang", id, LINKS.GANG)
    end
    if LINKS.MONEY then
      items[#items + 1] = form("money", "admin.menu.money", "money", id, LINKS.MONEY)
    end
  end

  items[#items + 1] = section("admin.menu.section.items")
  items[#items + 1] = go("giveVehicle", "admin.menu.giveVehicle", "vehicleClasses", id)
  items[#items + 1] = go("giveWeapon", "admin.menu.giveWeapon", "weaponClasses", id)
  items[#items + 1] = command("ammo", "admin.menu.ammo", { "opx77.admin.weapon.ammo", target })
  items[#items + 1] = command("holster", "admin.menu.holster",
    { "opx77.admin.weapon.holster", target })
  items[#items + 1] = guarded("disarm", "admin.menu.disarm",
    { "opx77.admin.weapon.remove", target, "all" }, "admin.confirm.disarm")
  items[#items + 1] = command("loadout", "admin.menu.loadout",
    { "opx77.admin.weapon.read", target })

  items[#items + 1] = section("admin.menu.section.moderation")
  items[#items + 1] = form("kick", "admin.menu.kick", "kick", id, "opx77.admin.moderate.kick")
  items[#items + 1] = form("ban", "admin.menu.ban", "ban", id, "opx77.admin.moderate.ban")
  return nameOf(id), items
end

SCREENS.self = function()
  return locale("admin.menu.self"), {
    command("noclip", "admin.menu.noclip", { "opx77.admin.self.noclip" }),
    form("speed", "admin.menu.speed", "speed", nil, "opx77.admin.self.speed"),
    command("maptravel", "admin.menu.maptravel", { "opx77.admin.self.maptravel" }),
    command("god", "admin.menu.god", { "opx77.admin.self.god" }),
    command("heal", "admin.menu.heal", { "opx77.admin.self.heal" }),
    command("revive", "admin.menu.revive", { "opx77.admin.self.revive" }),
    section(),
    go("teleport", "admin.menu.teleport", "locations", "me"),
    form("coords", "admin.menu.coords", "coords", "me", "opx77.admin.player.tp"),
    command("pos", "admin.menu.pos", { "opx77.admin.self.pos" }),
  }
end

SCREENS.vehicles = function()
  local items = {
    go("spawn", "admin.menu.spawn", "vehicleClasses", "me"),
    section("admin.menu.section.nearest"),
    command("repair", "admin.menu.repair", { "opx77.admin.vehicle.repair", "near", "full" }),
    command("repairVisual", "admin.menu.repairVisual",
      { "opx77.admin.vehicle.repair", "near", "visual" }),
  }
  local flags = type((Config.VEHICLES or {}).FLAGS) == "table" and Config.VEHICLES.FLAGS or {}
  for _, flag in ipairs(flags) do
    if type(flag) == "string" and flag:match("^[%w_]+$") then
      items[#items + 1] = command("flag_" .. flag,
        { text = locale("admin.menu.flag", { flag = flag }) },
        { "opx77.admin.vehicle.flag", "near", flag })
    end
  end
  items[#items + 1] = command("remove", "admin.menu.remove",
    { "opx77.admin.vehicle.remove", "near" })
  items[#items + 1] = section()
  items[#items + 1] = command("removeMine", "admin.menu.removeMine",
    { "opx77.admin.vehicle.remove", "mine" })
  items[#items + 1] = guarded("cleanup", "admin.menu.cleanup", { "opx77.admin.vehicle.cleanup" },
    "admin.confirm.cleanup")
  return locale("admin.menu.vehicles"), items
end

--- A class list for a target: "me", or a player id. `kind` is vehicle or weapon.
local function classes(kind, target)
  local list = kind == "vehicle" and Catalog.vehicleClasses or Catalog.weaponClasses
  local items = {}
  for _, class in ipairs(list) do
    if #class.members > 0 then
      items[#items + 1] = go("class_" .. class.key, { text = class.label },
        kind == "vehicle" and "vehicleList" or "weaponList", { t = target, c = class.key },
        { value = tostring(#class.members) })
    end
  end
  if #items == 0 then items[1] = row("empty", locale("admin.menu.catalogEmpty"), nil,
    { disabled = true }) end
  local titleKey = kind == "vehicle" and "admin.menu.vehicles" or "admin.menu.weapons"
  local title = target == "me" and locale(titleKey)
    or ("%s: %s"):format(locale(titleKey), nameOf(target))
  return title, items
end

SCREENS.vehicleClasses = function(target) return classes("vehicle", target) end
SCREENS.weaponClasses = function(target) return classes("weapon", target) end

--- The rows of one class, each a spawn for the operator or a delivery to a player.
local function members(kind, arg)
  local list = kind == "vehicle" and Catalog.vehicleClasses or Catalog.weaponClasses
  local target = type(arg) == "table" and arg.t or "me"
  local found
  for _, class in ipairs(list) do
    if type(arg) == "table" and class.key == arg.c then found = class end
  end
  local items = {}
  for index = 1, found and math.min(#found.members, MAX_LISTED) or 0 do
    local entry = found.members[index]
    local tokens
    if kind == "vehicle" then
      tokens = target == "me" and { "opx77.admin.vehicle.spawn", entry.name }
        or { "opx77.admin.vehicle.give", tostring(target), entry.name }
    else
      tokens = { "opx77.admin.weapon.give", tostring(target), entry.name }
    end
    local item = command("entry_" .. entry.name, { text = entry.label }, tokens)
    if kind == "weapon" and session and not session.weapons then
      item.disabled, item.value = true, locale("admin.menu.unavailable")
    end
    items[#items + 1] = item
  end
  if #items == 0 then items[1] = row("empty", locale("admin.menu.catalogEmpty"), nil,
    { disabled = true }) end
  return found and found.label or "?", items
end

SCREENS.vehicleList = function(arg) return members("vehicle", arg) end
SCREENS.weaponList = function(arg) return members("weapon", arg) end

SCREENS.weapons = function()
  local unavailable = session and not session.weapons
  local items = {
    go("give", "admin.menu.giveMe", "weaponClasses", "me"),
    command("ammo", "admin.menu.ammo", { "opx77.admin.weapon.ammo", "me" }),
    command("holster", "admin.menu.holster", { "opx77.admin.weapon.holster", "me" }),
    guarded("disarm", "admin.menu.disarm", { "opx77.admin.weapon.remove", "me", "all" },
      "admin.confirm.disarm"),
    command("loadout", "admin.menu.loadout", { "opx77.admin.weapon.read", "me" }),
  }
  if unavailable then
    for _, item in ipairs(items) do
      item.disabled, item.value = true, locale("admin.menu.unavailable")
    end
  end
  return locale("admin.menu.weapons"), items
end

SCREENS.locations = function(target)
  local items = {}
  for index = 1, math.min(#locations, MAX_LISTED) do
    local entry = locations[index]
    local item = command("loc_" .. entry.name, { text = entry.label },
      { "opx77.admin.player.send", tostring(target), entry.name })
    if not item.disabled and entry.runtime then item.value = locale("admin.menu.runtime") end
    items[#items + 1] = item
  end
  if #items == 0 then items[1] = row("empty", locale("admin.menu.noLocations"), nil,
    { disabled = true }) end
  local title = target == "me" and locale("admin.menu.teleport")
    or ("%s: %s"):format(locale("admin.menu.send"), nameOf(target))
  return title, items
end

SCREENS.saved = function()
  local items = {}
  for _, entry in ipairs(locations) do
    if entry.runtime then
      items[#items + 1] = command("forget_" .. entry.name,
        { text = locale("admin.menu.forget", { label = entry.label }) },
        { "opx77.admin.world.loc.remove", entry.name }, "locations")
    end
  end
  if #items == 0 then items[1] = row("empty", locale("admin.menu.noSaved"), nil,
    { disabled = true }) end
  return locale("admin.menu.saved"), items
end

SCREENS.world = function()
  local items = {
    form("announce", "admin.menu.announce", "announce", nil, "opx77.admin.world.announce"),
    section("admin.menu.section.locations"),
    go("teleport", "admin.menu.teleport", "locations", "me"),
    form("save", "admin.menu.saveHere", "location", nil, "opx77.admin.world.loc.add"),
    go("saved", "admin.menu.saved", "saved"),
  }
  if Client.running("opx77_weather") then
    items[#items + 1] = section("admin.menu.section.sky")
    items[#items + 1] = go("weather", "admin.menu.weather", "weather")
    items[#items + 1] = go("time", "admin.menu.time", "time")
  end
  return locale("admin.menu.world"), items
end

SCREENS.weather = function()
  local items = {}
  if LINKS.WEATHER_SET then
    for _, preset in ipairs(type(Config.WEATHER_PRESETS) == "table" and Config.WEATHER_PRESETS
      or {}) do
      if type(preset) == "string" and preset:match("^[%w_%-]+$") then
        items[#items + 1] = command("preset_" .. preset, { text = preset },
          { LINKS.WEATHER_SET, preset })
      end
    end
  end
  items[#items + 1] = section()
  if LINKS.WEATHER_NEXT then
    items[#items + 1] = command("next", "admin.menu.weatherNext", { LINKS.WEATHER_NEXT })
  end
  if LINKS.WEATHER_FREEZE then
    items[#items + 1] = command("hold", "admin.menu.weatherHold", { LINKS.WEATHER_FREEZE, "on" })
    items[#items + 1] = command("release", "admin.menu.weatherRelease",
      { LINKS.WEATHER_FREEZE, "off" })
  end
  return locale("admin.menu.weather"), items
end

SCREENS.time = function()
  local items = {}
  if LINKS.TIME then
    for _, clock in ipairs(type(Config.TIMES) == "table" and Config.TIMES or {}) do
      if type(clock) == "string" and clock:match("^%d%d?:%d%d$") then
        items[#items + 1] = command("at_" .. (clock:gsub(":", "_")), { text = clock },
          { LINKS.TIME, clock })
      end
    end
    items[#items + 1] = form("custom", "admin.menu.timeCustom", "time", nil, LINKS.TIME)
  end
  items[#items + 1] = section()
  if LINKS.TIME_FREEZE then
    items[#items + 1] = command("hold", "admin.menu.clockHold", { LINKS.TIME_FREEZE, "on" })
    items[#items + 1] = command("release", "admin.menu.clockRelease", { LINKS.TIME_FREEZE, "off" })
  end
  return locale("admin.menu.time"), items
end

SCREENS.server = function()
  local items = {
    command("status", "admin.menu.status", { "opx77.admin.read.status" }),
    command("list", "admin.menu.playerList", { "opx77.admin.read.players" }),
    command("audit", "admin.menu.audit", { "opx77.admin.read.audit" }),
    command("locations", "admin.menu.locationList", { "opx77.admin.read.locations" }),
  }
  if Client.running("opx77_core") then
    items[#items + 1] = section("admin.menu.section.characters")
    if LINKS.CHARACTERS then
      items[#items + 1] = command("characters", "admin.menu.characters", { LINKS.CHARACTERS })
    end
    if LINKS.SAVE then
      items[#items + 1] = guarded("save", "admin.menu.saveAll", { LINKS.SAVE },
        "admin.confirm.save")
    end
  end
  return locale("admin.menu.server"), items
end

SCREENS.confirm = function(arg)
  return locale(arg.key), {
    row("cancel", locale("admin.menu.cancel"), { back = true }),
    row("confirm", locale("admin.menu.confirm"), { confirmed = true },
      { description = table.concat(arg.tokens, " ") }),
  }
end

-- ---------------------------------------------------------------------------
-- Drawing
-- ---------------------------------------------------------------------------

---@return table|nil
local function top()
  return stack[#stack]
end

--- Put the top screen up. `inPlace` rebuilds the open one without moving the cursor.
---@param inPlace boolean|nil
local function draw(inPlace)
  local current = top()
  if current == nil or suspended then return end
  local builder = SCREENS[current.screen]
  if builder == nil then return end
  local title, items = builder(current.arg)
  if current.screen == "confirm" then
    -- Cancel is already the first row: a Back under it would be a second way to say no
  elseif #stack > 1 then
    items[#items + 1] = section()
    items[#items + 1] = row("back", locale("admin.menu.back"), { back = true })
  else
    items[#items + 1] = section()
    local key = Keys.effective(KEY_MENU)
    items[#items + 1] = { id = "close", label = locale("admin.menu.close"), close = true,
      description = key and locale("admin.menu.closeKey", { key = key }) or nil }
  end

  drawn = drawn + 1
  local mine = drawn
  local status = queuedStatus
  queuedStatus = nil
  CreateThread(function()
    if inPlace and handle ~= nil then
      local _, reason = Client.call(MENU, "update", handle, { title = title, items = items })
      if reason == nil then return end
    end
    local opened, reason = Client.call(MENU, "open", {
      id = "opx77_admin." .. current.screen,
      title = title,
      event = EVENT,
      cursor = current.cursor,
      status = status and status.text or nil,
      items = items,
    })
    if mine ~= drawn then return end
    if opened == nil then
      handle = nil
      Open77.log.warn(("menu %s did not open: %s"):format(current.screen, tostring(reason)))
      if reason == "menu_busy" then Client.toast("admin.client.menuBusy", nil, "warning") end
      return
    end
    handle = opened.handle
    if status and status.ok == false then
      Client.call(MENU, "setStatus", status.text, false)
    end
  end)
end

---@param screen string
---@param arg any
local function push(screen, arg)
  stack[#stack + 1] = { screen = screen, arg = arg }
  -- leaving the root: a grant added or removed with acl.reload shows without reopening
  if #stack == 2 then TriggerServerEvent("opx77_admin:refresh", "access") end
  if screen == "players" or screen == "player" then
    TriggerServerEvent("opx77_admin:refresh", "roster")
  elseif screen == "locations" or screen == "saved" then
    TriggerServerEvent("opx77_admin:refresh", "locations")
  end
  draw()
end

local function pop()
  if #stack <= 1 then return Menu.close() end
  stack[#stack] = nil
  draw()
end

--- Write the line under the list, or keep it for the next screen when none is up.
---@param text string
---@param ok boolean
function Menu.status(text, ok)
  if type(text) ~= "string" then return end
  -- the line is capped at 120 characters and a listing is many lines: the chat box has it all
  local line = text:match("^[^\n]*") or text
  if #line > 116 then line = line:sub(1, 113) .. "..." end
  if handle == nil then
    queuedStatus = { text = line, ok = ok }
    return
  end
  CreateThread(function() Client.call(MENU, "setStatus", line, ok) end)
end

--- Run a command line from a row or a form, and ask for a list again once it has had time to
--- land. The answer is written under the list when it comes back.
---@param tokens table
---@param refresh string|nil
function Menu.run(tokens, refresh)
  suspended = false
  if #stack > 0 and handle == nil then draw() end
  if not Client.execute(tokens) then
    Menu.status(locale("admin.client.notSent"), false)
    return
  end
  if refresh then
    CreateThread(function()
      Wait(1200)
      TriggerServerEvent("opx77_admin:refresh", refresh)
    end)
  end
end

--- Ask before running.
---@param tokens table
---@param key string
function Menu.confirm(tokens, key)
  suspended = false
  if #stack == 0 then return end
  top().cursor = nil
  stack[#stack + 1] = { screen = "confirm", arg = { tokens = tokens, key = key } }
  draw()
end

--- Take the menu down for a form, keeping the stack.
function Menu.suspend()
  suspended = true
  if handle == nil then return end
  local closing = handle
  handle = nil
  CreateThread(function() Client.call(MENU, "close", closing) end)
end

--- Bring the menu back after a form, with a line under it if there is one.
---@param text string|nil
---@param ok boolean|nil
function Menu.resume(text, ok)
  suspended = false
  if text then queuedStatus = { text = text, ok = ok } end
  draw()
end

function Menu.close()
  stack = {}
  suspended = false
  Forms.close()
  if handle == nil then return end
  local closing = handle
  handle = nil
  CreateThread(function() Client.call(MENU, "close", closing) end)
end

--- Redraw the open screen in place, for text that changed under it.
function Menu.refresh()
  if handle ~= nil and not suspended then draw(true) end
end

---@return boolean
function Menu.isOpen()
  return handle ~= nil or Forms.isOpen()
end

---@return string|nil
function Menu.screen()
  local current = top()
  return current and current.screen or nil
end

-- ---------------------------------------------------------------------------
-- The wire
-- ---------------------------------------------------------------------------

--- The opener's answer. Any client resource can raise this name locally; what it would get is
--- a menu whose every row is a command the host refuses it.
RegisterNetEvent("opx77_admin:open", function(payload)
  if type(payload) ~= "table" then return end
  if #stack > 0 and not suspended then return Menu.close() end -- the command toggles
  if not Client.need(MENU) then
    Client.toast("admin.client.menuMissing", nil, "error")
    return
  end
  session = {
    you = tonumber(payload.you),
    access = type(payload.access) == "table" and payload.access or {},
    aclKnown = payload.aclKnown == true,
    weapons = payload.weapons == true,
  }
  stack = { { screen = "root" } }
  suspended = false
  draw()
end)

RegisterNetEvent("opx77_admin:access", function(payload)
  if session == nil or type(payload) ~= "table" or type(payload.access) ~= "table" then return end
  session.access, session.aclKnown = payload.access, payload.aclKnown == true
  draw(true)
end)

RegisterNetEvent("opx77_admin:roster", function(payload)
  if type(payload) ~= "table" or type(payload.rows) ~= "table" then return end
  if payload.offset == 0 then incoming = {} end
  for _, entry in ipairs(payload.rows) do
    local id = tonumber(type(entry) == "table" and entry.id or nil)
    if id and type(entry.name) == "string" then
      incoming[#incoming + 1] = {
        id = id, name = entry.name, bucket = tonumber(entry.bucket) or 0,
        distance = tonumber(entry.distance),
        state = (entry.state == "up" or entry.state == "down" or entry.state == "gate")
          and entry.state or "loading",
      }
    end
  end
  if payload.done ~= true then return end
  roster, rosterById = incoming, {}
  incoming = {}
  for _, entry in ipairs(roster) do rosterById[entry.id] = entry end
  local screen = Menu.screen()
  if screen == "players" or screen == "player" or screen == "root" then draw(true) end
end)

RegisterNetEvent("opx77_admin:locations", function(payload)
  if type(payload) ~= "table" or type(payload.rows) ~= "table" then return end
  local rows = {}
  for _, entry in ipairs(payload.rows) do
    if type(entry) == "table" and type(entry.name) == "string" and entry.name:match("^[%w_%-]+$")
    then
      rows[#rows + 1] = { name = entry.name, label = tostring(entry.label or entry.name),
                          runtime = entry.runtime == true }
    end
  end
  locations = rows
  local screen = Menu.screen()
  if screen == "locations" or screen == "saved" then draw(true) end
end)

--- A row was used. Any resource on this machine can raise this name, so the shape and the
--- owner are checked; whatever a row runs is gated by the host anyway.
AddEventHandler(EVENT, function(payload)
  if type(payload) ~= "table" or payload.owner ~= Client.RESOURCE then return end

  if payload.action == "close" then
    -- a screen this one replaced, whose close can arrive before the new handle does
    if payload.reason == "reopened" or payload.handle ~= handle then return end
    handle = nil
    if suspended then return end
    if payload.reason == "back" and #stack > 1 then
      stack[#stack] = nil
      return draw()
    end
    stack = {}
    return
  end

  if payload.action ~= "select" or type(payload.data) ~= "table" then return end
  local data = payload.data
  local current = top()
  if current == nil then return end
  current.cursor = payload.itemId

  if data.back then return pop() end
  if data.confirmed and current.screen == "confirm" then
    local tokens = current.arg.tokens
    stack[#stack] = nil
    draw()
    return Menu.run(tokens)
  end
  if type(data.go) == "string" and SCREENS[data.go] then return push(data.go, data.arg) end
  if type(data.run) == "table" then return Menu.run(data.run, data.refresh) end
  if type(data.confirm) == "table" and type(data.key) == "string" then
    return Menu.confirm(data.confirm, data.key)
  end
  if type(data.form) == "string" then return Forms.open(data.form, data.arg) end
end)

-- ---------------------------------------------------------------------------
-- The key
-- ---------------------------------------------------------------------------

--- Up, the menu comes down here: closing grants nothing. Down, the key sends the line
--- /opx77.admin sends, so the host resolves command.opx77.admin before the server answers with
--- a menu, and a player without the grant gets the host's refusal and nothing else.
local function pressed()
  if Menu.isOpen() then return Menu.close() end
  Client.execute({ OPENER })
end

AddEventHandler("onClientResourceStart", function(name)
  if name ~= Client.RESOURCE then return end
  local keys = Config.KEYS
  if keys ~= nil and type(keys) ~= "table" then
    Open77.log.warn("config: KEYS must be a table; using the default keys")
    keys = nil
  end
  keys = keys or {}
  Keys.register(KEY_MENU, "admin.key.menu", Keys.setting("KEYS.MENU", keys.MENU, "F10"), pressed)
end)

-- the close row names the key, so a rebind in the pause menu shows without reopening
Keys.onChanged(Menu.refresh)

AddEventHandler("onClientResourceStop", function(name)
  if name ~= Client.RESOURCE then return end
  -- opx77_menu and opx77_input sweep a stopped owner, but not instantly
  Menu.close()
end)
