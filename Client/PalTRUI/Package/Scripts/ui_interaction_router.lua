local UIInteractionRouter = {}
UIInteractionRouter.__index = UIInteractionRouter

local function valid_controller(controller)
    return type(controller) == "table"
        and type(controller.toggle) == "function"
        and type(controller.set_tab) == "function"
end

local function current_model(controller)
    if type(controller.model) ~= "function" then return nil end
    return controller:model()
end

local function tab_id_for_control(model, control_name)
    local tabs = type(model) == "table" and model.tabs or nil
    if type(tabs) ~= "table" then return nil end

    for _, tab in ipairs(tabs) do
        if type(tab) == "table"
            and tostring(tab.control or "") == control_name then
            return tostring(tab.id or "")
        end
    end
    return nil
end

local function action_control(controller, control_name)
    local model = current_model(controller)
    local views = type(model) == "table" and model.views or nil
    local diplomacy = type(views) == "table" and views.DIPLOMACY or nil
    local controls = type(diplomacy) == "table"
        and diplomacy.action_controls or nil
    if type(controls) ~= "table" then return model, nil end
    return model, controls[control_name]
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

    local model = current_model(self.controller)
    local tab_id = tab_id_for_control(model, name)
    if tab_id == nil then
        local action_model, action = action_control(self.controller, name)
        if type(action) ~= "table" then
            return false, nil, false,
                "UI kontrol etkilesimi tanimli degil."
        end
        if action.enabled ~= true then
            return false, action_model, false,
                tostring(action.reason or "Diplomasi aksiyonu kullanilamaz.")
        end
        if type(self.controller.request_action) ~= "function" then
            return false, action_model, false,
                "UI aksiyon controller'i hazir degil."
        end

        local dispatched, dispatch_result =
            self.controller:request_action(action.action_id)
        if dispatched ~= true then
            return false, action_model, false, dispatch_result
        end
        return true, action_model, true
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
