local UMGViewBinder = {}
UMGViewBinder.__index = UMGViewBinder

local tab_indexes = {
    CLAN = 0,
    DIPLOMACY = 1,
    ALLIANCE = 2,
    CHAT = 3
}

local function table_or_empty(value)
    return type(value) == "table" and value or {}
end

local function text(value)
    return value == nil and "" or tostring(value)
end

local function unwrap(value)
    if value == nil then return nil end
    local ok, result = pcall(function() return value:get() end)
    if ok and result ~= nil then return result end
    return value
end

local function read_property(object, property_name)
    object = unwrap(object)
    if object == nil then return nil end

    local direct_ok, direct_value = pcall(function()
        return object[property_name]
    end)
    if direct_ok and direct_value ~= nil then return unwrap(direct_value) end

    local getter_ok, getter_value = pcall(function()
        return object:GetPropertyValue(property_name)
    end)
    if getter_ok then return unwrap(getter_value) end
    return nil
end

local function widget_name(widget)
    local named, name = pcall(function()
        return widget:GetFName():ToString()
    end)
    return named and text(name) or ""
end

local function collect_widgets(widget, controls, depth)
    widget = unwrap(widget)
    if widget == nil or depth > 64 then return end

    local name = widget_name(widget)
    if name ~= "" then controls[name] = widget end

    local counted, count = pcall(function()
        return widget:GetChildrenCount()
    end)
    if not counted or type(count) ~= "number" then return end

    for index = 0, count - 1 do
        local found, child = pcall(function()
            return widget:GetChildAt(index)
        end)
        if found then collect_widgets(child, controls, depth + 1) end
    end
end

local function join_members(members)
    local lines = {}
    for _, member in ipairs(table_or_empty(members)) do
        member = table_or_empty(member)
        local suffix = member.online == true and " (cevrimici)" or ""
        table.insert(lines, text(member.name) .. suffix)
    end
    return table.concat(lines, "\n")
end

local function join_relations(relations)
    local lines = {}
    for _, relation in ipairs(table_or_empty(relations)) do
        relation = table_or_empty(relation)
        local guild = table_or_empty(relation.guild)
        local status = table_or_empty(relation.status)
        table.insert(lines, string.format(
            "%s | %s",
            text(guild.name),
            text(status.label)
        ))
    end
    return table.concat(lines, "\n")
end

local function relation_description(relation)
    relation = table_or_empty(relation)
    local status = table_or_empty(relation.status)
    local permissions = table_or_empty(relation.permissions)
    local parts = {}
    for _, value in ipairs({
        status.proposal_direction_label,
        status.note,
        permissions.reason
    }) do
        value = text(value)
        if value ~= "" then table.insert(parts, value) end
    end
    return #parts > 0 and table.concat(parts, " | ")
        or "Iliski ayrintisi yok."
end

local function join_messages(messages)
    local lines = {}
    for _, message in ipairs(table_or_empty(messages)) do
        message = table_or_empty(message)
        table.insert(lines, string.format(
            "%s: %s",
            text(message.sender),
            text(message.text)
        ))
    end
    return table.concat(lines, "\n")
end

local function valid_object(object)
    if object == nil then return false end
    local checked, valid = pcall(function()
        return object:IsValid()
    end)
    if checked then return valid == true end
    return true
end

local function default_get_text_library()
    local loaded, UEHelpers = pcall(require, "UEHelpers")
    if not loaded then return nil end
    local found, library = pcall(UEHelpers.GetKismetTextLibrary)
    if not found or not valid_object(library) then return nil end
    return library
end

local function default_make_text(value, get_text_library)
    if type(FText) == "function" then
        local created, unreal_text = pcall(FText, value)
        if created then return unreal_text end
    end

    local library = get_text_library()
    if not valid_object(library) then return nil end
    local converted, unreal_text = pcall(function()
        return library:Conv_StringToText(value)
    end)
    if not converted then return nil end
    return unreal_text
end

function UMGViewBinder.new(dependencies)
    dependencies = type(dependencies) == "table" and dependencies or {}
    local get_text_library = dependencies.get_text_library
        or default_get_text_library
    local make_text = dependencies.make_text
    if type(make_text) ~= "function" then
        make_text = function(value)
            return default_make_text(value, get_text_library)
        end
    end
    return setmetatable({
        make_text = make_text
    }, UMGViewBinder)
end

function UMGViewBinder:_set_text(controls, name, value)
    local control = controls[name]
    if control == nil then
        return false, "UMG kontrolu bulunamadi: " .. name
    end

    local unreal_text = self.make_text(text(value))
    if unreal_text == nil then
        return false, "UE4SS FText API bulunamadi."
    end

    local updated = pcall(function()
        control:SetText(unreal_text)
    end)
    if not updated then
        return false, "UMG metni guncellenemedi: " .. name
    end
    return true
end

function UMGViewBinder:_set_enabled(controls, name, enabled)
    local control = controls[name]
    if control == nil then
        return false, "UMG kontrolu bulunamadi: " .. name
    end

    local updated = pcall(function()
        control:SetIsEnabled(enabled == true)
    end)
    if not updated then
        return false, "UMG kontrol durumu guncellenemedi: " .. name
    end
    return true
end

function UMGViewBinder:bind(panel, model)
    if type(model) ~= "table" then
        return false, "Gorunum modeli bulunamadi."
    end

    local tree = read_property(panel, "WidgetTree")
    local root = read_property(tree, "RootWidget")
    if root == nil then
        return false, "PalTR widget agaci bulunamadi."
    end

    local controls = {}
    collect_widgets(root, controls, 0)

    local switcher = controls.ContentSwitcher
    local active_index = tab_indexes[text(model.active_tab)]
    if switcher == nil or active_index == nil then
        return false, "PalTR aktif sekmesi guncellenemedi."
    end
    local switched = pcall(function()
        switcher:SetActiveWidgetIndex(active_index)
    end)
    if not switched then
        return false, "PalTR aktif sekmesi guncellenemedi."
    end

    local views = table_or_empty(model.views)
    local clan = table_or_empty(views.CLAN)
    local diplomacy = table_or_empty(views.DIPLOMACY)
    local alliance = table_or_empty(views.ALLIANCE)
    local chat = table_or_empty(views.CHAT)
    local selected = table_or_empty(diplomacy.selected_relation)
    local selected_guild = table_or_empty(selected.guild)
    local selected_status = table_or_empty(selected.status)
    local clan_guild = table_or_empty(clan.guild)

    local connection = table_or_empty(model.connection)

    local bindings = {
        { "TitleText", "PalTR" },
        { "ConnectionStatusText", connection.status_text },
        { "ClanNameText", text(clan_guild.name) ~= ""
            and clan_guild.name or "Klan bilgisi bekleniyor" },
        { "ClanSummaryText", string.format(
            "%d uye | %d cevrimici",
            tonumber(clan.member_count) or 0,
            tonumber(clan.online_count) or 0
        ) },
        { "ClanMembersText", clan.empty == true
            and text(clan.empty_message) or join_members(clan.members) },
        { "RelationListEmptyText", diplomacy.empty == true
            and text(diplomacy.empty_message)
            or join_relations(diplomacy.relations) },
        { "RelationTitleText", text(selected_guild.name) ~= ""
            and selected_guild.name or "Klan secin" },
        { "RelationStateText", text(selected_status.label) ~= ""
            and selected_status.label or "Iliski durumu: -" },
        { "RelationDescriptionText", relation_description(selected) },
        { "AllianceSummaryText", string.format(
            "%d ittifak kaydi",
            #table_or_empty(alliance.relations)
        ) },
        { "AllianceMembersText", alliance.empty == true
            and text(alliance.empty_message)
            or join_relations(alliance.relations) },
        { "ChatEmptyText", chat.empty == true
            and text(chat.empty_message) or join_messages(chat.messages) }
    }

    for _, binding in ipairs(bindings) do
        local updated, update_error = self:_set_text(
            controls,
            binding[1],
            binding[2]
        )
        if not updated then return false, update_error end
    end

    for _, tab in ipairs(table_or_empty(model.tabs)) do
        tab = table_or_empty(tab)
        local label_updated, label_error = self:_set_text(
            controls,
            text(tab.text_control),
            tab.label
        )
        if not label_updated then return false, label_error end

        local state_updated, state_error = self:_set_enabled(
            controls,
            text(tab.control),
            tab.enabled
        )
        if not state_updated then return false, state_error end
    end

    for _, action_control in pairs(
        table_or_empty(diplomacy.action_controls)
    ) do
        action_control = table_or_empty(action_control)
        local label_updated, label_error = self:_set_text(
            controls,
            text(action_control.text_control),
            action_control.label
        )
        if not label_updated then return false, label_error end

        local state_updated, state_error = self:_set_enabled(
            controls,
            text(action_control.control),
            action_control.enabled
        )
        if not state_updated then return false, state_error end
    end
    return true
end

return UMGViewBinder
