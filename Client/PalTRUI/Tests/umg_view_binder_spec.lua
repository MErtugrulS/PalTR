local UMGViewBinder = require("umg_view_binder")

local function equal(actual, expected, label)
    if actual ~= expected then
        error(string.format(
            "%s | expected=%s actual=%s",
            label,
            tostring(expected),
            tostring(actual)
        ))
    end
end

local function widget(name, children)
    local item = {
        name = name,
        children = children or {},
        GetFName = function(self)
            return { ToString = function() return self.name end }
        end,
        GetChildrenCount = function(self)
            return #self.children
        end,
        GetChildAt = function(self, index)
            return self.children[index + 1]
        end
    }
    return item
end

local text_values = {}
local enabled_values = {}
local function text_widget(name)
    local item = widget(name)
    item.SetText = function(_, value)
        text_values[name] = value
    end
    return item
end

local function button_widget(name)
    local item = widget(name)
    item.SetIsEnabled = function(_, value)
        enabled_values[name] = value
    end
    return item
end

local switch_index = nil
local switcher = widget("ContentSwitcher")
switcher.SetActiveWidgetIndex = function(_, index)
    switch_index = index
end

local names = {
    "TitleText",
    "ConnectionStatusText",
    "ClanNameText",
    "ClanSummaryText",
    "ClanMembersText",
    "PendingOffersText",
    "DashboardDiplomacyButtonText",
    "DashboardOffersButtonText",
    "DashboardGuildsButtonText",
    "DashboardClanCardTitleText",
    "DashboardClanCardValueText",
    "DashboardClanCardDetailText",
    "DashboardDiplomacyCardTitleText",
    "DashboardDiplomacyCardValueText",
    "DashboardDiplomacyCardDetailText",
    "DashboardRelationsText",
    "RelationListEmptyText",
    "RelationTitleText",
    "RelationStateText",
    "RelationDescriptionText",
    "AllianceSummaryText",
    "AllianceMembersText",
    "AllianceTitleText",
    "AllianceStateText",
    "AllianceDescriptionText",
    "ChatEmptyText",
    "GuildCatalogSummaryText",
    "GuildCatalogActiveText",
    "GuildCatalogRegisteredText"
}
local controls = { switcher }
for _, name in ipairs(names) do
    table.insert(controls, text_widget(name))
end
for _, action in ipairs({
    {
        control = "DashboardDiplomacyButton",
        text_control = "DashboardDiplomacyButtonText"
    },
    {
        control = "DashboardOffersButton",
        text_control = "DashboardOffersButtonText"
    },
    {
        control = "DashboardGuildsButton",
        text_control = "DashboardGuildsButtonText"
    },
    {
        control = "WarRequestButton",
        text_control = "WarRequestButtonText"
    },
    {
        control = "AllianceRequestButton",
        text_control = "AllianceRequestButtonText"
    }
}) do
    table.insert(controls, button_widget(action.control))
    table.insert(controls, text_widget(action.text_control))
end
for _, navigation in ipairs({
    {
        control = "PreviousRelationButton",
        text_control = "PreviousRelationButtonText"
    },
    {
        control = "NextRelationButton",
        text_control = "NextRelationButtonText"
    },
    {
        control = "PreviousAllianceButton",
        text_control = "PreviousAllianceButtonText"
    },
    {
        control = "NextAllianceButton",
        text_control = "NextAllianceButtonText"
    }
}) do
    table.insert(controls, button_widget(navigation.control))
    table.insert(controls, text_widget(navigation.text_control))
end
for _, tab in ipairs({
    { control = "ClanTabButton", text_control = "ClanTabText" },
    {
        control = "DiplomacyTabButton",
        text_control = "DiplomacyTabText"
    }
}) do
    table.insert(controls, button_widget(tab.control))
    table.insert(controls, text_widget(tab.text_control))
end
local root = widget("RootCanvas", {
    widget("PanelBackground", controls)
})
local panel = {
    WidgetTree = { RootWidget = root }
}

local binder = UMGViewBinder.new({
    make_text = function(value) return value end
})
local model = {
    schema_version = 1,
    active_tab = "DIPLOMACY",
    error = "",
    connection = {
        ready = true,
        status_text = "Sunucu snapshoti hazir"
    },
    tabs = {
        {
            id = "CLAN",
            label = "Klanim",
            display_label = "Klanim (2)",
            control = "ClanTabButton",
            text_control = "ClanTabText",
            page_index = 0,
            active = false,
            enabled = true
        },
        {
            id = "DIPLOMACY",
            label = "Diplomasi",
            display_label = "Diplomasi (1)",
            control = "DiplomacyTabButton",
            text_control = "DiplomacyTabText",
            page_index = 1,
            active = true,
            enabled = false
        }
    },
    views = {
        CLAN = {
            guild = { name = "Anka" },
            member_count = 2,
            online_count = 1,
            empty = false,
            name_text = "Anka",
            summary_text = "Lider: Ada | Üye: 2 | Çevrimiçi: 1\nSavaş: 1 | İttifak: 0 | Bekleyen: 0",
            members_text = "Ada (cevrimici)\nBora",
            pending_text = "Teklifçiler | İttifak teklifi bekliyor | Gelen teklif",
            dashboard = {
                relations_text = "Rakipler | Savas\nTeklifciler | Ittifak teklifi bekliyor",
                cards = {
                    {
                        id = "CLAN_STATUS",
                        title_control = "DashboardClanCardTitleText",
                        value_control = "DashboardClanCardValueText",
                        detail_control = "DashboardClanCardDetailText",
                        title = "Klanim",
                        value = "Anka",
                        detail = "Lider: Ada | Uye: 2 | Cevrimici: 1"
                    },
                    {
                        id = "DIPLOMACY_STATUS",
                        title_control = "DashboardDiplomacyCardTitleText",
                        value_control = "DashboardDiplomacyCardValueText",
                        detail_control = "DashboardDiplomacyCardDetailText",
                        title = "Diplomasi",
                        value = "Savas: 1 | Ittifak: 0 | Bekleyen: 1",
                        detail = ""
                    }
                }
            },
            quick_actions = {
                DashboardDiplomacyButton = {
                    control = "DashboardDiplomacyButton",
                    text_control = "DashboardDiplomacyButtonText",
                    label = "Diplomasiyi Ac",
                    enabled = true
                },
                DashboardOffersButton = {
                    control = "DashboardOffersButton",
                    text_control = "DashboardOffersButtonText",
                    label = "Teklifleri Gor",
                    enabled = true
                },
                DashboardGuildsButton = {
                    control = "DashboardGuildsButton",
                    text_control = "DashboardGuildsButtonText",
                    label = "Klanlari Listele",
                    enabled = false
                }
            },
            members = {
                { name = "Ada", online = true },
                { name = "Bora", online = false }
            }
        },
        DIPLOMACY = {
            empty = false,
            list_text = "Rakipler | Savas",
            title_text = "Rakipler",
            state_text = "Savas",
            description_text = "Sinir catismasi",
            navigation_controls = {
                PreviousRelationButton = {
                    control = "PreviousRelationButton",
                    text_control = "PreviousRelationButtonText",
                    label = "Onceki",
                    enabled = true
                },
                NextRelationButton = {
                    control = "NextRelationButton",
                    text_control = "NextRelationButtonText",
                    label = "Sonraki",
                    enabled = false
                }
            },
            action_controls = {
                WarRequestButton = {
                    control = "WarRequestButton",
                    text_control = "WarRequestButtonText",
                    label = "Savas Ilan Et",
                    enabled = true
                },
                AllianceRequestButton = {
                    control = "AllianceRequestButton",
                    text_control = "AllianceRequestButtonText",
                    label = "Ittifak Iste",
                    enabled = false
                }
            },
            relations = {
                {
                    guild = { name = "Rakipler" },
                    status = { label = "Savas" }
                }
            },
            selected_relation = {
                guild = { name = "Rakipler" },
                status = {
                    label = "Savas",
                    proposal_direction_label = "",
                    note = "Sinir catismasi"
                },
                permissions = { reason = "" }
            }
        },
        ALLIANCE = {
            empty = true,
            empty_message = "Ittifak yok.",
            summary_text = "0 ittifak kaydi",
            members_text = "Ittifak yok.",
            title_text = "Ittifak secin",
            state_text = "Ittifak durumu: -",
            description_text = "Ittifak ayrintisi yok.",
            relations = {},
            navigation_controls = {
                PreviousAllianceButton = {
                    control = "PreviousAllianceButton",
                    text_control = "PreviousAllianceButtonText",
                    label = "Onceki",
                    enabled = false
                },
                NextAllianceButton = {
                    control = "NextAllianceButton",
                    text_control = "NextAllianceButtonText",
                    label = "Sonraki",
                    enabled = false
                }
            }
        },
        GUILDS = {
            empty = false,
            summary_text = "2 klan | 1 aktif",
            list_text = "Gezginler | Aktif | 4 uye | 2 cevrimici",
            active_text = "Gezginler | Aktif | 4 uye | 2 cevrimici",
            registered_text = "Uykudakiler | Kayitli | 3 uye | 0 cevrimici",
            guilds = {
                { name = "Gezginler", active = true }
            }
        }
    }
}

local bound, bind_error = binder:bind(panel, model)
equal(bound, true, "view model bound")
equal(bind_error, nil, "successful bind has no error")
equal(switch_index, 1, "diplomacy tab selected")
equal(text_values.TitleText, "PALTR DİPLOMASİ MODU", "panel title")
equal(text_values.ConnectionStatusText, "Sunucu snapshoti hazir", "status")
equal(text_values.ClanNameText, "Anka", "clan name")
equal(text_values.ClanSummaryText,
    "Lider: Ada | Üye: 2 | Çevrimiçi: 1\nSavaş: 1 | İttifak: 0 | Bekleyen: 0",
    "clan summary")
equal(text_values.ClanMembersText, "Ada (cevrimici)\nBora", "members")
equal(text_values.PendingOffersText,
    "Teklifçiler | İttifak teklifi bekliyor | Gelen teklif",
    "pending offers")
equal(text_values.DashboardDiplomacyButtonText, "Diplomasiyi Ac",
    "dashboard diplomacy label")
equal(enabled_values.DashboardDiplomacyButton, true,
    "dashboard diplomacy enabled")
equal(text_values.DashboardOffersButtonText, "Teklifleri Gor",
    "dashboard offers label")
equal(enabled_values.DashboardGuildsButton, false,
    "dashboard guilds disabled")
equal(text_values.DashboardClanCardTitleText, "Klanim",
    "clan dashboard card title")
equal(text_values.DashboardClanCardValueText, "Anka",
    "clan dashboard card value")
equal(text_values.DashboardClanCardDetailText,
    "Lider: Ada | Uye: 2 | Cevrimici: 1",
    "clan dashboard card detail")
equal(text_values.DashboardDiplomacyCardTitleText, "Diplomasi",
    "diplomacy dashboard card title")
equal(text_values.DashboardDiplomacyCardValueText,
    "Savas: 1 | Ittifak: 0 | Bekleyen: 1",
    "diplomacy dashboard card value")
equal(text_values.DashboardRelationsText,
    "Rakipler | Savas\nTeklifciler | Ittifak teklifi bekliyor",
    "dashboard relation preview")
equal(text_values.RelationListEmptyText, "Rakipler | Savas", "relations")
equal(text_values.RelationTitleText, "Rakipler", "selected guild")
equal(text_values.RelationStateText, "Savas", "relation state")
equal(text_values.RelationDescriptionText, "Sinir catismasi", "relation detail")
equal(text_values.AllianceMembersText, "Ittifak yok.", "empty alliance")
equal(text_values.AllianceTitleText, "Ittifak secin", "alliance title")
equal(text_values.AllianceStateText, "Ittifak durumu: -", "alliance state")
equal(text_values.PreviousAllianceButtonText, "Onceki",
    "alliance previous label")
equal(enabled_values.NextAllianceButton, false,
    "alliance next disabled")
equal(text_values.ChatEmptyText,
    "Gezginler | Aktif | 4 uye | 2 cevrimici", "guild catalog")
equal(text_values.GuildCatalogSummaryText, "2 klan | 1 aktif",
    "guild catalog summary")
equal(text_values.GuildCatalogActiveText,
    "Gezginler | Aktif | 4 uye | 2 cevrimici", "active guild catalog")
equal(text_values.GuildCatalogRegisteredText,
    "Uykudakiler | Kayitli | 3 uye | 0 cevrimici",
    "registered guild catalog")
equal(text_values.ClanTabText, "Klanim (2)", "clan tab label")
equal(enabled_values.ClanTabButton, true, "inactive tab enabled")
equal(text_values.DiplomacyTabText, "Diplomasi (1)", "diplomacy tab label")
equal(enabled_values.DiplomacyTabButton, false, "active tab disabled")
equal(text_values.WarRequestButtonText, "Savas Ilan Et", "war label")
equal(enabled_values.WarRequestButton, true, "war button enabled")
equal(text_values.PreviousRelationButtonText, "Onceki",
    "previous relation label")
equal(enabled_values.PreviousRelationButton, true,
    "previous relation enabled")
equal(text_values.NextRelationButtonText, "Sonraki",
    "next relation label")
equal(enabled_values.NextRelationButton, false,
    "next relation disabled")
equal(
    enabled_values.AllianceRequestButton,
    false,
    "alliance button disabled"
)

local converted_values = {}
local fallback_binder = UMGViewBinder.new({
    get_text_library = function()
        return {
            Conv_StringToText = function(_, value)
                table.insert(converted_values, value)
                return "FText:" .. value
            end
        }
    end
})
local fallback_bound, fallback_error = fallback_binder:bind(panel, model)
equal(fallback_bound, true, "Kismet text fallback bound")
equal(fallback_error, nil, "Kismet text fallback has no error")
equal(#converted_values > 0, true, "Kismet text fallback used")
equal(
    text_values.ClanNameText,
    "FText:Anka",
    "Kismet text fallback result passed to widget"
)

local invalid_model, model_error = binder:bind(panel, nil)
equal(invalid_model, false, "missing model rejected")
equal(model_error, "Gorunum modeli bulunamadi.", "model error")

local missing_tree, tree_error = binder:bind({}, model)
equal(missing_tree, false, "missing tree rejected")
equal(tree_error, "PalTR widget agaci bulunamadi.", "tree error")

local missing_control_panel = {
    WidgetTree = { RootWidget = widget("RootCanvas", { switcher }) }
}
local controls_bound, controls_error = binder:bind(missing_control_panel, model)
equal(controls_bound, false, "missing text control rejected")
equal(controls_error, "UMG kontrolu bulunamadi: TitleText", "control error")

print("PALTR_UI_UMG_VIEW_BINDER_TEST_OK")
