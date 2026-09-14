-- The weapons staff may hand out. Definitions, not settings, and this list IS the allowlist: a
-- record that is not a row here never reaches Open77.weapons.assign, whatever a client types.
--
-- The platform has no server-side call that enumerates item records, so this is a short,
-- hand-picked starter list. Extend it: add a row with a NAME staff type, a LABEL, a CLASS key
-- from CLASSES, and the exact TweakDB RECORD. Only the three ordinary weapon slots are
-- supported by the platform, so grenades, heavy weapons and arm cyberware do not belong here.
--
-- The ammunition TYPE is never chosen: the engine reads it off the weapon record. A class only
-- says whether there is ammunition at all (AMMO) and how many spare rounds a give loads
-- (RESERVE). The engine caps what a character carries per ammo type, on reserve plus magazine;
-- an ask above that cap is partly applied and then reported as refused, so keep RESERVE
-- modest. Precision rifles draw rifle ammunition, not sniper ammunition.

OPX_ADMIN_WEAPONS = {
  CLASSES = { -- menu order
    { KEY = "handgun", LABEL = "Handguns", AMMO = true, RESERVE = 300 },
    { KEY = "revolver", LABEL = "Revolvers", AMMO = true, RESERVE = 200 },
    { KEY = "smg", LABEL = "SMGs", AMMO = true, RESERVE = 600 },
    { KEY = "rifle", LABEL = "Assault rifles", AMMO = true, RESERVE = 600 },
    { KEY = "precision", LABEL = "Precision rifles", AMMO = true, RESERVE = 300 },
    { KEY = "sniper", LABEL = "Sniper rifles", AMMO = true, RESERVE = 100 },
    { KEY = "shotgun", LABEL = "Shotguns", AMMO = true, RESERVE = 120 },
    { KEY = "lmg", LABEL = "Light machine guns", AMMO = true, RESERVE = 600 },
    { KEY = "melee", LABEL = "Melee", AMMO = false, RESERVE = 0 },
  },

  WEAPONS = {
    { NAME = "lexington", LABEL = "M-10AF Lexington", CLASS = "handgun",
      RECORD = "Items.Preset_Lexington_Default" },
    { NAME = "unity", LABEL = "Unity", CLASS = "handgun",
      RECORD = "Items.Preset_Unity_Default" },
    { NAME = "nue", LABEL = "Nue", CLASS = "handgun",
      RECORD = "Items.Preset_Nue_Default" },
    { NAME = "overture", LABEL = "Overture", CLASS = "revolver",
      RECORD = "Items.Preset_Overture_Default" },
    { NAME = "saratoga", LABEL = "M221 Saratoga", CLASS = "smg",
      RECORD = "Items.Preset_Saratoga_Default" },
    { NAME = "ajax", LABEL = "Ajax", CLASS = "rifle",
      RECORD = "Items.Preset_Ajax_Default" },
    { NAME = "copperhead", LABEL = "Copperhead", CLASS = "rifle",
      RECORD = "Items.Preset_Copperhead_Default" },
    { NAME = "masamune", LABEL = "Masamune", CLASS = "rifle",
      RECORD = "Items.Preset_Masamune_Default" },
    { NAME = "achilles", LABEL = "Achilles", CLASS = "precision",
      RECORD = "Items.Preset_Achilles_Default" },
    { NAME = "grad", LABEL = "SPT32 Grad", CLASS = "sniper",
      RECORD = "Items.Preset_Grad_Default" },
    { NAME = "nekomata", LABEL = "Nekomata", CLASS = "sniper",
      RECORD = "Items.Preset_Nekomata_Default" },
    { NAME = "carnage", LABEL = "Carnage", CLASS = "shotgun",
      RECORD = "Items.Preset_Carnage_Default" },
    { NAME = "defender", LABEL = "M2067 Defender", CLASS = "lmg",
      RECORD = "Items.Preset_Defender_Default" },
    { NAME = "katana", LABEL = "Katana", CLASS = "melee",
      RECORD = "Items.Preset_Katana_Default" },
    { NAME = "knife", LABEL = "Knife", CLASS = "melee",
      RECORD = "Items.Preset_Knife_Default" },
    { NAME = "machete", LABEL = "Machete", CLASS = "melee",
      RECORD = "Items.Preset_Machete_Default" },
    { NAME = "hammer", LABEL = "Hammer", CLASS = "melee",
      RECORD = "Items.Preset_Hammer_Default" },
  },
}
