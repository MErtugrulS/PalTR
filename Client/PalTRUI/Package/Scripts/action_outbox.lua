local ActionOutbox = {}
ActionOutbox.__index = ActionOutbox

local function valid_sender(sender)
    return type(sender) == "table" and type(sender.send) == "function"
end

local function validate_intent(intent)
    if type(intent) ~= "table" then return false, "intent" end
    if intent.kind ~= "DIPLOMACY_ACTION" then return false, "kind" end
    if type(intent.guild_key) ~= "string" or intent.guild_key == "" then
        return false, "guild_key"
    end
    if type(intent.action_id) ~= "string" or intent.action_id == "" then
        return false, "action_id"
    end
    if type(intent.snapshot_generated_at) ~= "number" then
        return false, "snapshot_generated_at"
    end
    return true
end

function ActionOutbox.new(sender)
    return setmetatable({
        sender = valid_sender(sender) and sender or nil,
        sequence = 0
    }, ActionOutbox)
end

function ActionOutbox:dispatch(intent)
    local valid, field = validate_intent(intent)
    if not valid then
        return false, "UI aksiyon intenti gecersiz: " .. tostring(field)
    end
    if self.sender == nil then
        return false, "Client-server UI transportu hazir degil."
    end

    self.sequence = self.sequence + 1
    local envelope = {
        version = 1,
        request_id = string.format("ui-action-%d", self.sequence),
        kind = intent.kind,
        guild_key = intent.guild_key,
        action_id = intent.action_id,
        snapshot_generated_at = intent.snapshot_generated_at
    }
    local sent, result = self.sender:send(envelope)
    if sent ~= true then
        return false, result or "UI aksiyon istegi gonderilemedi."
    end
    return true, result or envelope
end

return ActionOutbox
