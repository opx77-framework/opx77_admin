-- How the staff menu groups weapons. Definitions, not settings.
--
-- The weapons themselves are not listed here any more. A weapon is an item of opx77_inventory,
-- declared in that resource's data/weapons.lua with its TweakDB record, its class and the
-- ammunition that loads it, and this resource reads that catalogue through the inventory's
-- GetItems export. One list, so a weapon staff can hand out is always one the inventory backs;
-- a name that is not a weapon item there is refused, whatever a client types.
--
-- A class here gives a menu order and a LABEL, nothing else: a weapon is given empty, and its
-- rounds are ammunition items of that same catalogue, given on their own. A class the inventory
-- uses and this file does not name is listed last, under its key.

OPX_ADMIN_WEAPONS = {
	CLASSES = { -- menu order; KEY matches CLASS in opx77_inventory's data/weapons.lua
		{ KEY = 'handgun', LABEL = 'Handguns' },
		{ KEY = 'revolver', LABEL = 'Revolvers' },
		{ KEY = 'smg', LABEL = 'SMGs' },
		{ KEY = 'rifle', LABEL = 'Assault rifles' },
		{ KEY = 'precision', LABEL = 'Precision rifles' },
		{ KEY = 'sniper', LABEL = 'Sniper rifles' },
		{ KEY = 'shotgun', LABEL = 'Shotguns' },
		{ KEY = 'lmg', LABEL = 'Light machine guns' },
		{ KEY = 'melee', LABEL = 'Melee' },
	},
}
