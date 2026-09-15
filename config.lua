--- @author DemiAutomatic
--- @file config.lua
--- @description Operator configuration, shared with clients: no secrets and no grants.
--- @field LOCALE {string} Catalogue code in locales/ player-facing text is read from.
--- @field KEYS {table} Default keys players can rebind; false registers none.
--- @field KEYS.MENU {string|false} Opens the staff menu, or closes it.
--- @field KEYS.SPEED_UP {string|false} Raises noclip speed while noclip is on; repeats held.
--- @field KEYS.SPEED_DOWN {string|false} Lowers noclip speed while noclip is on; repeats held.
--- @field RATE {table} Per-operator floors between command runs, in milliseconds.
--- @field RATE.ACTION_MS {integer} Floor between two runs of one mutating command.
--- @field RATE.READ_MS {integer} Floor between two runs of one reading command.
--- @field RATE.REFRESH_MS {integer} Floor between two menu refresh requests.
--- @field AUDIT_ENTRIES {integer} Actions read.audit can look back over this uptime; at least 10.
--- @field TOAST_MS {integer} How long a target's staff action toast stays up.
--- @field PLACEMENT {table} How a moved player lands.
--- @field PLACEMENT.HEALTH {number} Fraction of full health after a move, 0.01..1.0.
--- @field PLACEMENT.GRACE_MS {integer} Respawn protection after a move, in milliseconds.
--- @field PLACEMENT.BESIDE {table} Offset from the other player on goto and bring.
--- @field PLACEMENT.BESIDE.X {number} Metres along the world X axis.
--- @field PLACEMENT.BESIDE.Y {number} Metres along the world Y axis.
--- @field PLACEMENT.BESIDE.Z {number} Metres along the world Z axis.
--- @field PLACEMENT.OBSERVE_HEIGHT {number} Metres above the target an observer lands, noclip on.
--- @field NOCLIP {table} Noclip speed and its on-screen controls.
--- @field NOCLIP.SPEED {number} Metres per second the first time noclip goes on, 0.1..500.
--- @field NOCLIP.MIN_SPEED {number} Lowest speed the keys reach, 0.1..500.
--- @field NOCLIP.MAX_SPEED {number} Highest speed the keys reach, MIN_SPEED..500.
--- @field NOCLIP.STEP {number} Fraction of the speed one press changes, 0.01..1.
--- @field NOCLIP.SEND_AFTER_MS {integer} Quiet time before sending; never below RATE.ACTION_MS plus 100.
--- @field NOCLIP.PROMPTS {boolean} Travel controls in opx77_prompts' strip; false for none.
--- @field TAGS {table} Name tags staff see above nearby players.
--- @field TAGS.DISTANCE {number} Metres a tag shows within, 1..100.
--- @field TAGS.FADE_START {number} Fraction of DISTANCE where a tag starts fading, 0..1.
--- @field TAGS.HEAD_LIFT {number} Metres above the head slot a tag sits, 0..2.
--- @field TAGS.HEAD_OFFSET_Z {number} Metres above the body when the head is unreadable, 0.5..3.
--- @field TAGS.UPDATE_MS {integer} Milliseconds between two tag updates on the client, 50..2000.
--- @field TAGS.REFRESH_MS {integer} Milliseconds between two name lists from the server, at least 500.
--- @field TAGS.MAX {integer} Most tags drawn at once, nearest first, 1..32.
--- @field TAGS.OWN {boolean} Also tag yourself, in third person only.
--- @field TAGS.HIDE_IN_FIRST_PERSON {boolean} Hide every tag while the view is first person.
--- @field TAGS.TECHNICAL {boolean} Show the player id in the tag's key box.
--- @field TAGS.BADGE {boolean} Mark staff who may open the menu with a badge.
--- @field TAGS.COLORS {table} Tag colours, #RRGGBB; the fade adds the alpha.
--- @field TAGS.COLORS.TEXT {string} The name.
--- @field TAGS.COLORS.ACCENT {string} Border and id box of a player's tag.
--- @field TAGS.COLORS.STAFF {string} Border and id box of a staff member's tag.
--- @field TAGS.COLORS.BACKGROUND {string} The tag's fill.
--- @field ANNOUNCE {table} How an announcement reaches every player.
--- @field ANNOUNCE.DURATION_MS {integer} Announcement toast lifetime on every client.
--- @field ANNOUNCE.CHAT {boolean} Also write the announcement into the chat box.
--- @field ANNOUNCE.MAX_CHARACTERS {integer} Longest announcement, in characters.
--- @field BAN_DURATIONS {string[]} Durations the ban form offers; typed bans take any duration.
--- @field VEHICLES {table} Vehicle spawning, the near search and repairs.
--- @field VEHICLES.SPAWN_OFFSET {table} World-axis offset from whoever the vehicle is for.
--- @field VEHICLES.SPAWN_OFFSET.X {number} Metres along the world X axis.
--- @field VEHICLES.SPAWN_OFFSET.Y {number} Metres along the world Y axis.
--- @field VEHICLES.SPAWN_OFFSET.Z {number} Metres along the world Z axis.
--- @field VEHICLES.PER_OWNER {integer} Vehicles this resource keeps out per player at once.
--- @field VEHICLES.NEAR_RADIUS {number} Metres near looks when the operator is on foot.
--- @field VEHICLES.OCCUPIED_REPAIRS {table<string, boolean>} Repair scopes allowed with somebody aboard.
--- @field VEHICLES.FLAGS {string[]} Open77.vehicles.flags names the flag command may toggle.
--- @field INVENTORY {table} The opx77_inventory the weapon and bag commands call.
--- @field INVENTORY.RESOURCE {string} Inventory resource name, to match a renamed folder.
--- @field INVENTORY.MAX_COUNT {integer} Largest count an item or ammunition give or removal accepts.
--- @field LINKS {table} Other resources' command names the menu drives; false removes the row.
--- @field LINKS.CHARACTERS {string|false} opx77_core: every loaded character.
--- @field LINKS.WHERE {string|false} opx77_core: what the server believes about one player.
--- @field LINKS.JOB {string|false} opx77_core: sets a job and grade.
--- @field LINKS.GANG {string|false} opx77_core: sets a gang and grade.
--- @field LINKS.MONEY {string|false} opx77_core: adds or takes money of one type.
--- @field LINKS.SAVE {string|false} opx77_core: writes every character now.
--- @field LINKS.INVENTORY_OPEN {string|false} opx77_inventory: opens a character's bag in game.
--- @field LINKS.INVENTORY_HOLDERS {string|false} opx77_inventory: lists the containers holding an item.
--- @field LINKS.WEATHER_SET {string|false} opx77_weather: sets a weather preset.
--- @field LINKS.WEATHER_NEXT {string|false} opx77_weather: rolls the next weather.
--- @field LINKS.WEATHER_FREEZE {string|false} opx77_weather: holds or releases the weather.
--- @field LINKS.TIME {string|false} opx77_weather: sets the time of day.
--- @field LINKS.TIME_FREEZE {string|false} opx77_weather: holds or releases the clock.
--- @field WEATHER_PRESETS {string[]} Weather names the sky screen offers, from opx77_weather.
--- @field TIMES {string[]} Times of day the time screen offers, HH:MM.
--- @field LOCATIONS {table[]} Saved destinations; self.pos copies a row.
--- @field LOCATIONS[].NAME {string} What staff type: letters, digits, _ and -.
--- @field LOCATIONS[].LABEL {string} What the menu shows.
--- @field LOCATIONS[].X {number} World X coordinate.
--- @field LOCATIONS[].Y {number} World Y coordinate.
--- @field LOCATIONS[].Z {number} World Z coordinate.
--- @field LOCATIONS[].HEADING {number} Heading in degrees on arrival.

OPX_ADMIN_CONFIG = {
	LOCALE = 'en',

	KEYS = {
		MENU = 'F9',
		SPEED_UP = 'PAGEUP',
		SPEED_DOWN = 'PAGEDOWN',
	},

	RATE = {
		ACTION_MS = 400,
		READ_MS = 1000,
		REFRESH_MS = 750,
	},

	AUDIT_ENTRIES = 200,
	TOAST_MS = 6000,

	PLACEMENT = {
		HEALTH = 1.0,
		GRACE_MS = 5000,
		BESIDE = { X = 1.5, Y = 0.0, Z = 0.0 },
		OBSERVE_HEIGHT = 2.0,
	},

	NOCLIP = {
		SPEED = 40.0,
		MIN_SPEED = 1.0,
		MAX_SPEED = 500.0,
		STEP = 0.15,
		SEND_AFTER_MS = 500,
		PROMPTS = true,
	},

	TAGS = {
		DISTANCE = 25.0,
		FADE_START = 0.55,
		HEAD_LIFT = 0.35,
		HEAD_OFFSET_Z = 2.05,
		UPDATE_MS = 250,
		REFRESH_MS = 2000,
		MAX = 32,
		OWN = false,
		HIDE_IN_FIRST_PERSON = false,
		TECHNICAL = true,
		BADGE = true,
		COLORS = {
			TEXT = '#F2F6F8',
			ACCENT = '#FCEE0A',
			STAFF = '#22D8E2',
			BACKGROUND = '#0A1220',
		},
	},

	ANNOUNCE = {
		DURATION_MS = 12000,
		CHAT = true,
		MAX_CHARACTERS = 240,
	},

	BAN_DURATIONS = { '1h', '1d', '7d', '30d', 'perm' },

	VEHICLES = {
		SPAWN_OFFSET = { X = 3.0, Y = 0.0, Z = 0.25 },
		PER_OWNER = 8,
		NEAR_RADIUS = 30.0,
		OCCUPIED_REPAIRS = { glass = true, body = true, lights = true, tires = true, visual = true },
		FLAGS = { 'locked', 'engineOn', 'lightsOn', 'invulnerable' },
	},

	INVENTORY = {
		RESOURCE = 'opx77_inventory',
		MAX_COUNT = 10000,
	},

	LINKS = {
		CHARACTERS = 'opx77',
		WHERE = 'opx77.where',
		JOB = 'opx77.job',
		GANG = 'opx77.gang',
		MONEY = 'opx77.money',
		SAVE = 'opx77.save',
		INVENTORY_OPEN = 'opx77.inventory.open',
		INVENTORY_HOLDERS = 'opx77.inventory.holders',
		WEATHER_SET = 'opx77.weather.set',
		WEATHER_NEXT = 'opx77.weather.next',
		WEATHER_FREEZE = 'opx77.weather.freeze',
		TIME = 'opx77.weather.time',
		TIME_FREEZE = 'opx77.weather.time.freeze',
	},

	WEATHER_PRESETS = { 'sunny', 'lightclouds', 'cloudy', 'rain', 'heavyclouds', 'fog',
		'pollution', 'sandstorm' },
	TIMES = { '06:00', '09:00', '12:00', '17:30', '20:30', '23:00', '03:00' },

	LOCATIONS = {
		{ NAME = 'watson', LABEL = 'Watson, west', X = -667.14, Y = -382.61, Z = 9.16, HEADING = 0.0 },
		{ NAME = 'heights', LABEL = 'Northwest heights', X = -1441.0, Y = 1269.0, Z = 123.0,
			HEADING = 180.0 },
		{ NAME = 'coast', LABEL = 'Southwest coast', X = -1716.38, Y = -2421.28, Z = 62.59,
			HEADING = 0.0 },
		{ NAME = 'stoop', LABEL = 'Watson, King Stoop forecourt', X = -410.22, Y = 722.73, Z = 115.0,
			HEADING = 147.0 },
		{ NAME = 'northside', LABEL = 'Watson, north promenade', X = -469.47, Y = 930.99, Z = 56.45,
			HEADING = -68.0 },
		{ NAME = 'junction', LABEL = 'Watson, lower junction', X = -644.91, Y = 1019.37, Z = 36.56,
			HEADING = 75.5 },
		{ NAME = 'underpass', LABEL = 'Watson, lower underpass', X = -701.49, Y = 1033.97, Z = 35.71,
			HEADING = -104.5 },
		{ NAME = 'dealer', LABEL = 'Westbrook, vehicle dealership', X = -1442.2, Y = 127.4, Z = 18.0,
			HEADING = 0.0 },
		{ NAME = 'racegrid', LABEL = 'Westbrook, race grid', X = -1450.2, Y = 119.9, Z = 14.8,
			HEADING = 200.0 },
		{ NAME = 'lab', LABEL = 'East, laboratory', X = 1669.75, Y = -739.12, Z = 49.86,
			HEADING = 0.0 },
		{ NAME = 'arena', LABEL = 'Badlands, arena', X = 381.36, Y = -2401.79, Z = 181.99,
			HEADING = 0.0 },
	},
}
