local RelationNavigator = {}

local function relation_key(relation)
    local guild = type(relation) == "table" and relation.guild or nil
    if type(guild) ~= "table" then return "" end
    return tostring(guild.key or "")
end

function RelationNavigator.select(controller, step)
    if type(controller) ~= "table"
        or type(controller.model) ~= "function"
        or type(controller.select_guild) ~= "function" then
        return false, nil, "UI sunum controller'i hazir degil."
    end

    local model = controller:model()
    local active_tab = type(model) == "table"
        and tostring(model.active_tab or "") or ""
    if active_tab ~= "DIPLOMACY" and active_tab ~= "ALLIANCE" then
        return false, model, "Aktif sekmede iliski listesi yok."
    end

    local views = type(model.views) == "table" and model.views or nil
    local view = type(views) == "table" and views[active_tab] or nil
    local relations = type(view) == "table" and view.relations or nil
    if type(relations) ~= "table" or #relations == 0 then
        return false, model, "Secilebilir iliski kaydi bulunamadi."
    end

    local direction = tonumber(step) or 0
    if direction == 0 then
        return false, model, "Iliski gezinme yonu gecersiz."
    end
    direction = direction < 0 and -1 or 1

    local selected_guild = tostring(model.selected_guild or "")
    local target_index = direction < 0 and #relations or 1
    for index, relation in ipairs(relations) do
        if relation_key(relation) == selected_guild then
            target_index = (index - 1 + direction) % #relations + 1
            break
        end
    end

    local guild_key = relation_key(relations[target_index])
    if guild_key == "" then
        return false, model, "Iliski klan kimligi bulunamadi."
    end

    local accepted, selected_model, rendered, selection_error =
        controller:select_guild(guild_key)
    if accepted ~= true or rendered ~= true then
        return false, selected_model,
            selection_error or "Iliski kaydi secilemedi."
    end
    return true, selected_model
end

return RelationNavigator
