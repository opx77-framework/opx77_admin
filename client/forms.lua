--- @author DemiAutomatic
--- @file client/forms.lua
--- @description Forms through opx77_input for values a menu row cannot hold.

OpxAdmin = OpxAdmin or {}

local Config = OPX_ADMIN_CONFIG
local Client = OpxAdmin.Client
local Text = OpxAdmin.Text

--- @author DemiAutomatic
--- @type {table}
--- @description The form helpers the menu calls.
OpxAdmin.Forms = {}
local Forms = OpxAdmin.Forms

--- @author DemiAutomatic
--- @type {string}
--- @description The resource that draws the forms.
local INPUT = 'opx77_input'

--- @author DemiAutomatic
--- @type {string}
--- @description The resource whose exports list jobs, gangs and money types.
local CORE = 'opx77_core'

--- @author DemiAutomatic
--- @type {string}
--- @description The local event opx77_input raises this resource's answers on.
local EVENT = 'opx77_admin:form'

--- @author DemiAutomatic
--- @type {table}
--- @description The LINKS config table, or an empty one.
local LINKS = type(Config.LINKS) == 'table' and Config.LINKS or {}

--- @author DemiAutomatic
--- @type {string}
--- @description Pattern a typed decimal number must match.
local NUMBER = '^%-?%d+%.?%d*$'

--- @author DemiAutomatic
--- @type {string}
--- @description Pattern a typed whole number must match.
local INTEGER = '^%-?%d+$'

--- @author DemiAutomatic
--- @type {integer|nil}
--- @description The open form's handle while one is up.
local handle

--- @author DemiAutomatic
--- @method menu
--- @description The menu module, read when called because it loads later.
--- @returns {table}
local function menu()
	return OpxAdmin.Menu
end

--- @author DemiAutomatic
--- @method text
--- @description One text field with its label and extra properties.
--- @param id {string}
--- @param labelKey {string}
--- @param extra {table|nil}
--- @returns {table}
local function text(id, labelKey, extra)
	local field = { id = id, label = locale(labelKey) }
	for key, value in pairs(extra or {}) do field[key] = value end
	return field
end

--- @author DemiAutomatic
--- @method groupOptions
--- @description Options from one of opx77_core's group exports, sorted by label.
--- @param export {string} GetJobs or GetGangs.
--- @param key {string} jobs or gangs.
--- @returns {table[]|nil}
local function groupOptions(export, key)
	local result = Client.Call(CORE, export)
	if result == nil or type(result[key]) ~= 'table' then return nil end
	local options = {}
	for name, group in pairs(result[key]) do
		options[#options + 1] = { label = ('%s (%s)'):format(tostring(group.label or name), name),
			value = name }
	end
	table.sort(options, function(left, right) return left.label < right.label end)
	return options
end

--- @author DemiAutomatic
--- @type {table<string, table>}
--- @description Every form by kind: how it is built and what it runs.
local FORMS = {}

--- @author DemiAutomatic
--- @type {table}
--- @description Health slider ending in the player health command.
FORMS.health = {
	build = function()
		return { title = locale('admin.form.health'), fields = {
			{ id = 'points', label = locale('admin.field.points'),
				slider = { min = 0, max = 100, step = 5, value = 100 } },
		} }
	end,
	submit = function(values, arg)
		local points = math.floor(Text.Finite(values.points) or 0)
		menu().Run({ 'opx77.admin.player.health', tostring(arg), ('%d'):format(points) })
	end,
}

--- @author DemiAutomatic
--- @type {table}
--- @description Armour points ending in the player armour command.
FORMS.armor = {
	build = function()
		return { title = locale('admin.form.armor'), fields = {
			text('points', 'admin.field.points', { value = '100', charset = 'digits', maxLength = 5,
				required = true }),
		} }
	end,
	submit = function(values, arg)
		menu().Run({ 'opx77.admin.player.armor', tostring(arg), values.points })
	end,
}

--- @author DemiAutomatic
--- @method groupForm
--- @description A job or gang form: group options and a typed grade.
--- @param export {string}
--- @param key {string}
--- @param titleKey {string}
--- @param link {string|nil}
--- @returns {table}
local function groupForm(export, key, titleKey, link)
	return {
		build = function()
			local options = groupOptions(export, key)
			if options == nil or #options == 0 then return nil end
			return { title = locale(titleKey), fields = {
				{ id = 'group', label = locale('admin.field.group'), options = options },
				text('grade', 'admin.field.grade', { value = '0', charset = 'digits', maxLength = 2,
					required = true }),
			} }
		end,
		submit = function(values, arg)
			if type(link) ~= 'string' then return end
			menu().Run({ link, tostring(arg), values.group, values.grade })
		end,
	}
end

--- @author DemiAutomatic
--- @type {table}
--- @description Job form ending in opx77_core's job command.
FORMS.job = groupForm('GetJobs', 'jobs', 'admin.form.job', LINKS.JOB)

--- @author DemiAutomatic
--- @type {table}
--- @description Gang form ending in opx77_core's gang command.
FORMS.gang = groupForm('GetGangs', 'gangs', 'admin.form.gang', LINKS.GANG)

--- @author DemiAutomatic
--- @type {table}
--- @description Money type and amount ending in opx77_core's money command.
FORMS.money = {
	build = function()
		local result = Client.Call(CORE, 'GetSharedConfig')
		local types = result and type(result.config) == 'table' and result.config.moneyTypes or nil
		if type(types) ~= 'table' then return nil end
		local options = {}
		for name in pairs(types) do options[#options + 1] = name end
		table.sort(options)
		if #options == 0 then return nil end
		return { title = locale('admin.form.money'), description = locale('admin.form.moneyHint'),
			fields = {
				{ id = 'type', label = locale('admin.field.moneyType'), options = options },
				text('amount', 'admin.field.amount', { pattern = INTEGER, maxLength = 10,
					required = true }),
			} }
	end,
	submit = function(values, arg)
		if type(LINKS.MONEY) ~= 'string' then return end
		menu().Run({ LINKS.MONEY, tostring(arg), values.type, values.amount })
	end,
}

--- @author DemiAutomatic
--- @method countForm
--- @description A count form for giving or removing items of a picked row.
--- @param titleKey {string}
--- @param commandName {string}
--- @param refresh {string|nil}
--- @returns {table}
local function countForm(titleKey, commandName, refresh)
	return {
		build = function(arg)
			if type(arg) ~= 'table' or type(arg.n) ~= 'string' then return nil end
			local held = Text.Integer(arg.c)
			local label = tostring(arg.l or arg.n)
			return { title = locale(titleKey),
				description = held and locale('admin.form.itemHeld', { label = label, count = held })
					or label,
				fields = {
					text('count', 'admin.field.count', { value = '1', charset = 'digits', maxLength = 6,
						required = true }),
				} }
		end,
		submit = function(values, arg)
			menu().Run({ commandName, tostring(arg.t), arg.n, values.count }, refresh)
		end,
	}
end

--- @author DemiAutomatic
--- @type {table}
--- @description Count of an item to give to a bag.
FORMS.itemGive = countForm('admin.form.itemGive', 'opx77.admin.inventory.give')

--- @author DemiAutomatic
--- @type {table}
--- @description Count of a stack to take from a bag.
FORMS.itemRemove = countForm('admin.form.itemRemove', 'opx77.admin.inventory.remove', 'bag')

--- @author DemiAutomatic
--- @type {table}
--- @description Count of ammunition items, starting at one full load.
FORMS.ammoGive = {
	build = function(arg)
		if type(arg) ~= 'table' or type(arg.n) ~= 'string' then return nil end
		local full = Text.Integer(arg.x)
		local label = tostring(arg.l or arg.n)
		return { title = locale('admin.form.ammoGive'),
			description = full and locale('admin.form.ammoLoad', { label = label, max = full }) or label,
			fields = {
				text('count', 'admin.field.count', { value = tostring(full or 1), charset = 'digits',
					maxLength = 6, required = true }),
			} }
	end,
	submit = function(values, arg)
		menu().Run({ 'opx77.admin.weapon.giveammo', tostring(arg.t), arg.n, values.count })
	end,
}

--- @author DemiAutomatic
--- @type {table}
--- @description Optional kick reason, confirmed before it runs.
FORMS.kick = {
	build = function()
		return { title = locale('admin.form.kick'), fields = {
			text('reason', 'admin.field.reason', { maxLength = 120 }),
		} }
	end,
	submit = function(values, arg)
		local tokens = { 'opx77.admin.moderate.kick', tostring(arg) }
		if Text.Clean(values.reason, 120) then tokens[3] = values.reason end
		menu().Confirm(tokens, 'admin.confirm.kick')
	end,
}

--- @author DemiAutomatic
--- @type {table}
--- @description Ban duration and optional reason, confirmed before it runs.
FORMS.ban = {
	build = function()
		local options = {}
		for _, word in ipairs(type(Config.BAN_DURATIONS) == 'table' and Config.BAN_DURATIONS or {}) do
			options[#options + 1] = tostring(word)
		end
		if #options == 0 then options[1] = 'perm' end
		return { title = locale('admin.form.ban'), fields = {
			{ id = 'duration', label = locale('admin.field.duration'), options = options },
			text('reason', 'admin.field.reason', { maxLength = 120 }),
		} }
	end,
	submit = function(values, arg)
		local tokens = { 'opx77.admin.moderate.ban', tostring(arg), values.duration }
		if Text.Clean(values.reason, 120) then tokens[4] = values.reason end
		menu().Confirm(tokens, 'admin.confirm.ban')
	end,
}

--- @author DemiAutomatic
--- @type {table}
--- @description Announcement text, confirmed before it reaches everybody.
FORMS.announce = {
	build = function()
		local maximum = math.floor(Text.Finite((Config.ANNOUNCE or {}).MAX_CHARACTERS) or 240)
		return { title = locale('admin.form.announce'), fields = {
			text('message', 'admin.field.message', { maxLength = maximum, required = true }),
		} }
	end,
	submit = function(values)
		menu().Confirm({ 'opx77.admin.world.announce', values.message }, 'admin.confirm.announce')
	end,
}

--- @author DemiAutomatic
--- @type {table}
--- @description A point and optional heading ending in the teleport command.
FORMS.coords = {
	build = function()
		return { title = locale('admin.form.coords'), fields = {
			text('x', 'admin.field.x', { pattern = NUMBER, maxLength = 12, required = true }),
			text('y', 'admin.field.y', { pattern = NUMBER, maxLength = 12, required = true }),
			text('z', 'admin.field.z', { pattern = NUMBER, maxLength = 12, required = true }),
			text('heading', 'admin.field.heading', { pattern = NUMBER, maxLength = 8 }),
		} }
	end,
	submit = function(values, arg)
		local tokens = { 'opx77.admin.player.tp', tostring(arg or 'me'), values.x, values.y, values.z }
		if Text.Finite(values.heading) then tokens[6] = values.heading end
		menu().Run(tokens)
	end,
}

--- @author DemiAutomatic
--- @type {table}
--- @description Name and label of a destination saved where the operator stands.
FORMS.location = {
	build = function()
		return { title = locale('admin.form.location'), fields = {
			text('name', 'admin.field.locationName', { pattern = '^[%w_%-]+$', maxLength = 32,
				required = true }),
			text('label', 'admin.field.label', { maxLength = 48 }),
		} }
	end,
	submit = function(values)
		local tokens = { 'opx77.admin.world.loc.add', values.name }
		if Text.Clean(values.label, 48) then tokens[3] = values.label end
		menu().Run(tokens, 'locations')
	end,
}

--- @author DemiAutomatic
--- @type {table}
--- @description A typed clock time ending in opx77_weather's time command.
FORMS.time = {
	build = function()
		return { title = locale('admin.form.time'), fields = {
			text('time', 'admin.field.time', { pattern = '^%d%d?:%d%d$', maxLength = 5, value = '12:00',
				required = true }),
		} }
	end,
	submit = function(values)
		if type(LINKS.TIME) ~= 'string' then return end
		menu().Run({ LINKS.TIME, values.time })
	end,
}

--- @author DemiAutomatic
--- @method OpxAdmin.Forms.Open
--- @description Takes the menu down and puts one form up.
--- @param kind {string}
--- @param arg {any}
--- @returns {boolean}
function OpxAdmin.Forms.Open(kind, arg)
	local form = FORMS[kind]
	if form == nil then return false end
	if not Client.Need(INPUT) then
		menu().Status(locale('admin.client.inputMissing'), false)
		return false
	end
	menu().Suspend()
	CreateThread(function()
		local spec = form.build(arg)
		if spec == nil then
			menu().Resume(locale('admin.client.formUnavailable'), false)
			return
		end
		spec.id = 'opx77_admin.' .. kind
		spec.event = EVENT
		spec.data = { form = kind, arg = arg }
		local opened, reason = Client.Call(INPUT, 'open', spec)
		if opened == nil then
			Open77.log.warn(('form %s did not open: %s'):format(kind, tostring(reason)))
			menu().Resume(locale('admin.client.formUnavailable'), false)
			return
		end
		handle = opened.handle
	end)
	return true
end

--- @author DemiAutomatic
--- @method OpxAdmin.Forms.IsOpen
--- @description Whether a form of this resource is up.
--- @returns {boolean}
function OpxAdmin.Forms.IsOpen()
	return handle ~= nil
end

--- @author DemiAutomatic
--- @method OpxAdmin.Forms.Close
--- @description Takes the open form down, if there is one.
function OpxAdmin.Forms.Close()
	if handle == nil then return end
	local closing = handle
	handle = nil
	CreateThread(function() Client.Call(INPUT, 'close', closing) end)
end

--- @author DemiAutomatic
--- @event opx77_admin:form
--- @description Turns a submitted form into its command, or brings the menu back.
--- @param payload {table}
AddEventHandler(EVENT, function(payload)
	if type(payload) ~= 'table' or payload.owner ~= Client.RESOURCE then return end
	if payload.handle ~= nil and handle ~= nil and payload.handle ~= handle then return end
	handle = nil
	local data = type(payload.data) == 'table' and payload.data or {}
	local form = FORMS[data.form]
	if payload.action ~= 'submit' or form == nil or type(payload.values) ~= 'table' then
		return menu().Resume()
	end
	form.submit(payload.values, data.arg)
end)
