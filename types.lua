---@meta
--- Type annotations for opx77_admin. Never loaded at runtime; keep it in step with the code.

--- A refusal code. Meant for branching and for the audit, never for a player to read: a player
--- reads the `admin.error.*` catalogue key server/main.lua maps it to.
---@alias AdminError
---| "in_game_only"          the command acts on the caller's own body, and the console has none
---| "too_fast"              inside RATE.ACTION_MS or RATE.READ_MS of the last run
---| "failed"                the handler raised; the log has the line
---| "no_target"             no player named
---| "bad_target"            not a player id and not `me`
---| "console_has_no_player" `me`, or `near`, typed at the console
---| "not_connected"         nobody holds that player id
---| "self_target"           goto, bring or observe aimed at the caller
---| "not_incarnated"        no life state: loading, or the continue screen
---| "gate_closed"           the readiness gate is still held for that player
---| "gate_unreadable"       Open77.ready is missing or raised; fails closed
---| "no_position"           no replicated position for that player yet
---| "kill_refused"          the first half of a placement was refused
---| "respawn_refused"       the second half was refused; the player was revived in place
---| "refused"               a native answered false; `reason` carries the host's own word
---| "bad_number"            a reserve or amount that is not a whole number
---| "bad_coordinates"       a point that is not three finite numbers inside a million
---| "bad_switch"            not on, off, or nothing
---| "bad_duration"          looks like a ban duration and is out of range
---| "empty_text"            an announcement with nothing in it
---| "unknown_vehicle"       not a NAME or RECORD in data/vehicles.lua
---| "vehicle_cap"           VEHICLES.PER_OWNER reached for that player
---| "no_vehicle"            no such vehicle id, or nothing within NEAR_RADIUS
---| "occupied"              somebody is aboard; remove refuses
---| "unsafe_repair"         full or mechanical with somebody aboard
---| "bad_scope"             not a repair scope
---| "unknown_flag"          not in VEHICLES.FLAGS, or the host has no mask of that name
---| "not_ours"              the host refused a removal: another resource created it
---| "vehicles_unavailable"  Open77.vehicles is missing on this host
---| "unknown_weapon"        not a NAME or RECORD in data/weapons.lua
---| "bad_slot"              not 1, 2, 3, auto or all
---| "weapons_unavailable"   Open77.weapons is missing on this host
---| "weapon_no_answer"      the target's client never answered the relay: request_timeout
---| "unknown_location"      no destination of that name
---| "bad_location_name"     not 1..32 letters, digits, _ or -
---| "seeded_location"       configured in config.lua, so not removable in game

--- One command as server/main.lua registers it.
---@class AdminCommandSpec
---@field help string                 catalogue key of the chat suggestion
---@field params AdminParameter[]|nil
---@field read boolean|nil            cooled on RATE.READ_MS instead of RATE.ACTION_MS
---@field inGame boolean|nil          refused from the console
---@field handler fun(source: integer, args: table, raw: string)

---@class AdminParameter
---@field name string
---@field help string|nil  catalogue key
---@field optional boolean|nil  true when the handler runs without it; drawn `[name]` in the chat

--- What `Server.commands()` answers, in registration order.
---@class AdminCommand
---@field name string
---@field help string
---@field params AdminParameter[]

--- One row of data/vehicles.lua or data/weapons.lua, after the index checked it.
---@class CatalogEntry
---@field name string    what staff type, lower-cased
---@field label string
---@field record string  the exact TweakDB record
---@field class string   a class key

---@class CatalogClass
---@field key string
---@field label string
---@field members CatalogEntry[]

---@class WeaponClass : CatalogClass
---@field ammo boolean      false for melee: no spare rounds are asked for
---@field reserve integer   spare rounds a give loads

--- One entry of the in-memory audit ring. The log line written beside it is the record.
---@class AuditEntry
---@field seq integer
---@field atMs integer
---@field event string          "admin.player.kill"
---@field ok boolean
---@field actor integer         0 for the console
---@field actorName string
---@field target integer|nil
---@field targetName string|nil
---@field detail string

---@class AdminLocation
---@field name string
---@field label string
---@field x number
---@field y number
---@field z number
---@field heading number
---@field runtime boolean  added in game; gone at the next restart

--- One player as the menu's roster draws them. No character: that lives in opx77_core's VM.
---@class AdminRosterRow
---@field id integer
---@field name string            the Master-verified display name
---@field state "up"|"down"|"gate"|"loading"
---@field bucket integer
---@field distance integer|nil   metres from the operator, same bucket only

--- `opx77_admin:open`, server to client.
---@class AdminSession
---@field you integer
---@field access table<string, true>  command names the ACL grants; absent means refused
---@field aclKnown boolean            false when the host has no ACL reader: nothing is greyed
---@field weapons boolean             Open77.weapons exists on this host

--- Every export answers a table carrying `ok` and never raises.
---@class AdminResponse
---@field ok boolean
---@field error "export_call_required"|"menu_not_running"|"not_sent"|nil
---@field queued boolean|nil  `open`: the opener command was sent; the host decides the rest
---@field open boolean|nil

---@class AdminState : AdminResponse
---@field screen string|nil  "root", "players", "player", ... while the menu is up
