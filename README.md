# opx77_admin

> [!WARNING]
> **This project is currently in early development and is not considered production-ready.**
>
> The API, architecture, features, and internal systems are subject to change at any time
> without prior notice. Breaking changes may be introduced as development progresses.
>
> **Do not rely on the current API for production resources yet.**

> [!IMPORTANT]
> **The host ACL is the only authority, and this resource adds none of its own.**
>
> Every staff action is a command registered with `RegisterCommand(name, handler, true)`, so the
> host resolves `command.<name>` against `acl.jsonc` **before the handler runs**. No handler
> checks a permission. The menu is a front-end: each row sends a command line through
> `open77:command:execute`, the same path the chat box uses, and meets the same gate. A forged
> row, a forged form or a hand-built packet gets exactly what the typed command would get.

The staff tool for **Opx77**. Find a player, get to them, fix them, move them, arm them, hand
them a car or remove them from the server — from a keyboard menu drawn by `opx77_menu`, or from
the chat box and the console with the same commands.

It owns no character data. What a character *is* — citizen id, job, gang, money — belongs to
`opx77_core`, and the menu drives the core's own staff commands for it rather than writing a
second set.

## Features

- A staff menu on `/opx77.admin` and on a rebindable key, F9 by default: players, yourself,
  vehicles, weapons, world and server screens
- Teleport: go to, bring, send to a saved destination, coordinates, map double-click, observe
- Heal, revive, god mode, health, armour and kill, on yourself or anybody
- Kick with a reason, and account bans through the platform's own server-local ban list
- Noclip with a speed, applied on the client only when an ACL-gated command says so
- Vehicles from a catalogue: spawn, deliver to a player, repair, flags, remove, clean up
- Weapons from a catalogue, handed out loaded; refill, clear, holster, read a loadout back
- Announcements to every player, as a toast and a chat line
- Character record, job, gang and money through `opx77_core`'s commands; weather and time
  through `opx77_weather`'s
- Every action audited in the platform log, in the same `[audit]` shape `opx77_core` writes
- Rows the ACL would refuse are greyed; kill, kick, ban and anything server-wide ask first
- Nothing is ever done to a player whose readiness gate is closed

## Requirements

- An OPEN//77 server build with the `Open77.acl` read binding (manifest permission `acl.read`).
  Without it every command still works and is still gated by the host, but the menu cannot
  grey out what the ACL refuses, the travel modes are not switched off when a grant is removed,
  and the menu's refresh request is refused. One warning says so at boot.
- **Soft dependencies.** None is declared: a declared dependency is hard, and a staff tool
  that refuses to start is no tool. Each missing one costs one log line and its screens.

| Resource | What needs it |
|---|---|
| `opx77_menu` | the menu itself; every command still runs typed |
| `opx77_input` | the forms: reasons, amounts, coordinates, announcements |
| `opx77_notify` | the toast a target sees ("a staff member healed you"), and the toast answering each staff action; without it that answer is a chat line |
| `opx77_core` | the character rows: record, job, gang, money, save, characters online |
| `opx77_appearance` | the readiness gate opening at all; see [Safety](#safety) |
| `opx77_weather` | the weather and time screens |
| `open77_weapons` | every weapon command: its client half answers the relay |

`open77_admin`, the platform's own admin package, can run beside this one: every name here is
under `opx77.admin`, so no command shadows another. Two tools switching the same player's
noclip will fight, so give each operator one of them.

## Installation

1. Copy this directory into the server's `resources/` as `opx77_admin`.
2. Add it to `resources.load` in `server.jsonc` if the server uses an explicit list.
3. Grant the permissions below in `acl.jsonc`, then run `acl.reload` in the console.
4. Connect, and press F9 or type `/opx77.admin`.

`reload_policy` is `local`: the resource owns no page, so a reload rebuilds both halves without
a reconnect. Destinations saved in game survive a reload and not a restart.

## Commands and permissions

Every command is restricted. The permission is always `command.` plus the name. Grant a family
with a wildcard — `command.opx77.admin.player.*` — and remember that **`command.opx77.admin.*`
does not cover `command.opx77.admin`**, the menu: the wildcard grants what is *below* the
prefix. Grant both.

`<player>` is a player id, or `me`. A citizen id is not accepted: that mapping lives in
`opx77_core`'s VM, which no other server resource can ask.

| Command | Does |
|---|---|
| `opx77.admin` | open the staff menu; run again to close it |
| **Yourself** | |
| `opx77.admin.self.noclip [on\|off]` | toggle noclip |
| `opx77.admin.self.speed <m/s>` | noclip speed, 0.1 to 500 |
| `opx77.admin.self.maptravel [on\|off]` | arm the world map: a double-click sends you there |
| `opx77.admin.self.maptravel <x> <y> <z>` | what the double-click sends; the ACL is resolved per jump |
| `opx77.admin.self.god [on\|off]` | your own god mode |
| `opx77.admin.self.heal` | heal yourself |
| `opx77.admin.self.revive` | revive yourself where you lie |
| `opx77.admin.self.pos` | copy where you stand as a `LOCATIONS` row |
| **Players** | |
| `opx77.admin.player.goto <player>` | teleport yourself beside them, into their bucket |
| `opx77.admin.player.bring <player>` | teleport them beside you |
| `opx77.admin.player.tp <player> <x> <y> <z> [heading]` | teleport to coordinates |
| `opx77.admin.player.send <player> <location>` | teleport to a saved destination |
| `opx77.admin.player.observe <player>` | land above them with noclip on — they can see you |
| `opx77.admin.player.heal <player>` | heal to their maximum health |
| `opx77.admin.player.revive <player>` | revive where they lie |
| `opx77.admin.player.god <player> [on\|off]` | god mode |
| `opx77.admin.player.health <player> <points>` | health in points, capped at their maximum |
| `opx77.admin.player.armor <player> <points>` | armour in points, 0 to 10000 |
| `opx77.admin.player.kill <player>` | kill |
| **Moderation** | |
| `opx77.admin.moderate.kick <player> [reason]` | disconnect, reason cut to the platform's 127 bytes |
| `opx77.admin.moderate.ban <player> [duration] [reason]` | ban the account on this server |
| **Vehicles** | |
| `opx77.admin.vehicle.spawn <vehicle>` | spawn beside you |
| `opx77.admin.vehicle.give <player> <vehicle>` | spawn beside a player |
| `opx77.admin.vehicle.repair [id\|near] [scope]` | `glass body lights tires visual mechanical full`; `near` and `full` when left out |
| `opx77.admin.vehicle.flag <id\|near> <flag> [on\|off]` | toggle a flag from `VEHICLES.FLAGS` |
| `opx77.admin.vehicle.remove [id\|near\|mine]` | remove one, or all of yours |
| `opx77.admin.vehicle.cleanup` | remove every empty vehicle this resource spawned |
| **Weapons** | |
| `opx77.admin.weapon.give <player> <weapon> [1\|2\|3\|auto] [reserve]` | equip, loaded |
| `opx77.admin.weapon.ammo <player> [slot\|all] [reserve]` | refill |
| `opx77.admin.weapon.remove <player> <slot\|all>` | clear a slot; the item stays in the inventory |
| `opx77.admin.weapon.holster <player>` | holster |
| `opx77.admin.weapon.read <player>` | the three slots, as that client reads them |
| **World** | |
| `opx77.admin.world.announce <text>` | a toast on every screen and a chat line |
| `opx77.admin.world.loc.add <name> [label]` | save where you stand, until the next restart |
| `opx77.admin.world.loc.remove <name>` | forget one saved in game |
| **Reading** | |
| `opx77.admin.read.players` | every connected player: state, bucket, distance |
| `opx77.admin.read.status` | counts, uptime, and the state of the resources this one leans on |
| `opx77.admin.read.audit [count]` | the latest staff actions of this uptime |
| `opx77.admin.read.locations` | every destination |

`near` is the vehicle you sit in, otherwise the nearest one in your bucket within
`VEHICLES.NEAR_RADIUS`, read at the moment of the command. A ban duration carries its unit —
`30m`, `12h`, `7d`, `3600s` — or is `perm`; leaving it out bans permanently, and a bare number
is the first word of the reason, so `/opx77.admin.moderate.ban 7 3 strikes` never bans for three
seconds. Bans are written by the host before anybody is disconnected; lifting one is the
server console's `unban <identity>`, which this resource does not wrap.

### Answers

Every command answers the staff member who ran it, and never on `open77:command:result`, whose
accepted answers `opx77_chat` does not print: the server half sends the answer, already in the
configured locale, to this resource's own client half.

- **An action's outcome is a toast** through `opx77_notify`, titled *STAFF*, in one slot that
  each answer replaces: a success when it was done, *info* when a request is only on its way (a
  weapon asked of a client), a warning for what was typed wrong — a usage, a bad number, an
  unknown name, a command run again too fast — and an error when it could not be done.
- **A report stays a chat line**: `read.players`, `read.status`, `read.audit`,
  `read.locations` and `weapon.read` are lists someone asked to read, scrolled back and
  compared, which a toast would cut short.
- Either way, when the menu sent the command, the first line is also written under the list.

`opx77_notify` stays optional: while it is stopped, or when it refuses a toast, the same text
is a chat line, and the client log says so once. The console reads English in the server log.

### Commands the menu drives in other resources

The menu greys these by the same ACL. Grant them where the role should have them; the names
are `LINKS` in `config.lua`, so a rename in those resources is followed there.

| Row | Command | Resource |
|---|---|---|
| Character record | `opx77.where <id>` | `opx77_core` |
| Set job / Set gang | `opx77.job <id> <job> <grade>` / `opx77.gang ...` | `opx77_core` |
| Money | `opx77.money <id> <TYPE> <amount>` | `opx77_core` |
| Characters in the world / Save every character | `opx77` / `opx77.save` | `opx77_core` |
| Weather presets, roll, hold | `opx77.weather.set`, `.next`, `.freeze` | `opx77_weather` |
| Time, hold the clock | `opx77.weather.time`, `.time.freeze` | `opx77_weather` |

### An `acl.jsonc` example

Principals are matched on the handshake public key and the `userId`; `identity.dump` in the
developer terminal writes a ready-to-paste `aclPrincipal`. Three desks, from least to most:

```jsonc
{
  "version": 1,
  "principals": [
    {
      // gets themselves unstuck and looks around; does nothing to anybody else
      "name": "helper",
      "userId": "00000000-0000-0000-0000-000000000001",
      "publicKey": "…",
      "permissions": [
        "command.opx77.admin",
        "command.opx77.admin.self.*",
        "command.opx77.admin.read.*",
        "command.opx77.where"
      ]
    },
    {
      // handles a report: reach the player, fix them, remove them. No money, no world.
      "name": "moderator",
      "userId": "00000000-0000-0000-0000-000000000002",
      "publicKey": "…",
      "permissions": [
        "command.opx77.admin",
        "command.opx77.admin.self.*",
        "command.opx77.admin.read.*",
        "command.opx77.admin.player.*",
        "command.opx77.admin.moderate.*",
        "command.opx77.admin.vehicle.*",
        "command.opx77.admin.world.announce",
        "command.opx77",
        "command.opx77.where"
      ]
    },
    {
      // the whole tool, plus the core's economy and the sky
      "name": "operator",
      "userId": "00000000-0000-0000-0000-000000000003",
      "publicKey": "…",
      "permissions": [
        "command.opx77",
        "command.opx77.*"
      ]
    }
  ]
}
```

`command.opx77.admin.weapon.give` hands a loaded weapon to anybody, the operator included; it is
left out of the moderator above on purpose. `command.opx77.*` covers every OPX//77 staff
command on the server, the core's money included — grant it only to whoever may have all of it.
`acl.check <playerId> <permission>` in the console answers the exact question the host asks.

## The menu

`/opx77.admin` or the menu key opens it; the arrow keys move, Enter chooses, Backspace goes
back a screen. Each screen is its own `opx77_menu` menu — a roster of thirty players with twenty
actions each is past what one menu tree may hold — and the stack of screens lives in this
resource.

### The key

| Mapping id | Name in the pause menu | Default | Does |
|---|---|---|---|
| `opx77_admin.menu` | *Staff: open or close the menu* | `F9` | opens the menu, or closes it when it is up |

The key is declared with `RegisterKeyMapping`, so the pause menu's key bindings tab lists it
under the name above — read from the configured locale when the resource starts — and every
player can rebind it there. The root screen's **Close** row names the key the player actually
has, and follows a rebind without the menu being reopened.

**It opens nothing by itself.** Pressed with the menu down, it sends `/opx77.admin` through
`open77:command:execute`, the line the chat box sends, so the host resolves
`command.opx77.admin` first: a player without the grant gets the host's refusal — a toast from
`opx77_chat` — and no menu, exactly as if they had typed it. Pressed with the menu up, it closes it locally,
which grants nothing. A press while another surface holds the keyboard — the chat box, a form,
the pause menu — does nothing. The mapping is registered for every player, staff or not: the
client cannot know the ACL, and the host is what answers.

`KEYS.MENU` in `config.lua` sets the default, which a player's own rebind overrides;
`KEYS.MENU = false` registers no mapping. A value that is neither a key name nor `false` is a
client log warning and the default. F9 was chosen clear of the keys the rest of a stock
resource set takes: F2 wardrobe, F3 animation picker, F6 perspective, F8 HUD,
F11 voice mode, X stop animation, V push-to-talk, ALT context menu.

- A row whose command the ACL refuses is drawn greyed, with *no access* beside it. The access map
  is re-read when you leave the root screen, so an `acl.reload` shows without reopening.
- A command's answer is written under the list, and also raised as a toast, or a chat line for
  a report; see [Answers](#answers). A refusal from the host — no grant — is written there in
  words, and `opx77_chat` toasts it.
- Kill, kick, ban, clearing a loadout, the vehicle cleanup, an announcement and saving every
  character go through a confirmation screen with Cancel first. Nothing else does.
- Forms — a reason, an amount, a point — are `opx77_input`'s. The menu steps aside while one is
  up and comes back where it was.
- The roster shows the platform's verified display name, the state (*in world*, *down*,
  *joining*, *loading*), the routing bucket and the distance. It does not show the character's
  name: that is in `opx77_core`'s VM. *Character record* runs `opx77.where` for it.

## Safety

- **Nothing touches a body behind a closed readiness gate.** Every teleport, kill, heal, god
  toggle, weapon request and vehicle delivery first needs a life state — the continue screen has
  none — and `Open77.ready.isReady` true. It fails closed when the gate cannot be read. Acting
  server-side on a client that is not incarnated crashes it. On a resource set with nothing that
  sends `open77:session:gameplayReady` the gate never opens, and every such command refuses;
  `opx77_appearance` is what sends it. Kick and ban act on the session and are not gated.
- **Placement is kill then respawn**, never a transform write: only the respawn carries the fade,
  the streaming preload and the grace window. A refused respawn revives the player where they
  fell rather than leaving a body.
- **The server decides everything.** The client sends a command line; the server resolves the
  target, reads the live position, bucket, life state and vehicle occupancy itself, and never
  acts on a value a menu drew seconds ago.
- **A vehicle with somebody aboard** is never removed, and never given a `full` or `mechanical`
  repair, both of which may respawn it.
- **Nobody is moved in silence.** A target is told by toast what was done to them.
- **Catalogues are allowlists.** Only a row of `data/vehicles.lua` or `data/weapons.lua` ever
  reaches the host, whatever a client types.
- **Travel modes follow the grant.** Noclip and map travel are switched off within two seconds
  of the permission that switched them on being removed, and when this resource stops.

## The audit

Every staff action — and every one refused at the gate or by a native — writes one line:

```text
[audit] event=admin.player.kill severity=info player=3 user=8f0f3a7c-… message="" data={"target":7,"targetUser":"1c4b9e02-…","targetName":"Kiroshi","actorName":"Vex"}
```

The shape is `opx77_core`'s own, so one grep over the platform log finds both. `user` and
`targetUser` are the durable account ids; a player id is recycled and is not worth keeping on its
own. Refusals are logged at `warn`. `/opx77.admin.read.audit` reads the last actions of this
uptime from memory; the log is the record.

## Catalogues

The platform has no server-side call that enumerates vehicle or item records, so the two lists
are hand-picked starters: fourteen vehicles in three classes and seventeen weapons in nine.
**They are allowlists, not suggestions.**

To extend one, add a row to `data/vehicles.lua` or `data/weapons.lua`:

```lua
{ NAME = "outlaw", LABEL = "Herrera Outlaw", CLASS = "sport",
  RECORD = "Vehicle.v_sport1_herrera_outlaw_player" },
```

`NAME` is what staff type, `CLASS` a key from the file's `CLASSES`, `RECORD` the exact TweakDB
record. A malformed row is dropped and named in a boot warning. A record the engine does not
know is refused when it is spawned, with the host's own reason in the answer.

A weapon class says whether it takes ammunition (`AMMO`) and how many spare rounds a give loads
(`RESERVE`); the ammunition *type* is read off the record by the engine. The engine caps what a
character carries per ammunition type, on the spare rounds plus the magazine, and a request
above the cap is partly applied and then reported as refused — keep `RESERVE` modest. Only the
three ordinary weapon slots are supported by the platform: no grenades, heavy weapons or arm
cyberware. A weapon give reads the loadout first, takes the first empty slot, and replaces the
drawn weapon only when all three are full; naming a slot always replaces it.

## Configuration

`config.lua`. Shared, so every client downloads it: nothing in it is a secret or a grant.

| Key | Default | |
|---|---|---|
| `LOCALE` | `"en"` | which `locales/<code>.lua` catalogue player-facing text uses |
| `KEYS.MENU` | `"F9"` | the menu key's default, or `false` for none; see [The key](#the-key) |
| `RATE.ACTION_MS` | `400` | floor between two runs of one mutating command, per operator |
| `RATE.READ_MS` | `1000` | the same for a reading command |
| `RATE.REFRESH_MS` | `750` | floor between two menu refresh requests |
| `AUDIT_ENTRIES` | `200` | how far back `read.audit` can look |
| `TOAST_MS` | `6000` | how long a target's toast stays up |
| `PLACEMENT.HEALTH` | `1.0` | fraction of full health after a move |
| `PLACEMENT.GRACE_MS` | `5000` | respawn protection after a move |
| `PLACEMENT.BESIDE` | `1.5, 0, 0` | offset from the other player on goto and bring |
| `PLACEMENT.OBSERVE_HEIGHT` | `2.0` | metres above the target an observer lands |
| `NOCLIP.SPEED` | `40.0` | m/s the first time noclip goes on |
| `ANNOUNCE.DURATION_MS` | `12000` | announcement toast lifetime |
| `ANNOUNCE.CHAT` | `true` | also write announcements into the chat box |
| `ANNOUNCE.MAX_CHARACTERS` | `240` | |
| `BAN_DURATIONS` | `1h 1d 7d 30d perm` | what the ban form offers |
| `VEHICLES.SPAWN_OFFSET` | `3, 0, 0.25` | where a vehicle appears, world axes |
| `VEHICLES.PER_OWNER` | `8` | staff vehicles out per player at once |
| `VEHICLES.NEAR_RADIUS` | `30.0` | how far `near` looks on foot |
| `VEHICLES.OCCUPIED_REPAIRS` | all but `mechanical`, `full` | repairs allowed with somebody aboard |
| `VEHICLES.FLAGS` | `locked engineOn lightsOn invulnerable` | what `flag` may toggle |
| `WEAPONS.MAX_RESERVE` | `2000` | ceiling on a typed reserve |
| `WEAPONS.FILL_MAGAZINE` | `true` | fill the magazine after the spare rounds |
| `LINKS` | see above | other resources' command names; `false` removes the row |
| `WEATHER_PRESETS`, `TIMES` | | what the sky screens offer |
| `LOCATIONS` | three starters | saved destinations; `/opx77.admin.self.pos` copies a row |

## Exports and events

Client exports. Each answers `{ ok = boolean, ... }` and never raises; the caller is read from
`GetInvokingResource()`.

| Export | Does |
|---|---|
| `open` | sends `/opx77.admin` for the local player; the host decides whether a menu appears |
| `close` | takes the menu, and any form it put up, down |
| `state` | `open`, and which `screen` is up |

`open` answering `ok = true` means *asked*, not *allowed*: a player without the grant gets the
host's refusal, which `opx77_chat` toasts, and no menu.

Net events, all private to this resource — nothing outside it should raise or rely on them:

| Event | Direction | Carries |
|---|---|---|
| `opx77_admin:open` | server → client | the access map, after the opener command |
| `opx77_admin:roster` | server → client | roster rows, twenty per event |
| `opx77_admin:locations` | server → client | the destination list |
| `opx77_admin:access` | server → client | a fresh access map |
| `opx77_admin:travel` | server → client | noclip, speed, map pick, a clipboard row |
| `opx77_admin:answer` | server → client | a command's answer: the typed line, whether it was done, the text, and `report` or a toast kind; see [Answers](#answers) |
| `opx77_admin:refresh` | client → server | `roster`, `locations` or `access`; re-checked against `command.opx77.admin` with `Open77.acl.isAllowed` |

Every mutation arrives as a command through `open77:command:execute`, never as an event of this
resource's own: a net event carries no authorisation on this platform, and one added here would
be a hole.

## Not built, and why

| Wanted | Why not |
|---|---|
| Freeze a player | The platform has no binding that holds a player in place. Not faked. |
| True spectate | There is no free camera at a world point. `observe` is a teleport with noclip, and says so. |
| Invisibility | No binding hides a player from other clients. |
| Props, lights and effects | Set dressing, not staff work; the platform's own `open77_props` and `open77_effects` do it. |
| Vehicle speed governor | Client-local, not in every client build, and balance rather than moderation. |
| Door inspector | A developer tool, not a staff one. |
| Unban | No Lua binding lifts a ban; the server console's `unban` does. |
| A citizen id as a target | The server cannot map one to a player: that lives in `opx77_core`. |
| Destinations that survive a restart | That would need the database, and a staff tool must not require one. `self.pos` copies a config row. |
| A full vehicle and weapon catalogue | No enumeration binding exists, and shipping a generated list is its own maintenance. See [Catalogues](#catalogues). |
| Short aliases like `/tp`, `/noclip` | Each alias is a separate permission, and a bare name can shadow another resource's command. |
| Its own job, money and weather commands | `opx77_core` and `opx77_weather` own those, and are already ACL-gated. |
| Ping in the roster | Lua has no reader for it. |

## Locales

Player-facing text lives in `locales/en.lua` and `locales/fr.lua`, keyed `admin.<thing>`.
`LOCALE` in `config.lua` picks one; a key missing from it falls back to `en`, then to the key
itself, and a key present in one catalogue and not the other is named in a boot warning.

To add a language, copy `locales/en.lua` to `locales/<code>.lua`, change the code in the
`register` call and translate the values. Add `shared_script "locales/<code>.lua"` to
`open77.lua` beside the others, then set `LOCALE = "<code>"`.

Every answer a player reads is translated, including a staff member's. The answer the console
gets, `Open77.log` lines, the audit and the refusal codes stay English. Catalogue labels,
destination labels, vehicle flag names and weather preset names are data, not text, and are
shown as written.

## Community & Support

Join the Open77 and Opx77 communities to discover the platform, share your projects, and
connect with other developers.

<!-- TODO: replace with the final URLs before publication. -->

* [Open77](#)
* [Open77 GitHub](#)
* [OPX Discord](#)

## License

opx77_admin is licensed under the [**MIT License**](LICENSE).

Copyright © 2026 **Luis MOUTA**.

<p align="center">
    <sub>opx77_admin is an independent community project and is not affiliated with or
    endorsed by CD PROJEKT RED.</sub>
</p>
