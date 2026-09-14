-- Operator configuration. Shared, so a client downloads it: no secrets, and no grants. Who may
-- run what lives in acl.jsonc and nowhere else; nothing in this file authorises anybody.

OPX_ADMIN_CONFIG = {
  LOCALE = "en", -- which locales/<code>.lua player-facing text is read from

  -- Default keys, which each player can rebind in the pause menu; false registers none. A key
  -- sends /opx77.admin like the chat box does, so the ACL still decides who gets a menu.
  KEYS = {
    MENU = "F9", -- open the staff menu, or close it
    -- Noclip speed up and down, only while noclip is on; held, they repeat. Not the mouse
    -- wheel: no client API on this platform reads it. Each change still goes through
    -- /opx77.admin.self.speed, so the ACL decides.
    SPEED_UP = "PAGEUP",
    SPEED_DOWN = "PAGEDOWN",
  },

  RATE = {
    ACTION_MS = 400, -- floor between two runs of one mutating command, per operator
    READ_MS = 1000, -- the same for a command that only reads
    REFRESH_MS = 750, -- floor between two menu refresh requests, per operator
  },

  AUDIT_ENTRIES = 200, -- how many actions /opx77.admin.read.audit can look back over, this uptime
  TOAST_MS = 6000, -- how long a target's "an administrator did this" toast stays up

  PLACEMENT = {
    HEALTH = 1.0, -- fraction of full health after a move, 0.01..1.0
    GRACE_MS = 5000, -- respawn protection after a move
    BESIDE = { X = 1.5, Y = 0.0, Z = 0.0 }, -- offset from the other player on goto and bring
    OBSERVE_HEIGHT = 2.0, -- metres above the target an observer lands, noclip on
  },

  NOCLIP = {
    SPEED = 40.0, -- m/s, applied the first time noclip goes on; the native accepts 0.1..500
    MIN_SPEED = 1.0, -- the lowest the speed keys go, 0.1..500
    MAX_SPEED = 500.0, -- the highest, MIN_SPEED..500
    STEP = 0.15, -- one press changes the speed by this fraction of itself, 0.01..1
    -- quiet time after the last press before the speed is sent; never below RATE.ACTION_MS
    -- plus 100, or a second change inside the floor would be refused
    SEND_AFTER_MS = 500,
    PROMPTS = true, -- the controls in opx77_prompts' strip while noclip is on; false for none
  },

  ANNOUNCE = {
    DURATION_MS = 12000, -- toast lifetime on every client
    CHAT = true, -- also write the announcement into the chat box
    MAX_CHARACTERS = 240,
  },

  -- Ban durations the menu offers. A typed ban takes any `<n>s|m|h|d` up to 3650d, or `perm`.
  BAN_DURATIONS = { "1h", "1d", "7d", "30d", "perm" },

  VEHICLES = {
    SPAWN_OFFSET = { X = 3.0, Y = 0.0, Z = 0.25 }, -- world axes, from whoever it is spawned for
    PER_OWNER = 8, -- vehicles this resource keeps out per player at once
    NEAR_RADIUS = 30.0, -- how far `near` looks when the operator is not in a vehicle, metres
    -- Repairs safe with somebody aboard. `full` and `mechanical` may respawn the vehicle.
    OCCUPIED_REPAIRS = { glass = true, body = true, lights = true, tires = true, visual = true },
    FLAGS = { "locked", "engineOn", "lightsOn", "invulnerable" }, -- Open77.vehicles.flags names
  },

  -- Weapons and bags are opx77_inventory's: every weapon and inventory command calls its server
  -- exports, which need this resource in its EXPORTS.WRITERS (shipped so). Without it running
  -- they refuse; the rounds a give loads are ROUNDS in data/weapons.lua.
  INVENTORY = {
    RESOURCE = "opx77_inventory", -- match a renamed folder
    MAX_COUNT = 10000, -- the largest count inventory.give and inventory.remove accept
  },

  -- Commands of other OPX//77 resources the menu drives instead of doing the same thing twice.
  -- Match any rename made in those resources' own config; false removes the row.
  LINKS = {
    CHARACTERS = "opx77", -- opx77_core: every loaded character
    WHERE = "opx77.where", -- opx77_core: what the server believes about one player
    JOB = "opx77.job", -- opx77_core: <playerId|citizenId> <job> [grade]
    GANG = "opx77.gang", -- opx77_core: <playerId|citizenId> <gang> [grade]
    MONEY = "opx77.money", -- opx77_core: <playerId|citizenId> <TYPE> <amount>
    SAVE = "opx77.save", -- opx77_core: write every character now
    -- opx77_inventory: no export opens another character's bag on a staff screen, or lists the
    -- containers holding an item, so the menu runs its commands for those two
    INVENTORY_OPEN = "opx77.inventory.open", -- <playerId|citizenId>, in game
    INVENTORY_HOLDERS = "opx77.inventory.holders", -- <item>
    WEATHER_SET = "opx77.weather.set", -- opx77_weather
    WEATHER_NEXT = "opx77.weather.next",
    WEATHER_FREEZE = "opx77.weather.freeze",
    TIME = "opx77.weather.time",
    TIME_FREEZE = "opx77.weather.time.freeze",
  },

  -- What the World > Weather screen offers. Names from opx77_weather's own WEATHER table.
  WEATHER_PRESETS = { "sunny", "lightclouds", "cloudy", "rain", "heavyclouds", "fog",
                      "pollution", "sandstorm" },
  TIMES = { "06:00", "09:00", "12:00", "17:30", "20:30", "23:00", "03:00" },

  -- Saved destinations. NAME is what staff type: letters, digits, _ and -. Copy a row with
  -- /opx77.admin.self.pos while standing where you want one. Starter points; replace them.
  LOCATIONS = {
    { NAME = "watson", LABEL = "Watson, west", X = -667.14, Y = -382.61, Z = 9.16, HEADING = 0.0 },
    { NAME = "heights", LABEL = "Northwest heights", X = -1441.0, Y = 1269.0, Z = 123.0,
      HEADING = 180.0 },
    { NAME = "coast", LABEL = "Southwest coast", X = -1716.38, Y = -2421.28, Z = 62.59,
      HEADING = 0.0 },
  },
}
