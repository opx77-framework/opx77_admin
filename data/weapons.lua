-- How the staff menu groups weapons, and how many rounds a give loads. Definitions, not settings.
--
-- The weapons themselves are not listed here any more. A weapon is an item of opx77_inventory,
-- declared in that resource's data/weapons.lua with its TweakDB record, its class and the
-- ammunition that loads it, and this resource reads that catalogue through the inventory's
-- GetItems export. One list, so a weapon staff can hand out is always one the inventory backs;
-- a name that is not a weapon item there is refused, whatever a client types.
--
-- A class here gives a menu order, a LABEL, and ROUNDS: the rounds a give puts on the weapon
-- item when none are typed. The inventory caps it at its ammunition's MAX, and a melee weapon
-- carries none. A class the inventory uses and this file does not name is listed last, under
-- its key, with a full load.

OPX_ADMIN_WEAPONS = {
  CLASSES = { -- menu order; KEY matches CLASS in opx77_inventory's data/weapons.lua
    { KEY = "handgun", LABEL = "Handguns", ROUNDS = 300 },
    { KEY = "revolver", LABEL = "Revolvers", ROUNDS = 150 },
    { KEY = "smg", LABEL = "SMGs", ROUNDS = 600 },
    { KEY = "rifle", LABEL = "Assault rifles", ROUNDS = 600 },
    { KEY = "precision", LABEL = "Precision rifles", ROUNDS = 300 },
    { KEY = "sniper", LABEL = "Sniper rifles", ROUNDS = 100 },
    { KEY = "shotgun", LABEL = "Shotguns", ROUNDS = 120 },
    { KEY = "lmg", LABEL = "Light machine guns", ROUNDS = 600 },
    { KEY = "melee", LABEL = "Melee", ROUNDS = 0 },
  },
}
