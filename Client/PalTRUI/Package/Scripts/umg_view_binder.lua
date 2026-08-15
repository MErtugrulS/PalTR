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

function UMGViewBinder:_set_text_if_present(controls, name, value)
    if controls[name] == nil then return true end
    -- Optional designer controls may be retained as named wrapper widgets in
    -- generated assets. A failed optional write must not abort panel opening.
    self:_set_text(controls, name, value)
    return true
end

function UMGViewBinder:_try_set_text(controls, name, value)
    if controls[name] ~= nil then
        self:_set_text(controls, name, value)
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

function UMGViewBinder:_set_enabled_if_present(controls, name, enabled)
    if controls[name] == nil then return true end
    self:_set_enabled(controls, name, enabled)
    return true
end

function UMGViewBinder:_set_visible_if_present(controls, name, visible)
    local control = controls[name]
    if control == nil then return true end

    -- ESlateVisibility: Collapsed=1, HitTestInvisible=3. Relation rows are
    -- presentation-only; keeping them out of hit testing also lets the parent
    -- VerticalBox reflow to exactly the number of live server relations.
    pcall(function()
        control:SetVisibility(visible == true and 3 or 1)
    end)
    return true
end

function UMGViewBinder:_set_interactive_visible_if_present(
    controls,
    name,
    visible
)
    local control = controls[name]
    if control == nil then return true end

    -- ESlateVisibility: Visible=0, Collapsed=1. Unlike decorative rows,
    -- diplomacy relation buttons must remain in the hit-test path.
    pcall(function()
        control:SetVisibility(visible == true and 0 or 1)
        control:SetIsEnabled(visible == true)
    end)
    return true
end

function UMGViewBinder:_bind_design_template(controls, model)
    local views = table_or_empty(model.views)
    local clan = table_or_empty(views.CLAN)
    local dashboard = table_or_empty(clan.dashboard)
    local header = table_or_empty(model.header)
    local connection = table_or_empty(model.connection)
    local protection = table_or_empty(dashboard.protection)
    local territories = table_or_empty(dashboard.territories)
    local diplomacy = table_or_empty(views.DIPLOMACY)
    local management = table_or_empty(views.MANAGEMENT)

    if controls.TemplatePageSwitcher ~= nil then
        pcall(function()
            local page_index = 0
            if model.active_tab == "DIPLOMACY" then page_index = 1 end
            if model.active_tab == "MANAGEMENT" then page_index = 2 end
            controls.TemplatePageSwitcher:SetActiveWidgetIndex(page_index)
        end)
    end
    local home_active = model.active_tab ~= "DIPLOMACY"
        and model.active_tab ~= "MANAGEMENT"
    local diplomacy_active = model.active_tab == "DIPLOMACY"
    local management_active = model.active_tab == "MANAGEMENT"
    if controls.C_Home ~= nil then
        pcall(function() controls.C_Home:SetIsChecked(home_active) end)
    end
    if controls.C_Diplomacy ~= nil then
        pcall(function() controls.C_Diplomacy:SetIsChecked(diplomacy_active) end)
    end
    -- Compatibility with the short-lived native-button asset: only one
    -- passive active overlay may be visible at a time.
    self:_set_visible_if_present(controls, "C_HomeActive", home_active)
    self:_set_visible_if_present(
        controls,
        "C_DiplomacyActive",
        diplomacy_active
    )
    self:_set_visible_if_present(
        controls,
        "PalTRSidebarDiplomacyArrow",
        diplomacy_active
    )
    for _, arrow_name in ipairs({
        "PalTRSidebarWarArrow",
        "PalTRSidebarBuildingsArrow",
        "PalTRSidebarRegionsArrow",
        "PalTRSidebarPlayersArrow",
        "PalTRSidebarRecordsArrow",
        "PalTRSidebarSettingsArrow"
    }) do
        self:_set_visible_if_present(controls, arrow_name, false)
    end
    self:_set_visible_if_present(
        controls,
        "PalTRSidebarManagementArrow",
        management_active
    )

    local role_header = text(header.role_text):gsub("^Rol:", "Yetki:")
    local role_value = role_header:gsub("^Yetki:%s*", "")
    -- These labels belong to the authored layout. They are intentionally kept
    -- local: only values that can change at runtime are read from the server.
    local static_text_bindings = {
        { "TemplateHomeText", "Ana Sayfa" },
        { "TemplateHomeText_1", "Diplomasi" },
        { "SavasText", "Savaş / Koruma" },
        { "YapilarText", "Yapılar" },
        { "BolgelerText", "Bölgeler" },
        { "BolgelerText_2", "Kayıtlar" },
        { "PlayersText", "Oyuncular" },
        { "YonetimText", "Yönetim" },
        { "AyarlarText", "Ayarlar" },
        { "TextBlock_362", "PALTR " },
        { "PANEL", "PANEL" },
        { "ClanNameText1", "Klan: " },
        { "ClanRoleText", "Yetki: " },
        { "ClanRoleText_1", "Bildirimler" },
        { "TemplatePageHeading", "Klan Durumu" },
        {
            "TemplatePageSubtitle",
            "Klanınızın genel durumunu ve önemli bilgileri buradan takip edin."
        },
        { "TemplateCardTitle1", "Klanım" },
        { "TemplateClanLeaderLabelText", "Lider:" },
        { "TemplateDiplomacyTitleText", "Diplomasi" },
        { "TemplateDiplomacyWarLabel", "Savaş:" },
        { "TemplateDiplomacyAllianceLabel", "İttifak:" },
        { "TemplateDiplomacyPendingLabel", "Bekleyen:" },
        { "TemplateProtectionTitleText", "Koruma" },
        { "TemplateProtectionOfflineLabel", "Offline Koruma:" },
        { "TemplateProtectionRaidLabel", "Baskın Penceresi:" },
        { "TemplateBuildingsTitleText", "Yapılar" },
        { "TemplateBuildingsProtectedBaseLabel", "Korunan Üs:" },
        { "TemplateBuildingsRiskyRegionLabel", "Riskli Bölge:" },
        { "TemplateRecentEventsHeadingText", "Son Olaylar" },
        { "TemplateRecentEventsViewAllText", "Tümünü Gör" },
        { "TemplateQuickActionsHeadingText", "Hızlı İşlemler" },
        { "TemplateRelationsHeading", "İlişkiler" },
        { "TemplateOffersHeading", "Bekleyen Teklifler" },
        {
            "TemplateDiplomacyListHeading",
            "Klan İlişkileri ve Teklifler"
        },
        { "TemplateProtectionStatusText", "Koruma Durumu" }
    }
    for _, binding in ipairs(static_text_bindings) do
        self:_set_text_if_present(controls, binding[1], binding[2])
    end

    local template_bindings = {
        { "TemplateServerBadgeText", connection.status_text },
        { "TemplateGuildBadgeText", header.guild_text },
        { "TemplateRoleBadgeText", role_header },
        { "TemplateNotificationBadgeText", header.notification_text },
        -- The manually-authored template kept these designer names instead
        -- of the generated Template* aliases. Only the final visible copies
        -- are targeted, so the decorative/label text remains untouched.
        { "ActivePlayerText", connection.status_text },
        { "ActivePlayerText_1", "" },
        { "ClanNameText", table_or_empty(clan.guild).name },
        { "ClanRoleText2", role_value },
        { "TextBlock_172", dashboard.pending_count_text },
        { "TemplateCardValue1", table_or_empty(clan.guild).name },
        { "TemplateClanLeaderValueText", clan.leader_name },
        {
            "TemplateClanMemberText",
            (tonumber(model.schema_version) or 0) > 0
                and string.format("Üye: %d", tonumber(clan.member_count) or 0)
                or "Üye: -"
        },
        { "TemplateDiplomacyWarValue", dashboard.war_count_text },
        {
            "TemplateDiplomacyAllianceValue",
            dashboard.alliance_count_text
        },
        { "TemplateDiplomacyPendingValue", dashboard.pending_count_text },
        { "TemplateProtectionOfflineValue", protection.offline_text },
        { "TemplateProtectionRaidValue", protection.raid_text },
        {
            "TemplateBuildingsProtectedBaseValue",
            territories.protected_base_count_text
        },
        {
            "TemplateBuildingsRiskyRegionValue",
            territories.risky_region_count_text
        },
        { "TemplateOfferGuild", dashboard.pending_guild_text },
        { "TemplateOfferType", dashboard.pending_state_text },
        {
            "TemplatePendingOffersEmptyText",
            clan.pending_empty and "Başka bekleyen teklif yok."
                or "Diğer teklifler Diplomasi sayfasında."
        }
    }
    for _, binding in ipairs(template_bindings) do
        self:_set_text_if_present(controls, binding[1], binding[2])
    end

    for _, binding in ipairs({
        { "TemplateDiplomacySelectedGuildText", diplomacy.title_text },
        { "TemplateDiplomacySelectedStateText", diplomacy.state_text },
        { "TemplateDiplomacyDescriptionText", diplomacy.description_text }
    }) do
        self:_set_text_if_present(controls, binding[1], binding[2])
    end

    local diplomacy_relations = table_or_empty(diplomacy.relations)
    for index = 1, 6 do
        local relation = table_or_empty(diplomacy_relations[index])
        local guild = table_or_empty(relation.guild)
        local status = table_or_empty(relation.status)
        local has_relation = text(guild.name) ~= ""
        self:_set_interactive_visible_if_present(
            controls,
            string.format("TemplateDiplomacyRelationButton_%02d", index),
            has_relation
        )
        self:_set_text_if_present(
            controls,
            string.format("TemplateDiplomacyRelationNameText_%02d", index),
            has_relation and ((relation.selected == true and "› " or "")
                .. text(guild.name)) or ""
        )
        self:_set_text_if_present(
            controls,
            string.format("TemplateDiplomacyRelationStateText_%02d", index),
            has_relation and (text(status.list_label) ~= ""
                and text(status.list_label) or text(status.label)) or ""
        )
    end

    local diplomacy_control_aliases = {
        PreviousRelationButton = {
            button = "TemplateDiplomacyPreviousButton",
            label = "TemplateDiplomacyPreviousText"
        },
        NextRelationButton = {
            button = "TemplateDiplomacyNextButton",
            label = "TemplateDiplomacyNextText"
        },
        AllianceRequestButton = {
            button = "TemplateDiplomacyAllianceButton",
            label = "TemplateDiplomacyAllianceText"
        },
        WarRequestButton = {
            button = "TemplateDiplomacyWarButton",
            label = "TemplateDiplomacyWarText"
        },
        AcceptButton = {
            button = "TemplateDiplomacyAcceptButton",
            label = "TemplateDiplomacyAcceptText"
        },
        RejectButton = {
            button = "TemplateDiplomacyRejectButton",
            label = "TemplateDiplomacyRejectText"
        },
        CancelButton = {
            button = "TemplateDiplomacyCancelButton",
            label = "TemplateDiplomacyCancelText"
        }
    }
    local diplomacy_controls = {}
    for name, item in pairs(table_or_empty(diplomacy.navigation_controls)) do
        diplomacy_controls[name] = item
    end
    for name, item in pairs(table_or_empty(diplomacy.action_controls)) do
        diplomacy_controls[name] = item
    end
    for canonical_name, alias in pairs(diplomacy_control_aliases) do
        local item = table_or_empty(diplomacy_controls[canonical_name])
        if text(item.label) ~= "" then
            self:_set_text_if_present(controls, alias.label, item.label)
        end
        self:_set_enabled_if_present(controls, alias.button, item.enabled)
    end

    local relation_rows = table_or_empty(dashboard.relation_rows)
    for index = 1, 3 do
        local relation_row = relation_rows[index]
        relation_row = table_or_empty(relation_row)
        local guild_name = text(relation_row.guild_name)
        local has_relation = guild_name ~= "" and guild_name ~= "-"
        self:_set_visible_if_present(
            controls,
            string.format("TemplateRelationRow_%02d", index),
            has_relation
        )
        self:_set_text_if_present(
            controls,
            string.format("TemplateRelation%d", index),
            has_relation and guild_name or ""
        )
        self:_set_text_if_present(
            controls,
            string.format("TemplateRelationStateText_%02d", index),
            has_relation and relation_row.state_label or ""
        )
    end

    local action_aliases = {
        DashboardDiplomacyButton = {
            button = "TemplateOpenDiplomacy",
            label = "TemplateOpenDiplomacyText"
        },
        DashboardOffersButton = {
            button = "TemplateViewOffers",
            label = "TemplateViewOffersText"
        },
        DashboardGuildsButton = {
            button = "TemplateListGuilds",
            label = "TemplateListGuildsText"
        },
        DashboardPendingAcceptButton = {
            button = "TemplateAcceptButton",
            label = "TemplateAcceptText"
        },
        DashboardPendingRejectButton = {
            button = "TemplateRejectButton",
            label = "TemplateRejectText"
        }
    }
    for canonical_name, alias in pairs(action_aliases) do
        local action = table_or_empty(table_or_empty(clan.quick_actions)[canonical_name])
        if text(action.label) ~= "" then
            self:_set_text_if_present(controls, alias.label, action.label)
        end
        self:_set_enabled_if_present(controls, alias.button, action.enabled)
    end

    local recent_events = table_or_empty(dashboard.recent_events)
    for index = 1, 5 do
        local event = table_or_empty(recent_events[index])
        local has_event = text(event.message) ~= ""
        self:_set_visible_if_present(
            controls,
            string.format("TemplateRecentEventRow_%02d", index),
            has_event
        )
        self:_set_text_if_present(
            controls,
            string.format("TemplateRecentEventMessageText_%02d", index),
            event.message
        )
        self:_set_text_if_present(
            controls,
            string.format("TemplateRecentEventTimeText_%02d", index),
            event.time_text
        )
    end

    for index = 1, 16 do
        local item = table_or_empty(management.colors[index])
        local exists = text(item.id) ~= ""
        self:_set_interactive_visible_if_present(
            controls,
            string.format("GuildIdentityColorButton%02d", index),
            exists
        )
        self:_set_text_if_present(
            controls,
            string.format("GuildIdentityColorText%02d", index),
            exists and ((item.selected == true and "✓ " or "")
                .. text(item.id)) or ""
        )
        self:_set_enabled_if_present(
            controls,
            string.format("GuildIdentityColorButton%02d", index),
            exists and management.read_only ~= true
                and item.available == true
        )
    end
    for index = 1, 12 do
        local item = table_or_empty(management.emblems[index])
        local exists = text(item.id) ~= ""
        self:_set_interactive_visible_if_present(
            controls,
            string.format("GuildIdentityEmblemButton%02d", index),
            exists
        )
        self:_set_text_if_present(
            controls,
            string.format("GuildIdentityEmblemText%02d", index),
            exists and ((item.selected == true and "✓ " or "")
                .. text(item.name)) or ""
        )
        self:_set_enabled_if_present(
            controls,
            string.format("GuildIdentityEmblemButton%02d", index),
            exists and management.read_only ~= true
        )
    end
    local save_control = table_or_empty(management.save_control)
    self:_set_text_if_present(
        controls,
        "GuildIdentityStatusText",
        management.status_text
    )
    self:_set_text_if_present(
        controls,
        "GuildIdentitySaveText",
        save_control.label
    )
    self:_set_enabled_if_present(
        controls,
        "GuildIdentitySaveButton",
        save_control.enabled == true
    )

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

    -- Preserve the authored hierarchy. Exact lookup through WidgetTree reaches
    -- named controls below Border/SizeBox/Button content nodes without moving,
    -- recreating, or requiring them to be Blueprint variables.
    local controls = setmetatable({}, {
        __index = function(_, control_name)
            local found, control = pcall(function()
                return tree:FindWidget(control_name)
            end)
            control = found and unwrap(control) or nil
            if control ~= nil then return control end
            return read_property(panel, control_name)
        end
    })
    collect_widgets(root, controls, 0)

    if controls.TemplatePanelBackground ~= nil
        or controls.TemplateShell ~= nil then
        return self:_bind_design_template(controls, model)
    end

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
        { "PendingOffersText", clan.pending_text }
    }

    for _, binding in ipairs(bindings) do
        local updated, update_error = self:_set_text(
            controls,
            binding[1],
            binding[2]
        )
        if not updated then return false, update_error end
    end


    -- The redesigned home widget retains legacy tab variables for contract
    -- compatibility. They can resolve to wrapper widgets until their page is
    -- opened, so a failed legacy text write must not abort the F6 open path.
    for _, binding in ipairs({
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
    }) do
        self:_try_set_text(controls, binding[1], binding[2])
    end

    -- These fields belong to optional dashboard presentation components.
    -- Keeping them optional lets the stable data contract bind to a manually
    -- authored widget while the designer adds or removes decorative cards.
    for _, binding in ipairs({
        { "DashboardPendingGuildText", dashboard.pending_guild_text },
        { "DashboardPendingStateText", dashboard.pending_state_text },
        { "DashboardClanRoleValueText", dashboard.clan_role_text },
        { "DashboardClanMembersValueText", dashboard.clan_member_count_text },
        { "DashboardDiplomacyWarValueText", dashboard.war_count_text },
        {
            "DashboardDiplomacyAllianceValueText",
            dashboard.alliance_count_text
        },
        {
            "DashboardDiplomacyPendingValueText",
            dashboard.pending_count_text
        }
    }) do
        local updated, update_error = self:_set_text_if_present(
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
            local updated, update_error = self:_set_text_if_present(
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

    local relations_updated, relations_error = self:_set_text_if_present(
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
            local updated, update_error = self:_set_text_if_present(
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
