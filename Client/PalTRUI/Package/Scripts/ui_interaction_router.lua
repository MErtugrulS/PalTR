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

local function navigation_control(controller, control_name)
    local model = current_model(controller)
    local views = type(model) == "table" and model.views or nil
    local active_tab = type(model) == "table"
        and tostring(model.active_tab or "") or ""
    local active_view = type(views) == "table" and views[active_tab] or nil
    local controls = type(active_view) == "table"
        and active_view.navigation_controls or nil
    if type(controls) ~= "table" then return model, nil end
    return model, controls[control_name]
end

local function dashboard_control(controller, control_name)
    local model = current_model(controller)
    local views = type(model) == "table" and model.views or nil
    local clan = type(views) == "table" and views.CLAN or nil
    local controls = type(clan) == "table" and clan.quick_actions or nil
    if type(controls) ~= "table" then return model, nil end
    return model, controls[control_name]
end

local function relation_row(controller, control_name)
    local index = tonumber(tostring(control_name or ""):match(
        "^DiplomacyRelationRowButton(%d%d)$"
    ))
    if index == nil then return nil, nil end
    local model = current_model(controller)
    local views = type(model) == "table" and model.views or nil
    local diplomacy = type(views) == "table" and views.DIPLOMACY or nil
    local relations = type(diplomacy) == "table"
        and diplomacy.relations or nil
    local relation = type(relations) == "table" and relations[index] or nil
    local guild = type(relation) == "table" and relation.guild or nil
    local guild_key = type(guild) == "table"
        and tostring(guild.key or "") or ""
    return model, guild_key ~= "" and guild_key or nil
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
    local row_model, guild_key = relation_row(self.controller, name)
    if guild_key ~= nil then
        if type(self.controller.select_guild) ~= "function" then
            return false, row_model, false,
                "UI klan secim controller'i hazir degil."
        end
        local accepted, selected_model, rendered, select_error =
            self.controller:select_guild(guild_key)
        if accepted ~= true or rendered ~= true then
            return false, selected_model, rendered, select_error
        end
        return true, selected_model, true
    end
    local tab_id = tab_id_for_control(model, name)
    if tab_id == nil then
        local dashboard_model, dashboard = dashboard_control(
            self.controller,
            name
        )
        if type(dashboard) == "table" then
            if dashboard.enabled ~= true then
                return false, dashboard_model, false,
                    tostring(dashboard.reason or "Hizli islem kullanilamaz.")
            end
            local target_guild = tostring(dashboard.target_guild or "")
            local action_id = tostring(dashboard.action_id or "")
            local accepted, target_model, rendered, render_error
            if target_guild ~= ""
                and type(self.controller.open_relation) == "function" then
                accepted, target_model, rendered, render_error =
                    self.controller:open_relation(
                        dashboard.target_tab,
                        target_guild
                    )
                if accepted ~= true or rendered ~= true then
                    return false, target_model, rendered, render_error
                end
                if action_id ~= "" then
                    if type(self.controller.request_action) ~= "function" then
                        return false, target_model, false,
                            "UI aksiyon controller'i hazir degil."
                    end
                    local dispatched, dispatch_result =
                        self.controller:request_action(action_id)
                    if dispatched ~= true then
                        return false, target_model, false, dispatch_result
                    end
                    return true, target_model, true
                end
            else
                accepted, target_model, rendered, render_error =
                    self.controller:set_tab(dashboard.target_tab)
            end
            if accepted ~= true or rendered ~= true then
                return false, target_model, rendered, render_error
            end
            return true, target_model, true
        end

        local navigation_model, navigation = navigation_control(
            self.controller,
            name
        )
        if type(navigation) == "table" then
            if navigation.enabled ~= true then
                return false, navigation_model, false,
                    tostring(navigation.reason or "Iliski gezinmesi kullanilamaz.")
            end
            if type(self.controller.navigate_relation) ~= "function" then
                return false, navigation_model, false,
                    "UI iliski navigator'i hazir degil."
            end
            local navigated, navigated_model, navigation_error =
                self.controller:navigate_relation(navigation.step)
            if navigated ~= true then
                return false, navigated_model, false, navigation_error
            end
            return true, navigated_model, true
        end

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
