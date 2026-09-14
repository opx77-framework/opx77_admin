resource "opx77_admin"
version "0.1.0"
open77_version ">=0.0.1"
auto_start true

reload_policy "local" -- no CEF surface of its own: opx77_menu and opx77_input draw everything,
                      -- and both drop this resource's menu and form when its generation changes

-- No dependencies declared. A declared dependency is hard, and a staff tool that refuses to
-- start because opx77_menu is missing is no tool at the moment somebody has to be kicked: every
-- command still runs from the chat box and the console without the menu.

-- Load order is manifest order. The catalogue comes before every file that renders a string,
-- the two data files before the index built over them, server/main.lua before every file that
-- registers through it, and server/menu.lua after all of them: the access map it sends lists
-- what they registered.
shared_script "config.lua"
shared_script "shared/text.lua"
shared_script "shared/locale.lua" -- after config.lua: LOCALE is read at load
shared_script "locales/en.lua" -- registered right after the catalogue, so no file
shared_script "locales/fr.lua" -- below calls locale() against an empty one
shared_script "data/vehicles.lua"
shared_script "data/weapons.lua"
shared_script "shared/catalog.lua" -- after both data files: it indexes them

server_script "server/main.lua"
server_script "server/players.lua"
server_script "server/vehicles.lua"
server_script "server/weapons.lua"
server_script "server/world.lua"
server_script "server/menu.lua"

client_script "client/main.lua"
client_script "client/forms.lua"
client_script "client/menu.lua" -- after forms.lua: a row can open a form
client_script "client/exports.lua" -- last: publishing the surface claims it exists

permissions {
  -- Both halves: the snapshot and travel pushes out, the refresh request in, and the menu's
  -- command lines sent through open77:command:execute. It is also the only grant the weapon
  -- commands need: Open77.weapons on the server is a relay over net events.
  "network.events",

  -- Server: Open77.acl.isAllowed. Re-checks the refresh event and the travel modes against
  -- the same command.<name> grants the host resolves, and filters chat suggestions. Read-only;
  -- this resource never writes a role or a permission.
  "acl.read",

  "players.life.read", -- the life state and the readiness gate, before anything is done to anybody
  "players.life.kill", -- /kill, and the first half of every placement
  "players.life.respawn", -- placement is kill -> respawn, never a transform write
  "players.life.revive", -- /revive, and the recovery when a placement's respawn is refused

  -- getHealth / setHealth / setArmor / setGodMode. Which of these two families gates which
  -- binding is not documented; the platform's own admin package declares both, so this does.
  "players.damage.read",
  "players.damage.apply",
  "players.stats.read",
  "players.stats.apply",

  "players.disconnect", -- Open77.players.kick
  "players.access", -- Open77.access.ban: the server-local ban list, never the ACL

  "world.vehicles", -- spawn, repair, flag and remove the vehicles this resource creates

  -- Client: Open77.travel.setNoclip / setNoclipSpeed / setMapPick, applied only when an
  -- ACL-gated server command says so.
  "player.travel",

  "clipboard.write", -- client: /opx77.admin.self.pos copies a LOCATIONS row to paste into config

  -- Deliberately not requested: database.access (nothing here persists to the database),
  -- world.props, world.effects, vehicles.performance, input.actions, local.events.
}
