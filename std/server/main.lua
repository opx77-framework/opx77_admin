---@meta

--- The server half's spine: answers, the audit, the readiness gate, placement and the command
--- registry every staff command file registers through.
OpxAdmin.Server = {}

--- Host-monotonic milliseconds. `Open77.time.monotonic` answers seconds; a failed or non-finite
--- reading holds the last good one.
---@return integer
function OpxAdmin.Server.NowMs() end

--- A configured number, or the fallback for anything arithmetic would raise on.
---@param value any
---@param fallback number
---@return number
function OpxAdmin.Server.Setting(value, fallback) end

--- How many arguments were typed. `args.n` is authoritative: `#args` reads a hole as the end.
---@param args table
---@return integer
function OpxAdmin.Server.Count(args) end

--- One answer back to whoever ran the command: a chat line for a report, a toast for an action's
--- outcome, through this resource's client half; English in the log for the console.
---@param source integer
---@param raw string the typed line, so the menu can put the answer under its list
---@param ok boolean
---@param key string catalogue key
---@param params table|nil
---@param kind "info"|"success"|"warning"|"error"|nil inferred from `ok` and `key` when nil
---@return boolean ok
function OpxAdmin.Server.Answer(source, raw, ok, key, params, kind) end

--- Answers a refusal by its code: a warning for what was typed, an error otherwise.
--- `params.reason` is the host's own word, when it gave one.
---@param source integer
---@param raw string
---@param code AdminError
---@param params table|nil
---@return boolean false
function OpxAdmin.Server.Refuse(source, raw, code, params) end

--- A toast on the target's screen through the platform's notifications. Best-effort: a missing
--- surface never fails the action that already happened.
---@param playerId integer
---@param key string catalogue key
---@param params table|nil
---@param kind "info"|"success"|"warning"|"error"|nil
function OpxAdmin.Server.Tell(playerId, key, params, kind) end

--- The Master-verified display name, cleaned to 32 characters.
---@param playerId integer
---@return string|nil
function OpxAdmin.Server.NameOf(playerId) end

--- The durable account id. A player id is recycled; this is what an audit line keeps.
---@param playerId integer
---@return string|nil
function OpxAdmin.Server.UserOf(playerId) end

--- Resolves a typed target, a connected player id or `me` / `self`, and answers the refusal
--- (`no_target`, `bad_target`, `not_connected`, `console_has_no_player`) when there is none.
---@param source integer
---@param raw string
---@param token any
---@return integer|nil playerId
function OpxAdmin.Server.Target(source, raw, token) end

--- The replicated position and routing bucket, or nil before the world is up.
---@param playerId integer
---@return { x: number, y: number, z: number, bucket: integer }|nil
function OpxAdmin.Server.PositionOf(playerId) end

--- The host's life state, or nil: loading and the continue screen have none.
---@param playerId integer
---@return table|nil
function OpxAdmin.Server.LifeOf(playerId) end

--- Whether anything may be done to this player's body: a life state and an open readiness gate.
--- Fails closed when the gate cannot be read. Kick and ban do not come through here.
---@param playerId integer
---@return boolean admitted
---@return table|AdminError lifeOrCode
function OpxAdmin.Server.Admit(playerId) end

--- `OpxAdmin.Server.Admit`, with a closed gate answered to the operator and audited under `event`.
---@param source integer
---@param raw string
---@param playerId integer
---@param event string
---@return boolean admitted
function OpxAdmin.Server.Admitted(source, raw, playerId, event) end

--- Moves a player through kill then respawn, never a transform write. A refused respawn after
--- a kill revives the player where they fell.
---@param playerId integer
---@param point { x: number, y: number, z: number }
---@param heading number|nil
---@param bucket integer|nil nil keeps the bucket they are in
---@param why string what the kill is attributed to
---@return boolean ok
---@return AdminError|nil code
---@return string|nil reason
function OpxAdmin.Server.Place(playerId, point, heading, bucket, why) end

--- Records one staff action: an `[audit]` line in the platform log, in opx77_core's shape, and an
--- entry in the in-memory ring `/opx77.admin.read.audit` reads.
---@param source integer
---@param event string stable and greppable: "admin.player.kill"
---@param ok boolean
---@param target integer|nil the player acted on, if any
---@param detail string|nil English, for the log
function OpxAdmin.Server.Audit(source, event, ok, target, detail) end

--- The most recent audit entries, newest last.
---@param count integer
---@return AuditEntry[]
function OpxAdmin.Server.Recent(count) end

--- Registers one staff command, always restricted: the host resolves `command.<name>` before the
--- handler runs. Adds the in-game check, the per-operator floor and a raise guard.
---@param name string
---@param spec AdminCommandSpec
function OpxAdmin.Server.Command(name, spec) end

--- Whether this run falls inside the player's floor for `name`, recording it when it does not.
--- Every command, `chat:ready` and each menu refresh topic keep their own slot; the console is
--- never cooled.
---@param player integer
---@param name string
---@param intervalMs number
---@return boolean cooled true when the run is to be dropped
function OpxAdmin.Server.Cooled(player, name, intervalMs) end

--- Every registered command, in registration order.
---@return AdminCommand[]
function OpxAdmin.Server.Commands() end

--- Whether the host's ACL grants `command.<name>`, for the places that are not a command. Nil when
--- the host has no ACL reader or it raised; the console is always true.
---@param playerId integer
---@param name string
---@return boolean|nil
function OpxAdmin.Server.Permitted(playerId, name) end
