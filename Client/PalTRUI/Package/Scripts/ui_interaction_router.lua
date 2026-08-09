local UIInteractionRouter = {}
UIInteractionRouter.__index = UIInteractionRouter

local tab_controls = {
    ClanTabButton = "CLAN",
    DiplomacyTabButton = "DIPLOMACY",
    AllianceTabButton = "ALLIANCE",
    ChatTabButton = "CHAT"
}

local function valid_controller(controller)
    return type(controller) == "table"
        and type(controller.toggle) == "function"
        and type(controller.set_tab) == "function"
end

function UIInteractionRouter.new(controller)
    return setmetatable({
        controller = valid_controller(controller) and controller or nil
    }, UIInteractionRouter)
end

function UIInteractionRouter:handle(control_name)
    if self.controller == nil then
        return false, nil, false, "UI sunum controller'i hazir degil."
    end

    local name = tostring(control_name or "")
    if name == "CloseButton" then
        local model, rendered, render_error = self.controller:toggle()
        if rendered ~= true then
            return false, model, rendered, render_error
        end
        return true, model, true
    end

    local tab_id = tab_controls[name]
    if tab_id == nil then
        return false, nil, false, "UI kontrol etkilesimi tanimli degil."
    end

    local accepted, model, rendered, render_error =
        self.controller:set_tab(tab_id)
    if accepted ~= true then
        local model_error = type(model) == "table" and model.error or nil
        return false, model, rendered,
            model_error or "UI sekmesi reddedildi."
    end
    if rendered ~= true then
        return false, model, rendered, render_error
    end
    return true, model, true
end

return UIInteractionRouter
