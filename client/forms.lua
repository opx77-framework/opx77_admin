--- The values a menu row cannot hold -- a reason, an amount, a point -- asked for through
--- opx77_input. A form's answer becomes a command line like any row's, and the menu comes back
--- where it was.

OpxAdmin = OpxAdmin or {}

local Config = OPX_ADMIN_CONFIG
local Client = OpxAdmin.Client
local Text = OpxAdmin.Text

local Forms = {}
OpxAdmin.Forms = Forms

local INPUT = "opx77_input"
local CORE = "opx77_core"

--- The name opx77_input raises this resource's answers on. Private to this file.
local EVENT = "opx77_admin:form"

local LINKS = type(Config.LINKS) == "table" and Config.LINKS or {}

local NUMBER = "^%-?%d+%.?%d*$"
local INTEGER = "^%-?%d+$"

--- The form's handle while one is up.
local handle

---@return table
local function menu()
  return OpxAdmin.Menu
end

--- A text field.
---@return table
local function text(id, labelKey, extra)
  local field = { id = id, label = locale(labelKey) }
  for key, value in pairs(extra or {}) do field[key] = value end
  return field
end

--- Options from one of opx77_core's group exports, sorted by label. Coroutine only.
---@param export string  GetJobs | GetGangs
---@param key string     jobs | gangs
---@return table[]|nil
local function groupOptions(export, key)
  local result = Client.call(CORE, export)
  if result == nil or type(result[key]) ~= "table" then return nil end
  local options = {}
  for name, group in pairs(result[key]) do
    options[#options + 1] = { label = ("%s (%s)"):format(tostring(group.label or name), name),
                              value = name }
  end
  table.sort(options, function(left, right) return left.label < right.label end)
  return options
end

--- Every form: how to build it (coroutine) and what its answer runs.
---@type table<string, { build: fun(arg: any): table|nil, submit: fun(values: table, arg: any) }>
local FORMS = {}

FORMS.health = {
  build = function()
    return { title = locale("admin.form.health"), fields = {
      { id = "points", label = locale("admin.field.points"),
        slider = { min = 0, max = 100, step = 5, value = 100 } },
    } }
  end,
  submit = function(values, arg)
    -- a slider answers a float, and `%d` raises on one with a fraction
    local points = math.floor(Text.finite(values.points) or 0)
    menu().run({ "opx77.admin.player.health", tostring(arg), ("%d"):format(points) })
  end,
}

FORMS.armor = {
  build = function()
    return { title = locale("admin.form.armor"), fields = {
      text("points", "admin.field.points", { value = "100", charset = "digits", maxLength = 5,
                                             required = true }),
    } }
  end,
  submit = function(values, arg)
    menu().run({ "opx77.admin.player.armor", tostring(arg), values.points })
  end,
}

--- Job and gang share a shape; the grade is typed because its range depends on the group.
---@param export string
---@param key string
---@param titleKey string
---@param link string|nil
local function groupForm(export, key, titleKey, link)
  return {
    build = function()
      local options = groupOptions(export, key)
      if options == nil or #options == 0 then return nil end
      return { title = locale(titleKey), fields = {
        { id = "group", label = locale("admin.field.group"), options = options },
        text("grade", "admin.field.grade", { value = "0", charset = "digits", maxLength = 2,
                                             required = true }),
      } }
    end,
    submit = function(values, arg)
      if type(link) ~= "string" then return end
      menu().run({ link, tostring(arg), values.group, values.grade })
    end,
  }
end

FORMS.job = groupForm("GetJobs", "jobs", "admin.form.job", LINKS.JOB)
FORMS.gang = groupForm("GetGangs", "gangs", "admin.form.gang", LINKS.GANG)

FORMS.money = {
  build = function()
    local result = Client.call(CORE, "GetSharedConfig")
    local types = result and type(result.config) == "table" and result.config.moneyTypes or nil
    if type(types) ~= "table" then return nil end
    local options = {}
    for name in pairs(types) do options[#options + 1] = name end
    table.sort(options)
    if #options == 0 then return nil end
    return { title = locale("admin.form.money"), description = locale("admin.form.moneyHint"),
      fields = {
        { id = "type", label = locale("admin.field.moneyType"), options = options },
        text("amount", "admin.field.amount", { pattern = INTEGER, maxLength = 10,
                                               required = true }),
      } }
  end,
  submit = function(values, arg)
    if type(LINKS.MONEY) ~= "string" then return end
    menu().run({ LINKS.MONEY, tostring(arg), values.type, values.amount })
  end,
}

FORMS.kick = {
  build = function()
    return { title = locale("admin.form.kick"), fields = {
      text("reason", "admin.field.reason", { maxLength = 120 }),
    } }
  end,
  submit = function(values, arg)
    local tokens = { "opx77.admin.moderate.kick", tostring(arg) }
    if Text.clean(values.reason, 120) then tokens[3] = values.reason end
    menu().confirm(tokens, "admin.confirm.kick")
  end,
}

FORMS.ban = {
  build = function()
    local options = {}
    for _, word in ipairs(type(Config.BAN_DURATIONS) == "table" and Config.BAN_DURATIONS or {}) do
      options[#options + 1] = tostring(word)
    end
    if #options == 0 then options[1] = "perm" end
    return { title = locale("admin.form.ban"), fields = {
      { id = "duration", label = locale("admin.field.duration"), options = options },
      text("reason", "admin.field.reason", { maxLength = 120 }),
    } }
  end,
  submit = function(values, arg)
    local tokens = { "opx77.admin.moderate.ban", tostring(arg), values.duration }
    if Text.clean(values.reason, 120) then tokens[4] = values.reason end
    menu().confirm(tokens, "admin.confirm.ban")
  end,
}

FORMS.announce = {
  build = function()
    local maximum = math.floor(Text.finite((Config.ANNOUNCE or {}).MAX_CHARACTERS) or 240)
    return { title = locale("admin.form.announce"), fields = {
      text("message", "admin.field.message", { maxLength = maximum, required = true }),
    } }
  end,
  submit = function(values)
    menu().confirm({ "opx77.admin.world.announce", values.message }, "admin.confirm.announce")
  end,
}

FORMS.coords = {
  build = function()
    return { title = locale("admin.form.coords"), fields = {
      text("x", "admin.field.x", { pattern = NUMBER, maxLength = 12, required = true }),
      text("y", "admin.field.y", { pattern = NUMBER, maxLength = 12, required = true }),
      text("z", "admin.field.z", { pattern = NUMBER, maxLength = 12, required = true }),
      text("heading", "admin.field.heading", { pattern = NUMBER, maxLength = 8 }),
    } }
  end,
  submit = function(values, arg)
    local tokens = { "opx77.admin.player.tp", tostring(arg or "me"), values.x, values.y, values.z }
    if Text.finite(values.heading) then tokens[6] = values.heading end
    menu().run(tokens)
  end,
}

FORMS.location = {
  build = function()
    return { title = locale("admin.form.location"), fields = {
      text("name", "admin.field.locationName", { pattern = "^[%w_%-]+$", maxLength = 32,
                                                  required = true }),
      text("label", "admin.field.label", { maxLength = 48 }),
    } }
  end,
  submit = function(values)
    local tokens = { "opx77.admin.world.loc.add", values.name }
    if Text.clean(values.label, 48) then tokens[3] = values.label end
    menu().run(tokens, "locations")
  end,
}

FORMS.time = {
  build = function()
    return { title = locale("admin.form.time"), fields = {
      text("time", "admin.field.time", { pattern = "^%d%d?:%d%d$", maxLength = 5, value = "12:00",
                                         required = true }),
    } }
  end,
  submit = function(values)
    if type(LINKS.TIME) ~= "string" then return end
    menu().run({ LINKS.TIME, values.time })
  end,
}

--- Put a form up. The menu is taken down first -- a form and a list both reading the arrow
--- keys is one too many -- and comes back when the form is answered either way.
---@param kind string
---@param arg any
---@return boolean asked
function Forms.open(kind, arg)
  local form = FORMS[kind]
  if form == nil then return false end
  if not Client.need(INPUT) then
    menu().status(locale("admin.client.inputMissing"), false)
    return false
  end
  menu().suspend()
  CreateThread(function()
    local spec = form.build(arg)
    if spec == nil then
      menu().resume(locale("admin.client.formUnavailable"), false)
      return
    end
    spec.id = "opx77_admin." .. kind
    spec.event = EVENT
    spec.data = { form = kind, arg = arg }
    local opened, reason = Client.call(INPUT, "open", spec)
    if opened == nil then
      Open77.log.warn(("form %s did not open: %s"):format(kind, tostring(reason)))
      menu().resume(locale("admin.client.formUnavailable"), false)
      return
    end
    handle = opened.handle
  end)
  return true
end

---@return boolean
function Forms.isOpen()
  return handle ~= nil
end

function Forms.close()
  if handle == nil then return end
  local closing = handle
  handle = nil
  CreateThread(function() Client.call(INPUT, "close", closing) end)
end

--- The answer. Any resource on this machine can raise this name, so the shape and the owner are
--- checked; the command line it turns into is gated by the host like any other.
AddEventHandler(EVENT, function(payload)
  if type(payload) ~= "table" or payload.owner ~= Client.RESOURCE then return end
  if payload.handle ~= nil and handle ~= nil and payload.handle ~= handle then return end
  handle = nil
  local data = type(payload.data) == "table" and payload.data or {}
  local form = FORMS[data.form]
  if payload.action ~= "submit" or form == nil or type(payload.values) ~= "table" then
    return menu().resume()
  end
  form.submit(payload.values, data.arg)
end)
