---@meta

--- The staff rows on opx77_target's eye, registered from the access map the server sends.
OpxAdmin.Target = {}

--- Takes an access map from the opener or an access refresh, and registers on the eye exactly the
--- rows it grants; an empty map takes them all down.
---@param payload table access and aclKnown
function OpxAdmin.Target.Access(payload) end
