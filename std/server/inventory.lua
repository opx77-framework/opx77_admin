---@meta

--- The bridge to opx77_inventory: every call to its server exports goes through here.
OpxAdmin.Inventory = {}

--- The inventory resource whose exports are called (`INVENTORY.RESOURCE`, validated).
---@type string
OpxAdmin.Inventory.RESOURCE = 'opx77_inventory'

--- The largest count a give or a removal accepts (`INVENTORY.MAX_COUNT`, at least 1).
---@type integer
OpxAdmin.Inventory.MAX_COUNT = 10000

--- Whether the host reports the inventory resource as running.
---@return boolean
function OpxAdmin.Inventory.Running() end

--- Calls one inventory server export and awaits it. Coroutine only: never under a pcall.
--- Answers the result, or nil with this resource's refusal code and the raw reason.
---@param name string the export name
---@param ... any the export's arguments
---@return table|nil result
---@return string|nil code `inventory_unavailable`, `refused` or a code mapped from the inventory's
---@return string|nil reason the raw reason, for the audit
function OpxAdmin.Inventory.Call(name, ...) end

--- Resolves what was typed for a bag: `me`, a connected player id, or a citizen id.
---@param source integer the caller, 0 for the console
---@param token any
---@return integer|string|nil target what the inventory exports take
---@return string|nil who a label for answers and the audit
---@return integer|nil playerId the connected player, if any
---@return string|nil code no_target, console_has_no_player, bad_holder or not_connected
function OpxAdmin.Inventory.Target(source, token) end

--- A typed count: nil when omitted, false when it is not a whole number in `least`..MAX_COUNT.
---@param token any
---@param least integer 0 where 0 means none, 1 elsewhere
---@return integer|false|nil
function OpxAdmin.Inventory.Count(token, least) end

--- The holder, resolved as `OpxAdmin.Inventory.Target` does, with the refusal answered, and
--- `inventory_unavailable` answered while the inventory is not running.
---@param source integer
---@param raw string
---@param token any
---@return integer|string|nil target
---@return string|nil who
---@return integer|nil playerId
function OpxAdmin.Inventory.Resolve(source, raw, token) end

--- The suggestion parameter of a holder: a player id, `me` or a citizen id.
---@type AdminParameter
OpxAdmin.Inventory.HOLDER = {}

--- The inventory's catalogue through GetItems, page by page, cached until it starts or stops
--- again or five minutes pass. Coroutine only.
---@return InventoryCatalog|nil catalog
---@return string|nil code
---@return string|nil reason
function OpxAdmin.Inventory.Catalog() end

--- A catalogue item by its exact name, without case.
---@param catalog InventoryCatalog
---@param token any
---@return InventoryItem|nil
function OpxAdmin.Inventory.Item(catalog, token) end

--- A weapon item by its name, or by the name without its `weapon_` prefix.
---@param catalog InventoryCatalog
---@param token any
---@return InventoryItem|nil
function OpxAdmin.Inventory.Weapon(catalog, token) end

--- A label for a stored item the catalogue may no longer carry: its name as a fallback.
---@param catalog InventoryCatalog|nil
---@param name string
---@return string
function OpxAdmin.Inventory.LabelOf(catalog, name) end

--- Every stack of a bag, page by page, in slot order. Coroutine only.
---@param target integer|string
---@return InventoryBag|nil bag
---@return string|nil code
---@return string|nil reason
function OpxAdmin.Inventory.Bag(target) end

--- A refusal, audited and answered. `params` may carry the words the refusal is answered with.
---@param source integer
---@param raw string
---@param event string
---@param playerId integer|nil
---@param who string|nil
---@param code string
---@param reason string|nil
---@param params table|nil
function OpxAdmin.Inventory.Fail(source, raw, event, playerId, who, code, reason, params) end

--- CanCarry. Coroutine only. True when the bag takes those items; otherwise false, this
--- resource's refusal code and the raw reason.
---@param target integer|string
---@param name string
---@param count integer
---@param metadata table|nil
---@return boolean carried
---@return string|nil code
---@return string|nil reason
function OpxAdmin.Inventory.Carry(target, name, count, metadata) end

--- CanCarry, then AddItem, answering nothing. Coroutine only.
---@param target integer|string
---@param name string
---@param count integer
---@param metadata table|nil
---@return boolean added
---@return string|nil code
---@return string|nil reason
function OpxAdmin.Inventory.Add(target, name, count, metadata) end

--- CanCarry, then AddItem. Coroutine only. True once the items are in the bag; otherwise the
--- refusal has been answered and audited.
---@param source integer
---@param raw string
---@param event string
---@param target integer|string
---@param who string
---@param playerId integer|nil
---@param name string
---@param count integer
---@param metadata table|nil
---@param label string
---@return boolean
function OpxAdmin.Inventory.Give(source, raw, event, target, who, playerId, name, count, metadata, label) end
