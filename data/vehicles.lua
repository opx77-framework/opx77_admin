-- The vehicles staff may spawn. Definitions, not settings, and this list IS the allowlist: a
-- record that is not a row here never reaches Open77.vehicles.create, whatever a client types.
--
-- The platform has no server-side call that enumerates vehicle records, so this is a short,
-- hand-picked starter list. Extend it: add a row with a NAME staff type (letters, digits, _ and
-- -), a LABEL, a CLASS key from CLASSES, and the exact TweakDB RECORD. A record the engine does
-- not know is refused at spawn time with the host's own reason.

OPX_ADMIN_VEHICLES = {
  CLASSES = { -- menu order
    { KEY = "street", LABEL = "Street" },
    { KEY = "sport", LABEL = "Sport" },
    { KEY = "bike", LABEL = "Motorcycles" },
  },

  VEHICLES = {
    { NAME = "galena", LABEL = "Thorton Galena", CLASS = "street",
      RECORD = "Vehicle.v_standard2_thorton_galena_player" },
    { NAME = "colby", LABEL = "Thorton Colby", CLASS = "street",
      RECORD = "Vehicle.v_standard2_thorton_colby_player" },
    { NAME = "cortes", LABEL = "Villefort Cortes", CLASS = "street",
      RECORD = "Vehicle.v_standard2_villefort_cortes_player" },
    { NAME = "supron", LABEL = "Mahir Supron", CLASS = "street",
      RECORD = "Vehicle.v_standard25_mahir_supron_player" },
    { NAME = "hella", LABEL = "Archer Hella", CLASS = "street",
      RECORD = "Vehicle.v_standard2_archer_hella_player" },
    { NAME = "maimai", LABEL = "Makigai MaiMai", CLASS = "street",
      RECORD = "Vehicle.v_standard2_makigai_maimai_player" },

    { NAME = "turbo", LABEL = "Quadra Turbo-R", CLASS = "sport",
      RECORD = "Vehicle.v_sport1_quadra_turbo_player" },
    { NAME = "type66", LABEL = "Quadra Type-66", CLASS = "sport",
      RECORD = "Vehicle.v_sport2_quadra_type66_player" },
    { NAME = "shion", LABEL = "Mizutani Shion", CLASS = "sport",
      RECORD = "Vehicle.v_sport2_mizutani_shion_player" },
    { NAME = "alvarado", LABEL = "Villefort Alvarado", CLASS = "sport",
      RECORD = "Vehicle.v_sport2_villefort_alvarado_player" },
    { NAME = "caliburn", LABEL = "Rayfield Caliburn", CLASS = "sport",
      RECORD = "Vehicle.v_sport1_rayfield_caliburn_player" },

    { NAME = "arch", LABEL = "Arch Nazare", CLASS = "bike",
      RECORD = "Vehicle.v_sportbike2_arch_player" },
    { NAME = "kusanagi", LABEL = "Yaiba Kusanagi", CLASS = "bike",
      RECORD = "Vehicle.v_sportbike1_yaiba_kusanagi_player" },
    { NAME = "apollo", LABEL = "Brennan Apollo", CLASS = "bike",
      RECORD = "Vehicle.v_sportbike3_brennan_apollo_player" },
  },
}
