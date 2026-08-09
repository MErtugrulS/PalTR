local Contract = require("contract")

local SnapshotInbox = {}
SnapshotInbox.__index = SnapshotInbox

local function valid_controller(controller)
    return type(controller) == "table"
        and type(controller.model) == "function"
        and type(controller.apply_snapshot) == "function"
end

function SnapshotInbox.new(controller)
    return setmetatable({
        controller = valid_controller(controller) and controller or nil,
        last_generated_at = nil
    }, SnapshotInbox)
end

function SnapshotInbox:receive(snapshot)
    if self.controller == nil then
        return false, nil, false, "UI sunum controller'i hazir degil."
    end

    local valid, contract_error = Contract.validate(snapshot)
    if not valid then
        local _, model, rendered, render_error =
            self.controller:apply_snapshot(snapshot)
        return false, model, rendered,
            render_error or (model and model.error)
                or ("Snapshot reddedildi: " .. tostring(contract_error))
    end

    local generated_at = snapshot.generated_at
    if self.last_generated_at ~= nil
        and generated_at < self.last_generated_at then
        return false, self.controller:model(), false,
            "Eski sunucu snapshoti reddedildi."
    end

    local accepted, model, rendered, render_error =
        self.controller:apply_snapshot(snapshot)
    if accepted == true then
        self.last_generated_at = generated_at
    end
    return accepted, model, rendered, render_error
end

return SnapshotInbox
