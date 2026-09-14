--- Commands that act on a body or a session: the operator's own, somebody else's, and the two
--- moderation commands. Every one of them is restricted; see server/main.lua.

local Config = OPX_ADMIN_CONFIG
local Server = OpxAdmin.Server
local Text = OpxAdmin.Text

local answer, refuse, audit, tell = Server.answer, Server.refuse, Server.audit, Server.tell
local count = Server.count

local RESOURCE = GetCurrentResourceName()

--- Resolve the typed target, or answer why not.
---@return integer|nil
local function targetOf(source, raw, token)
  local playerId, code = Server.target(source, token)
  if playerId == nil then refuse(source, raw, code) end
  return playerId
end

--- The gate, answered and audited when it is closed.
---@return boolean
local function admitted(source, raw, playerId, event)
  local ok, code = Server.admit(playerId)
  if ok then return true end
  refuse(source, raw, code, { id = playerId })
  audit(source, event, false, playerId, code)
  return false
end

--- A native mutator answered `false, reason`: tell the operator, keep the reason in the audit.
---@return false
local function nativeRefused(source, raw, event, playerId, reason)
  refuse(source, raw, "refused", { reason = tostring(reason) })
  audit(source, event, false, playerId, "refused: " .. tostring(reason))
  return false
end

--- The three words that make a point, or nil.
---@return { x: number, y: number, z: number }|nil
local function pointOf(x, y, z)
  x, y, z = Text.finite(x), Text.finite(y), Text.finite(z)
  if x == nil or y == nil or z == nil then return nil end
  -- the world is a few kilometres across; past a million is a typo, not a destination
  if math.abs(x) > 1e6 or math.abs(y) > 1e6 or math.abs(z) > 1e6 then return nil end
  return { x = x, y = y, z = z }
end

---@return number maximum, table|nil health
local function healthOf(playerId)
  local read, health = pcall(Open77.players.getHealth, playerId)
  if not read or type(health) ~= "table" then return 100.0, nil end
  local maximum = Text.finite(health.maxHealth)
  -- getHealth answers ABSOLUTE points; revive and respawn take a FRACTION. Never mix the two.
  if maximum == nil or maximum <= 0 then maximum = 100.0 end
  return maximum, health
end

-- ---------------------------------------------------------------------------
-- Travel: noclip and map travel
--
-- Both are client capabilities. The ACL decides here; the client half applies it through its
-- own `player.travel` grant. This is not what stops a patched client flying -- nothing on the
-- server can -- it is what keeps the switch in staff hands on an honest one.
-- ---------------------------------------------------------------------------

--- playerId -> the command name that switched it on, so a revoked grant switches it off.
local noclip, mapPick = {}, {}
local speedChosen = {}

---@param playerId integer
---@param action string  noclip | speed | mapPick | copy
local function travel(playerId, action, value, detail)
  TriggerClientEvent("opx77_admin:travel", playerId, action, value, detail)
end

---@param playerId integer
---@param on boolean
---@param grant string|nil
local function setNoclip(playerId, on, grant)
  noclip[playerId] = on and grant or nil
  travel(playerId, "noclip", on == true)
  if on and speedChosen[playerId] == nil then
    travel(playerId, "speed", Server.setting((Config.NOCLIP or {}).SPEED, 40.0))
  end
end

Server.command("opx77.admin.self.noclip", {
  help = "admin.help.noclip", params = { { name = "on|off", help = "admin.help.toggle" } },
  inGame = true,
  handler = function(source, args, raw)
    local wanted, invalid = Text.switch(args[1])
    if invalid then return refuse(source, raw, "bad_switch") end
    if wanted == nil then wanted = noclip[source] == nil end
    setNoclip(source, wanted, "opx77.admin.self.noclip")
    audit(source, "admin.self.noclip", true, nil, wanted and "on" or "off")
    answer(source, raw, true, wanted and "admin.done.noclipOn" or "admin.done.noclipOff")
  end,
})

Server.command("opx77.admin.self.speed", {
  help = "admin.help.speed", params = { { name = "m/s", help = "admin.help.speedValue" } },
  inGame = true,
  handler = function(source, args, raw)
    local speed = Text.finite(args[1])
    if count(args) ~= 1 or speed == nil or speed < 0.1 or speed > 500 then
      return answer(source, raw, false, "admin.usage.speed")
    end
    speedChosen[source] = speed
    travel(source, "speed", speed)
    audit(source, "admin.self.speed", true, nil, ("%.1f"):format(speed))
    answer(source, raw, true, "admin.done.speed", { speed = ("%.1f"):format(speed) })
  end,
})

Server.command("opx77.admin.self.maptravel", {
  help = "admin.help.maptravel",
  params = { { name = "on|off|x", help = "admin.help.maptravelValue" }, { name = "y" },
             { name = "z" } },
  inGame = true,
  handler = function(source, args, raw)
    if count(args) == 3 then
      -- the double click: the client sends the point back through this same command, so the
      -- ACL is resolved again on every jump rather than once when the gesture was armed
      local point = pointOf(args[1], args[2], args[3])
      if point == nil then return refuse(source, raw, "bad_coordinates") end
      local placed, code, reason = Server.place(source, point, 0.0, nil, "maptravel")
      audit(source, "admin.self.maptravel", placed, source,
        ("%.0f %.0f %.0f %s"):format(point.x, point.y, point.z, code or ""))
      if not placed then return refuse(source, raw, code, { reason = reason }) end
      return answer(source, raw, true, "admin.done.moved",
        { x = ("%.1f"):format(point.x), y = ("%.1f"):format(point.y),
          z = ("%.1f"):format(point.z) })
    end
    local wanted, invalid = Text.switch(args[1])
    if invalid or count(args) > 1 then
      return answer(source, raw, false, "admin.usage.maptravel")
    end
    if wanted == nil then wanted = mapPick[source] == nil end
    mapPick[source] = wanted and "opx77.admin.self.maptravel" or nil
    travel(source, "mapPick", wanted)
    audit(source, "admin.self.maptravel", true, nil, wanted and "on" or "off")
    answer(source, raw, true, wanted and "admin.done.mapOn" or "admin.done.mapOff")
  end,
})

--- Switch a revoked grant's travel mode off. Rechecked on a timer because a grant can be
--- removed with acl.reload while the mode is on, and no event says so.
CreateThread(function()
  while true do
    Wait(2000)
    local swept, failure = pcall(function()
      for playerId, grant in pairs(noclip) do
        if Server.permitted(playerId, grant) == false then
          setNoclip(playerId, false)
          Open77.log.info(("noclip off for player %d: %s is no longer granted")
            :format(playerId, grant))
        end
      end
      for playerId, grant in pairs(mapPick) do
        if Server.permitted(playerId, grant) == false then
          mapPick[playerId] = nil
          travel(playerId, "mapPick", false)
        end
      end
    end)
    if not swept then Open77.log.warn("travel sweep failed: " .. tostring(failure)) end
  end
end)

AddEventHandler("onPlayerDisconnected", function(playerId)
  local player = tonumber(playerId) or 0
  -- a recycled id must not inherit the last occupant's switches
  noclip[player], mapPick[player], speedChosen[player] = nil, nil, nil
end)

AddEventHandler("onResourceStop", function(name)
  if name ~= RESOURCE then return end
  -- the client half turns both off on its own stop as well; this reaches one that is not
  -- stopping, such as a server-only reload
  for playerId in pairs(noclip) do travel(playerId, "noclip", false) end
  for playerId in pairs(mapPick) do travel(playerId, "mapPick", false) end
end)

Server.noclip = setNoclip

-- ---------------------------------------------------------------------------
-- The operator's own body
-- ---------------------------------------------------------------------------

---@param source integer
---@param raw string
---@param playerId integer
---@param event string
local function heal(source, raw, playerId, event)
  if not admitted(source, raw, playerId, event) then return end
  local maximum = healthOf(playerId)
  local ok, reason = Open77.players.setHealth(playerId, maximum)
  if not ok then return nativeRefused(source, raw, event, playerId, reason) end
  audit(source, event, true, playerId, ("%.0f"):format(maximum))
  if playerId ~= source then tell(playerId, "admin.toast.healed", nil, "success") end
  answer(source, raw, true, "admin.done.healed",
    { id = playerId, name = Server.nameOf(playerId) or "?" })
end

---@param source integer
---@param raw string
---@param playerId integer
---@param event string
local function revive(source, raw, playerId, event)
  if not admitted(source, raw, playerId, event) then return end
  local placement = Config.PLACEMENT or {}
  local ok, reason = Open77.players.revive(playerId, {
    health = math.min(1.0, math.max(0.01, Server.setting(placement.HEALTH, 1.0))),
    graceMs = math.max(0, math.floor(Server.setting(placement.GRACE_MS, 5000))),
  })
  if not ok then return nativeRefused(source, raw, event, playerId, reason) end
  audit(source, event, true, playerId)
  if playerId ~= source then tell(playerId, "admin.toast.revived", nil, "success") end
  answer(source, raw, true, "admin.done.revived",
    { id = playerId, name = Server.nameOf(playerId) or "?" })
end

---@param source integer
---@param raw string
---@param playerId integer
---@param word any
---@param event string
local function god(source, raw, playerId, word, event)
  local wanted, invalid = Text.switch(word)
  if invalid then return refuse(source, raw, "bad_switch") end
  if not admitted(source, raw, playerId, event) then return end
  if wanted == nil then
    local _, health = healthOf(playerId)
    wanted = not (health ~= nil and health.godMode == true)
  end
  local ok, reason = Open77.players.setGodMode(playerId, wanted)
  if not ok then return nativeRefused(source, raw, event, playerId, reason) end
  audit(source, event, true, playerId, wanted and "on" or "off")
  if playerId ~= source then
    tell(playerId, wanted and "admin.toast.godOn" or "admin.toast.godOff")
  end
  answer(source, raw, true, wanted and "admin.done.godOn" or "admin.done.godOff",
    { id = playerId, name = Server.nameOf(playerId) or "?" })
end

Server.command("opx77.admin.self.heal", {
  help = "admin.help.selfHeal", inGame = true,
  handler = function(source, _, raw) heal(source, raw, source, "admin.self.heal") end,
})

Server.command("opx77.admin.self.revive", {
  help = "admin.help.selfRevive", inGame = true,
  handler = function(source, _, raw) revive(source, raw, source, "admin.self.revive") end,
})

Server.command("opx77.admin.self.god", {
  help = "admin.help.selfGod", params = { { name = "on|off", help = "admin.help.toggle" } },
  inGame = true,
  handler = function(source, args, raw) god(source, raw, source, args[1], "admin.self.god") end,
})

Server.command("opx77.admin.self.pos", {
  help = "admin.help.pos", inGame = true, read = true,
  handler = function(source, _, raw)
    local position = Server.positionOf(source)
    if position == nil then return refuse(source, raw, "no_position") end
    local row = ('{ NAME = "here", LABEL = "Here", X = %.2f, Y = %.2f, Z = %.2f, HEADING = 0.0 },')
      :format(position.x, position.y, position.z)
    travel(source, "copy", row)
    answer(source, raw, true, "admin.done.pos", { row = row, bucket = position.bucket })
  end,
})

-- ---------------------------------------------------------------------------
-- Somebody else's body
-- ---------------------------------------------------------------------------

--- Where to land beside a player, in their bucket.
---@param playerId integer
---@return { x: number, y: number, z: number }|nil, integer|nil
local function beside(playerId)
  local position = Server.positionOf(playerId)
  if position == nil then return nil, nil end
  local offset = (Config.PLACEMENT or {}).BESIDE or {}
  return {
    x = position.x + Server.setting(offset.X, 1.5),
    y = position.y + Server.setting(offset.Y, 0.0),
    z = position.z + Server.setting(offset.Z, 0.0),
  }, position.bucket
end

Server.command("opx77.admin.player.goto", {
  help = "admin.help.goto", params = { { name = "playerId" } }, inGame = true,
  handler = function(source, args, raw)
    local playerId = targetOf(source, raw, args[1])
    if playerId == nil then return end
    if playerId == source then return refuse(source, raw, "self_target") end
    -- the destination has to be a real body too: an unincarnated player stands in a menu world
    if not admitted(source, raw, playerId, "admin.player.goto") then return end
    local point, bucket = beside(playerId)
    if point == nil then return refuse(source, raw, "no_position") end
    local placed, code, reason = Server.place(source, point, 0.0, bucket, "goto")
    audit(source, "admin.player.goto", placed, playerId, code)
    if not placed then return refuse(source, raw, code, { reason = reason }) end
    answer(source, raw, true, "admin.done.goto",
      { id = playerId, name = Server.nameOf(playerId) or "?", bucket = bucket })
  end,
})

Server.command("opx77.admin.player.bring", {
  help = "admin.help.bring", params = { { name = "playerId" } }, inGame = true,
  handler = function(source, args, raw)
    local playerId = targetOf(source, raw, args[1])
    if playerId == nil then return end
    if playerId == source then return refuse(source, raw, "self_target") end
    local point, bucket = beside(source)
    if point == nil then return refuse(source, raw, "no_position") end
    local placed, code, reason = Server.place(playerId, point, 0.0, bucket, "bring")
    audit(source, "admin.player.bring", placed, playerId, code)
    if not placed then return refuse(source, raw, code, { reason = reason, id = playerId }) end
    tell(playerId, "admin.toast.brought")
    answer(source, raw, true, "admin.done.bring",
      { id = playerId, name = Server.nameOf(playerId) or "?" })
  end,
})

Server.command("opx77.admin.player.tp", {
  help = "admin.help.tp",
  params = { { name = "playerId|me" }, { name = "x" }, { name = "y" }, { name = "z" },
             { name = "heading" } },
  handler = function(source, args, raw)
    local given = count(args)
    if given < 4 or given > 5 then return answer(source, raw, false, "admin.usage.tp") end
    local playerId = targetOf(source, raw, args[1])
    if playerId == nil then return end
    local point = pointOf(args[2], args[3], args[4])
    local heading = given == 5 and Text.finite(args[5]) or 0.0
    if point == nil or heading == nil then return refuse(source, raw, "bad_coordinates") end
    local placed, code, reason = Server.place(playerId, point, heading, nil, "tp")
    audit(source, "admin.player.tp", placed, playerId,
      ("%.0f %.0f %.0f %s"):format(point.x, point.y, point.z, code or ""))
    if not placed then return refuse(source, raw, code, { reason = reason, id = playerId }) end
    if playerId ~= source then tell(playerId, "admin.toast.moved") end
    answer(source, raw, true, "admin.done.moved",
      { x = ("%.1f"):format(point.x), y = ("%.1f"):format(point.y),
        z = ("%.1f"):format(point.z) })
  end,
})

Server.command("opx77.admin.player.observe", {
  help = "admin.help.observe", params = { { name = "playerId" } }, inGame = true,
  handler = function(source, args, raw)
    local playerId = targetOf(source, raw, args[1])
    if playerId == nil then return end
    if playerId == source then return refuse(source, raw, "self_target") end
    if not admitted(source, raw, playerId, "admin.player.observe") then return end
    local position = Server.positionOf(playerId)
    if position == nil then return refuse(source, raw, "no_position") end
    local height = Server.setting((Config.PLACEMENT or {}).OBSERVE_HEIGHT, 2.0)
    local placed, code, reason = Server.place(source,
      { x = position.x, y = position.y, z = position.z + height }, 0.0, position.bucket,
      "observe")
    audit(source, "admin.player.observe", placed, playerId, code)
    if not placed then return refuse(source, raw, code, { reason = reason }) end
    -- there is no free camera on this platform: this is a teleport with noclip, and the
    -- target can see the observer. The answer says so.
    setNoclip(source, true, "opx77.admin.player.observe")
    answer(source, raw, true, "admin.done.observe",
      { id = playerId, name = Server.nameOf(playerId) or "?" })
  end,
})

Server.command("opx77.admin.player.heal", {
  help = "admin.help.heal", params = { { name = "playerId|me" } },
  handler = function(source, args, raw)
    local playerId = targetOf(source, raw, args[1])
    if playerId then heal(source, raw, playerId, "admin.player.heal") end
  end,
})

Server.command("opx77.admin.player.revive", {
  help = "admin.help.revive", params = { { name = "playerId|me" } },
  handler = function(source, args, raw)
    local playerId = targetOf(source, raw, args[1])
    if playerId then revive(source, raw, playerId, "admin.player.revive") end
  end,
})

Server.command("opx77.admin.player.god", {
  help = "admin.help.god",
  params = { { name = "playerId|me" }, { name = "on|off", help = "admin.help.toggle" } },
  handler = function(source, args, raw)
    local playerId = targetOf(source, raw, args[1])
    if playerId then god(source, raw, playerId, args[2], "admin.player.god") end
  end,
})

Server.command("opx77.admin.player.kill", {
  help = "admin.help.kill", params = { { name = "playerId" } },
  handler = function(source, args, raw)
    local playerId = targetOf(source, raw, args[1])
    if playerId == nil then return end
    if not admitted(source, raw, playerId, "admin.player.kill") then return end
    local ok, reason = Open77.players.kill(playerId, {
      killer = source > 0 and source or nil,
      cause = "script",
      weapon = RESOURCE .. ":kill",
    })
    if not ok then return nativeRefused(source, raw, "admin.player.kill", playerId, reason) end
    audit(source, "admin.player.kill", true, playerId)
    tell(playerId, "admin.toast.killed", nil, "warning")
    answer(source, raw, true, "admin.done.killed",
      { id = playerId, name = Server.nameOf(playerId) or "?" })
  end,
})

Server.command("opx77.admin.player.health", {
  help = "admin.help.health", params = { { name = "playerId|me" }, { name = "points" } },
  handler = function(source, args, raw)
    local value = Text.finite(args[2])
    if count(args) ~= 2 or value == nil or value < 0 then
      return answer(source, raw, false, "admin.usage.health")
    end
    local playerId = targetOf(source, raw, args[1])
    if playerId == nil then return end
    if not admitted(source, raw, playerId, "admin.player.health") then return end
    local maximum = healthOf(playerId)
    value = math.min(value, maximum)
    local ok, reason = Open77.players.setHealth(playerId, value)
    if not ok then return nativeRefused(source, raw, "admin.player.health", playerId, reason) end
    audit(source, "admin.player.health", true, playerId, ("%.0f/%.0f"):format(value, maximum))
    answer(source, raw, true, "admin.done.health",
      { id = playerId, value = ("%.0f"):format(value), maximum = ("%.0f"):format(maximum) })
  end,
})

Server.command("opx77.admin.player.armor", {
  help = "admin.help.armor", params = { { name = "playerId|me" }, { name = "points" } },
  handler = function(source, args, raw)
    local value = Text.finite(args[2])
    if count(args) ~= 2 or value == nil or value < 0 or value > 10000 then
      return answer(source, raw, false, "admin.usage.armor")
    end
    local playerId = targetOf(source, raw, args[1])
    if playerId == nil then return end
    if not admitted(source, raw, playerId, "admin.player.armor") then return end
    local ok, reason = Open77.players.setArmor(playerId, value)
    if not ok then return nativeRefused(source, raw, "admin.player.armor", playerId, reason) end
    audit(source, "admin.player.armor", true, playerId, ("%.0f"):format(value))
    answer(source, raw, true, "admin.done.armor",
      { id = playerId, value = ("%.0f"):format(value) })
  end,
})

-- ---------------------------------------------------------------------------
-- Moderation. These act on the session, not the body, so the readiness gate does not apply:
-- a player stuck on the loading screen must still be removable.
-- ---------------------------------------------------------------------------

--- The platform refuses a disconnect reason past 127 UTF-8 bytes, outright.
local KICK_REASON_BYTES = 127

--- `30m`, `12h`, `7d`, `3600s`, or `perm`. A bare number is not a duration: `/ban 7 3 strikes`
--- is a reason, not three seconds.
local UNITS = { s = 1, m = 60, h = 3600, d = 86400 }
local MAX_BAN_SECONDS = 3650 * 86400

---@param token any
---@return integer|false|nil  seconds, false for permanent, nil for "not a duration"
local function duration(token)
  if type(token) ~= "string" then return nil end
  local word = token:lower()
  if word == "perm" or word == "permanent" then return false end
  local amount, unit = word:match("^(%d+)([smhd])$")
  if amount == nil then return nil end
  local seconds = tonumber(amount) * UNITS[unit]
  if seconds <= 0 or seconds > MAX_BAN_SECONDS then return nil end
  return seconds
end

Server.command("opx77.admin.moderate.kick", {
  help = "admin.help.kick", params = { { name = "playerId" }, { name = "reason" } },
  handler = function(source, args, raw)
    local playerId = targetOf(source, raw, args[1])
    if playerId == nil then return end
    local reason = Text.clean(Text.rest(args, 2), 200) or locale("admin.kick.defaultReason")
    reason = Text.bytes(reason, KICK_REASON_BYTES)
    local name = Server.nameOf(playerId) or "?"
    local ok, failure = Open77.players.kick(playerId, reason)
    if not ok then return nativeRefused(source, raw, "admin.moderate.kick", playerId, failure) end
    audit(source, "admin.moderate.kick", true, playerId, ("%s: %s"):format(name, reason))
    answer(source, raw, true, "admin.done.kicked", { id = playerId, name = name, reason = reason })
  end,
})

Server.command("opx77.admin.moderate.ban", {
  help = "admin.help.ban",
  params = { { name = "playerId" }, { name = "duration", help = "admin.help.banDuration" },
             { name = "reason" } },
  handler = function(source, args, raw)
    local playerId = targetOf(source, raw, args[1])
    if playerId == nil then return end

    local seconds, reasonFrom = nil, 2
    local parsed = duration(args[2])
    if parsed == false then
      reasonFrom = 3
    elseif parsed ~= nil then
      seconds, reasonFrom = parsed, 3
    elseif type(args[2]) == "string" and args[2]:lower():match("^%-?%d+[smhd]$") then
      -- it looks like a duration and is out of range: refusing beats banning for ever
      return refuse(source, raw, "bad_duration")
    end

    local access = Open77.access
    if type(access) ~= "table" or type(access.ban) ~= "function" then
      return refuse(source, raw, "refused", { reason = "access_unavailable" })
    end
    local identifier = Server.userOf(playerId)
    if identifier == nil then return refuse(source, raw, "refused", { reason = "no_identity" }) end

    local reason = Text.clean(Text.rest(args, reasonFrom), 200) or locale("admin.ban.defaultReason")
    local name = Server.nameOf(playerId) or "?"
    -- the host writes the ban before it disconnects anybody, and answers false if it could not
    local ok, failure = access.ban(identifier, reason, seconds, name)
    if not ok then return nativeRefused(source, raw, "admin.moderate.ban", playerId, failure) end
    audit(source, "admin.moderate.ban", true, playerId,
      ("%s %s: %s"):format(name, seconds and (seconds .. "s") or "permanent", reason))
    answer(source, raw, true, seconds and "admin.done.banned" or "admin.done.bannedForever",
      { id = playerId, name = name, reason = reason,
        hours = seconds and ("%.1f"):format(seconds / 3600) or "" })
  end,
})
