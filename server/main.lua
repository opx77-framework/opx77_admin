--- The spine of the server half: answers, the audit, the readiness gate, placement, and the one
--- registry every staff command goes through.
---
--- Every command is registered restricted, so the host resolves `command.<name>` against the
--- caller's ACL before a handler runs. No handler in this resource checks a permission, and
--- none may: the host has already decided, and a second check would only drift from it.

OpxAdmin = OpxAdmin or {}

local Config = OPX_ADMIN_CONFIG
local Text = OpxAdmin.Text

local Server = {}
OpxAdmin.Server = Server

local RESOURCE = GetCurrentResourceName()

-- ---------------------------------------------------------------------------
-- Clock and configuration
-- ---------------------------------------------------------------------------

--- Host-monotonic milliseconds; `monotonic` answers SECONDS. A failed or non-finite reading
--- holds the last one: a NaN would expire nothing, an infinity everything.
local lastMs = 0
---@return integer
function Server.nowMs()
  local read, seconds = pcall(Open77.time.monotonic)
  if read and type(seconds) == "number" and seconds == seconds and
    seconds >= 0 and seconds < math.huge then
    lastMs = math.floor(seconds * 1000)
  end
  return lastMs
end
local nowMs = Server.nowMs

--- A configured number, or the fallback for anything arithmetic would raise on.
---@param value any
---@param fallback number
---@return number
function Server.setting(value, fallback)
  return Text.finite(value) or fallback
end

--- How many arguments were typed. `n` is authoritative: `#args` reads a hole as the end.
---@param args table
---@return integer
function Server.count(args)
  local given = Text.integer(args.n)
  if given == nil or given < 0 then return #args end
  return given
end

-- ---------------------------------------------------------------------------
-- Answers
-- ---------------------------------------------------------------------------

--- Refusal code -> catalogue key. Codes stay codes in the audit and the log.
local ERRORS = {
  in_game_only = "admin.error.inGameOnly",
  too_fast = "admin.error.tooFast",
  failed = "admin.error.failed",
  no_target = "admin.error.noTarget",
  bad_target = "admin.error.badTarget",
  console_has_no_player = "admin.error.consoleNoPlayer",
  not_connected = "admin.error.notConnected",
  self_target = "admin.error.selfTarget",
  not_incarnated = "admin.error.notIncarnated",
  gate_closed = "admin.error.gateClosed",
  gate_unreadable = "admin.error.gateUnreadable",
  no_position = "admin.error.noPosition",
  kill_refused = "admin.error.killRefused",
  respawn_refused = "admin.error.respawnRefused",
  refused = "admin.error.refused",
  bad_number = "admin.error.badNumber",
  bad_coordinates = "admin.error.badCoordinates",
  bad_switch = "admin.error.badSwitch",
  bad_duration = "admin.error.badDuration",
  empty_text = "admin.error.emptyText",
  unknown_vehicle = "admin.error.unknownVehicle",
  vehicle_cap = "admin.error.vehicleCap",
  no_vehicle = "admin.error.noVehicle",
  occupied = "admin.error.occupied",
  unsafe_repair = "admin.error.unsafeRepair",
  bad_scope = "admin.error.badScope",
  unknown_flag = "admin.error.unknownFlag",
  not_ours = "admin.error.notOurs",
  vehicles_unavailable = "admin.error.vehiclesUnavailable",
  unknown_weapon = "admin.error.unknownWeapon",
  bad_slot = "admin.error.badSlot",
  weapons_unavailable = "admin.error.weaponsUnavailable",
  weapon_no_answer = "admin.error.weaponNoAnswer",
  unknown_location = "admin.error.unknownLocation",
  bad_location_name = "admin.error.badLocationName",
  seeded_location = "admin.error.seededLocation",
}

--- One line back to whoever ran the command. A player reads the configured catalogue; the
--- console reads English, because that answer lands in a log an operator greps.
---@param source integer
---@param raw string
---@param ok boolean
---@param key string
---@param params? table
---@return boolean ok
function Server.answer(source, raw, ok, key, params)
  local player = tonumber(source) or 0
  if player > 0 then
    TriggerClientEvent("open77:command:result", player, raw or "", ok == true,
      locale(key, params))
  else
    local line = OpxAdmin.Locale.english(key, params)
    if ok then Open77.log.info(line) else Open77.log.warn(line) end
  end
  return ok == true
end

--- Answer a refusal by its code. `detail` is the host's own reason, when it gave one.
---@param source integer
---@param raw string
---@param code string
---@param params? table
---@return boolean false
function Server.refuse(source, raw, code, params)
  params = params or {}
  params.code = code
  params.reason = params.reason and Text.clean(params.reason, 64) or code
  Server.answer(source, raw, false, ERRORS[code] or ERRORS.failed, params)
  return false
end

--- A toast on the target's screen, drawn by opx77_notify through the platform's own
--- notification events. Best-effort: nobody is moved in silence, but a missing surface must
--- not fail the action that already happened.
---@param playerId integer
---@param key string
---@param params? table
---@param kind? string  info | success | warning | error
function Server.tell(playerId, key, params, kind)
  local notifications = Open77.notifications
  if type(notifications) ~= "table" or type(notifications.send) ~= "function" then return end
  pcall(notifications.send, playerId, {
    type = kind or "info",
    title = locale("admin.toast.title"),
    message = locale(key, params),
    durationMs = math.floor(Server.setting(Config.TOAST_MS, 6000)),
  })
end

-- ---------------------------------------------------------------------------
-- Identity
-- ---------------------------------------------------------------------------

--- The Master-verified display name, cleaned for a log line or a menu row.
---@param playerId integer
---@return string|nil
function Server.nameOf(playerId)
  local read, name = pcall(Open77.players.name, playerId)
  if not read then return nil end
  return Text.clean(name, 32)
end

--- The durable account id. `playerId` is recycled; this is what an audit line is worth keeping.
---@param playerId integer
---@return string|nil
function Server.userOf(playerId)
  if (tonumber(playerId) or 0) <= 0 then return nil end
  local read, identifier = pcall(Open77.players.identifier, playerId)
  if not read then return nil end
  return Text.clean(identifier, 64)
end

--- Resolve what was typed for a target: a connected player id, or `me`.
---@param source integer
---@param token any
---@return integer|nil playerId, string|nil code
function Server.target(source, token)
  if token == nil then return nil, "no_target" end
  local word = tostring(token):lower()
  if word == "me" or word == "self" then
    if source <= 0 then return nil, "console_has_no_player" end
    return source, nil
  end
  local playerId = Text.integer(token)
  if playerId == nil or playerId <= 0 then return nil, "bad_target" end
  if Server.nameOf(playerId) == nil then return nil, "not_connected" end
  return playerId, nil
end

--- The replicated position, or nil before the world is up.
---@param playerId integer
---@return { x: number, y: number, z: number, bucket: integer }|nil
function Server.positionOf(playerId)
  local read, position = pcall(Open77.players.position, playerId)
  if not read or type(position) ~= "table" then return nil end
  local x, y, z = Text.finite(position.x), Text.finite(position.y), Text.finite(position.z)
  if x == nil or y == nil or z == nil then return nil end
  return { x = x, y = y, z = z, bucket = Text.integer(position.bucket) or 0 }
end

-- ---------------------------------------------------------------------------
-- The readiness gate
-- ---------------------------------------------------------------------------

---@param playerId integer
---@return table|nil
function Server.lifeOf(playerId)
  local read, life = pcall(Open77.players.getLifeState, playerId)
  if not read or type(life) ~= "table" then return nil end
  return life
end

--- May anything be done TO this player's body? Acting server-side on a client that is not
--- incarnated crashes that client, so both halves are required: a life state, which the
--- continue screen has none of, and an open readiness gate. Fails closed when the gate cannot
--- be read. Kick and ban do not come through here; they touch the session, not the body.
---@param playerId integer
---@return boolean admitted, table|string lifeOrCode
function Server.admit(playerId)
  local life = Server.lifeOf(playerId)
  if life == nil then return false, "not_incarnated" end
  local ready = Open77.ready
  if type(ready) ~= "table" or type(ready.isReady) ~= "function" then
    return false, "gate_unreadable"
  end
  -- pcall: isReady raises for an id the host does not know rather than answering false
  local read, open = pcall(ready.isReady, playerId)
  if not read then return false, "gate_unreadable" end
  if open ~= true then return false, "gate_closed" end
  return true, life
end

--- Move a player through kill -> respawn, never a transform write: only the respawn carries
--- the fade, the streaming preload and the grace window.
---@param playerId integer
---@param point { x: number, y: number, z: number }
---@param heading number|nil
---@param bucket integer|nil  nil keeps the one they are in
---@param why string          what the kill is attributed to
---@return boolean ok, string|nil code, string|nil reason
function Server.place(playerId, point, heading, bucket, why)
  local admitted, code = Server.admit(playerId)
  if not admitted then return false, code end

  local placement = Config.PLACEMENT or {}
  local health = math.min(1.0, math.max(0.01, Server.setting(placement.HEALTH, 1.0)))
  local graceMs = math.max(0, math.floor(Server.setting(placement.GRACE_MS, 5000)))
  if bucket == nil then
    local position = Server.positionOf(playerId)
    bucket = position and position.bucket or 0
  end

  local killed = false
  local deadRead, dead = pcall(Open77.players.isDead, playerId)
  if not (deadRead and dead == true) then
    local ok, reason = Open77.players.kill(playerId, {
      cause = "script",
      weapon = RESOURCE .. ":" .. why,
    })
    if not ok then return false, "kill_refused", tostring(reason) end
    killed = true
  end

  local respawned, reason = Open77.players.respawn(playerId, {
    position = { x = point.x, y = point.y, z = point.z },
    heading = heading or 0.0,
    bucket = bucket,
    health = health,
    graceMs = graceMs,
  })
  if not respawned then
    -- the body is down and was not stood back up: revive where it fell rather than leave it
    if killed then
      pcall(Open77.players.revive, playerId, { health = health, graceMs = graceMs })
    end
    return false, "respawn_refused", tostring(reason)
  end
  return true
end

-- ---------------------------------------------------------------------------
-- The audit
-- ---------------------------------------------------------------------------

local ledger = {}
local sequence = 0
local AUDIT_ENTRIES = math.max(10, math.floor(Server.setting(Config.AUDIT_ENTRIES, 200)))

--- Record one staff action. Two sinks: a line in the platform log, in the same
--- `[audit] event=... severity=...` shape opx77_core writes so one grep finds both, and a ring
--- for /opx77.admin.read.audit. The log line is the record; the ring dies with the process.
---@param source integer
---@param event string       stable and greppable: "admin.player.kill"
---@param ok boolean
---@param target integer|nil the player acted on, if any
---@param detail string|nil  English, for the log
function Server.audit(source, event, ok, target, detail)
  local actor = tonumber(source) or 0
  sequence = sequence + 1
  local entry = {
    seq = sequence,
    atMs = nowMs(),
    event = event,
    ok = ok == true,
    actor = actor,
    actorName = actor > 0 and (Server.nameOf(actor) or "?") or "console",
    target = target,
    targetName = target and Server.nameOf(target) or nil,
    detail = Text.clean(detail, 120) or "",
  }
  ledger[#ledger + 1] = entry
  if #ledger > AUDIT_ENTRIES then table.remove(ledger, 1) end

  local data = {
    actorName = entry.actorName,
    target = target,
    targetUser = target and Server.userOf(target) or nil,
    targetName = entry.targetName,
  }
  local encoded, dataText = pcall(json.encode, data)
  local severity = entry.ok and "info" or "warn"
  Open77.log[severity](("[audit] event=%s severity=%s player=%d user=%s message=%q data=%s")
    :format(event, severity, actor, Server.userOf(actor) or "-", entry.detail,
      encoded and dataText or "{}"))
end

--- The most recent entries, newest last.
---@param count integer
---@return AuditEntry[]
function Server.recent(count)
  local out = {}
  for index = math.max(1, #ledger - count + 1), #ledger do out[#out + 1] = ledger[index] end
  return out
end

-- ---------------------------------------------------------------------------
-- The registry
-- ---------------------------------------------------------------------------

--- In registration order, for the chat suggestions, the access map and the boot line.
---@type AdminCommand[]
local commands = {}
local byName = {}

--- Last run per operator per command.
local lastRun = {}

---@param player integer
---@param name string
---@param intervalMs number
---@return boolean  true when this run should be dropped
local function cooled(player, name, intervalMs)
  -- the console is never cooled
  if player <= 0 then return false end
  local slot = player .. ":" .. name
  local atMs = nowMs()
  local previous = lastRun[slot]
  if previous ~= nil and atMs - previous < intervalMs then return true end
  lastRun[slot] = atMs
  return false
end

--- Register one staff command. There is no argument for an unrestricted one: every command
--- in this resource acts on the world or on somebody, and `true` below is not negotiable.
---@param name string
---@param spec AdminCommandSpec
function Server.command(name, spec)
  if byName[name] ~= nil then
    Open77.log.error(("command %s is registered twice; the second is dropped"):format(name))
    return
  end
  local rate = Config.RATE or {}
  local interval = spec.read and Server.setting(rate.READ_MS, 1000)
    or Server.setting(rate.ACTION_MS, 400)

  RegisterCommand(name, function(source, args, raw)
    local player = tonumber(source) or 0
    raw = type(raw) == "string" and raw or name
    args = type(args) == "table" and args or { n = 0 }
    if spec.inGame and player <= 0 then return Server.refuse(player, raw, "in_game_only") end
    if cooled(player, name, interval) then return Server.refuse(player, raw, "too_fast") end
    -- a raise inside a command handler is otherwise swallowed with no answer at all
    local ran, failure = pcall(spec.handler, player, args, raw)
    if not ran then
      Open77.log.error(("%s raised: %s"):format(name, tostring(failure)))
      Server.refuse(player, raw, "failed")
    end
  end, true)

  local entry = { name = name, help = spec.help, params = spec.params or {} }
  commands[#commands + 1] = entry
  byName[name] = entry
end

---@return AdminCommand[]
function Server.commands()
  return commands
end

--- Whether the host's ACL grants this player `command.<name>`. Only for the places that are
--- not a command: the menu's refresh event, the travel revocation sweep, the suggestions.
--- Nil when this host has no ACL reader, which callers treat as "cannot say".
---@param playerId integer
---@param name string
---@return boolean|nil
function Server.permitted(playerId, name)
  if playerId <= 0 then return true end
  local acl = Open77.acl
  if type(acl) ~= "table" or type(acl.isAllowed) ~= "function" then return nil end
  local read, allowed = pcall(acl.isAllowed, playerId, "command." .. name)
  if not read then return nil end
  return allowed == true
end

--- Suggestions go only to a player the ACL would let run the command, so the staff command
--- list is not handed to everybody who opens the chat box.
RegisterNetEvent("chat:ready", function()
  local player = tonumber(source) or 0
  if player <= 0 or cooled(player, "chat:ready", 2000) then return end
  local suggestions = {}
  for _, command in ipairs(commands) do
    if Server.permitted(player, command.name) == true then
      local parameters = {}
      for index, parameter in ipairs(command.params) do
        parameters[index] = {
          name = parameter.name,
          help = parameter.help and locale(parameter.help) or nil,
        }
      end
      suggestions[#suggestions + 1] = {
        command = "/" .. command.name,
        help = locale(command.help),
        parameters = parameters,
      }
    end
  end
  if #suggestions > 0 then TriggerClientEvent("chat:addSuggestions", player, suggestions) end
end)

--- The only departure event this platform raises. Files below add their own handlers.
AddEventHandler("onPlayerDisconnected", function(playerId)
  local prefix = tostring(tonumber(playerId) or 0) .. ":"
  for slot in pairs(lastRun) do
    if slot:sub(1, #prefix) == prefix then lastRun[slot] = nil end
  end
end)

-- ---------------------------------------------------------------------------
-- Boot checks
-- ---------------------------------------------------------------------------

for _, line in ipairs(OpxAdmin.Catalog.problems) do Open77.log.warn(line) end

do
  -- a key in one catalogue and missing from the other is a defect, not a fallback
  local english, french = OpxAdmin.Locale.keys("en"), OpxAdmin.Locale.keys("fr")
  for key in pairs(english) do
    if not french[key] then Open77.log.warn("locales/fr.lua is missing " .. key) end
  end
  for key in pairs(french) do
    if not english[key] then Open77.log.warn("locales/en.lua is missing " .. key) end
  end
end

if type(Open77.acl) ~= "table" or type(Open77.acl.isAllowed) ~= "function" then
  Open77.log.warn("Open77.acl is unavailable: the menu cannot grey out what the ACL refuses, " ..
    "and the travel modes are not revoked with a grant. Every command is still gated by the host.")
end
