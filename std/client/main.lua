---@meta

--- The client helpers the other client files call: clock, export calls, answers, commands.
OpxAdmin.Client = {}

--- This resource's name, as the host reports it.
---@type string
OpxAdmin.Client.RESOURCE = ''

--- The scheduler clock in milliseconds. A non-finite reading holds the last finite one.
---@return integer
function OpxAdmin.Client.NowMs() end

--- Whether another resource is in the `running` state.
---@param resource string
---@return boolean
function OpxAdmin.Client.Running(resource) end

--- One `Open77.travel` function, or nil when this client build lacks it.
---@param name string
---@return function|nil
function OpxAdmin.Client.TravelNative(name) end

--- One call to another resource's client export. Coroutine only. The third return says whether
--- the target answered at all: a refusal (any answer whose `ok` is not true) is authoritative, a
--- call that never landed says nothing.
---@param resource string
---@param name string
---@param ... any
---@return table|nil result
---@return string|nil reason
---@return boolean answered
function OpxAdmin.Client.Call(resource, name, ...) end

--- Whether a soft dependency runs; logs its absence once per resource.
---@param resource string
---@return boolean
function OpxAdmin.Client.Need(resource) end

--- Raises this resource's toast through opx77_notify, in one replaced slot; a chat line when it
--- cannot. Text already rendered.
---@param kind string info | success | warning | error
---@param message string
function OpxAdmin.Client.Notice(kind, message) end

--- `OpxAdmin.Client.Notice` from a catalogue key.
---@param key string
---@param params table|nil
---@param kind string|nil
function OpxAdmin.Client.Toast(key, params, kind) end

--- Sends one command line through `open77:command:execute`, exactly as the chat box would, and
--- remembers when, so its answer can be written under the list.
---@param tokens string[]
---@return boolean sent
function OpxAdmin.Client.Execute(tokens) end
