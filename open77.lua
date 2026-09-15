--- @author DemiAutomatic
--- @file open77.lua
--- @description Resource manifest declaring scripts, permissions and reload policy.

resource "opx77_admin"
version "0.2.0"
open77_version ">=0.0.1"
auto_start true

reload_policy "local"

shared_script "config.lua"
shared_script "shared/text.lua"
shared_script "shared/locale.lua"
shared_script "locales/en.lua"
shared_script "locales/fr.lua"
shared_script "data/vehicles.lua"
shared_script "data/weapons.lua"
shared_script "shared/catalog.lua"
shared_script "shared/catalog-1.lua"
shared_script "shared/catalog-2.lua"
shared_script "shared/catalog-3.lua"
shared_script "shared/catalog-4.lua"

server_script "server/main.lua"
server_script "server/players.lua"
server_script "server/vehicles.lua"
server_script "server/inventory.lua"
server_script "server/weapons.lua"
server_script "server/world.lua"
server_script "server/menu.lua"

client_script "client/main.lua"
client_script "client/keys.lua"
client_script "client/controls.lua"
client_script "client/forms.lua"
client_script "client/menu.lua"
client_script "client/exports.lua"

permissions {
  "network.events",
  "acl.read",
  "players.life.read",
  "players.life.kill",
  "players.life.respawn",
  "players.life.revive",
  "players.damage.read",
  "players.damage.apply",
  "players.stats.read",
  "players.stats.apply",
  "players.disconnect",
  "players.access",
  "world.vehicles",
  "player.travel",
  "clipboard.write",
  "input.actions",
}
