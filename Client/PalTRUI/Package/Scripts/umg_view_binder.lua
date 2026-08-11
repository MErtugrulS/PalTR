local UMGViewBinder = {}
UMGViewBinder.__index = UMGViewBinder

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
    local active_index = nil
    for _, tab in ipairs(table_or_empty(model.tabs)) do
        if type(tab) == "table" and tab.active == true then
            active_index = tonumber(tab.page_index)
            break
        end
    end
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
    local guilds = table_or_empty(views.GUILDS)
    local connection = table_or_empty(model.connection)
    local header = table_or_empty(model.header)
    local dashboard = table_or_empty(clan.dashboard)

    local bindings = {
        { "TitleText", "PALTR PANEL" },
        { "ConnectionStatusText", connection.status_text },
        { "HeaderGuildText", header.guild_text },
        { "HeaderRoleText", header.role_text },
        { "HeaderNotificationText", header.notification_text },
        { "ClanNameText", clan.name_text },
        { "ClanSummaryText", clan.summary_text },
        { "ClanMembersHeadingText", clan.members_heading_text },
        { "ClanMembersStatusText", clan.members_status_text },
        { "ClanMembersText", clan.members_text },
        { "PendingOffersText", clan.pending_text },
        { "DashboardPendingGuildText", dashboard.pending_guild_text },
        { "DashboardPendingStateText", dashboard.pending_state_text },
        { "DashboardClanRoleValueText", dashboard.clan_role_text },
        { "DashboardClanMembersValueText", dashboard.clan_member_count_text },
        { "DashboardDiplomacyWarValueText", dashboard.war_count_text },
        { "DashboardDiplomacyAllianceValueText", dashboard.alliance_count_text },
        { "DashboardDiplomacyPendingValueText", dashboard.pending_count_text },
        { "RelationListEmptyText", diplomacy.list_text },
        { "RelationTitleText", diplomacy.title_text },
        { "RelationStateText", diplomacy.state_text },
        { "RelationDescriptionText", diplomacy.description_text },
        { "AllianceSummaryText", alliance.summary_text },
        { "AllianceMembersText", alliance.members_text },
        { "AllianceTitleText", alliance.title_text },
        { "AllianceStateText", alliance.state_text },
        { "AllianceDescriptionText", alliance.description_text },
        { "ChatEmptyText", guilds.list_text },
        { "GuildCatalogSummaryText", guilds.summary_text },
        { "GuildCatalogActiveHeadingText", guilds.active_heading_text },
        { "GuildCatalogActiveText", guilds.active_text },
        { "GuildCatalogRegisteredHeadingText", guilds.registered_heading_text },
        { "GuildCatalogRegisteredText", guilds.registered_text }
    }

    for _, binding in ipairs(bindings) do
        local updated, update_error = self:_set_text(
            controls,
            binding[1],
            binding[2]
        )
        if not updated then return false, update_error end
    end

    for _, relation_row in ipairs(
        table_or_empty(dashboard.relation_rows)
    ) do
        relation_row = table_or_empty(relation_row)
        for _, field in ipairs({
            {
                control = relation_row.name_control,
                value = relation_row.guild_name
            },
            {
                control = relation_row.state_control,
                value = relation_row.state_label
            }
        }) do
            local updated, update_error = self:_set_text(
                controls,
                text(field.control),
                field.value
            )
            if not updated then return false, update_error end
        end
    end

    for _, tab in ipairs(table_or_empty(model.tabs)) do
        tab = table_or_empty(tab)
        local label_updated, label_error = self:_set_text(
            controls,
            text(tab.text_control),
            tab.display_label
        )
        if not label_updated then return false, label_error end

        local state_updated, state_error = self:_set_enabled(
            controls,
            text(tab.control),
            tab.enabled
        )
        if not state_updated then return false, state_error end
    end

    for _, quick_action in pairs(table_or_empty(clan.quick_actions)) do
        quick_action = table_or_empty(quick_action)
        local label_updated, label_error = self:_set_text(
            controls,
            text(quick_action.text_control),
            quick_action.label
        )
        if not label_updated then return false, label_error end

        local state_updated, state_error = self:_set_enabled(
            controls,
            text(quick_action.control),
            quick_action.enabled
        )
        if not state_updated then return false, state_error end
    end

    local relations_updated, relations_error = self:_set_text(
        controls,
        "DashboardRelationsText",
        dashboard.relations_text
    )
    if not relations_updated then return false, relations_error end

    for _, card in ipairs(table_or_empty(dashboard.cards)) do
        card = table_or_empty(card)
        for _, field in ipairs({
            { control = card.title_control, value = card.title },
            { control = card.value_control, value = card.value },
            { control = card.detail_control, value = card.detail }
        }) do
            local updated, update_error = self:_set_text(
                controls,
                text(field.control),
                field.value
            )
            if not updated then return false, update_error end
        end
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

    for _, navigation_control in pairs(
        table_or_empty(diplomacy.navigation_controls)
    ) do
        navigation_control = table_or_empty(navigation_control)
        local label_updated, label_error = self:_set_text(
            controls,
            text(navigation_control.text_control),
            navigation_control.label
        )
        if not label_updated then return false, label_error end

        local state_updated, state_error = self:_set_enabled(
            controls,
            text(navigation_control.control),
            navigation_control.enabled
        )
        if not state_updated then return false, state_error end
    end
    for _, navigation_control in pairs(
        table_or_empty(alliance.navigation_controls)
    ) do
        navigation_control = table_or_empty(navigation_control)
        local label_updated, label_error = self:_set_text(
            controls,
            text(navigation_control.text_control),
            navigation_control.label
        )
        if not label_updated then return false, label_error end

        local state_updated, state_error = self:_set_enabled(
            controls,
            text(navigation_control.control),
            navigation_control.enabled
        )
        if not state_updated then return false, state_error end
    end
    return true
end

return UMGViewBinder
