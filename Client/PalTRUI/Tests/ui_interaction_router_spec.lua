local UIInteractionRouter = require("ui_interaction_router")

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

local calls = {}
local current_model = {
    open = true,
    active_tab = "DIPLOMACY",
    tabs = {
        { id = "CLAN", control = "ClanTabButton" },
        { id = "DIPLOMACY", control = "DiplomacyTabButton" },
        { id = "ALLIANCE", control = "AllianceTabButton" },
        { id = "GUILDS", control = "ChatTabButton" },
        { id = "MANAGEMENT", control = "ManagementTabButton" }
    },
    views = {
        CLAN = {
            quick_actions = {
                DashboardGuildsButton = {
                    target_tab = "GUILDS",
                    enabled = true
                },
                DashboardOffersButton = {
                    target_tab = "DIPLOMACY",
                    enabled = false,
                    reason = "Bekleyen teklif yok."
                },
                DashboardPendingButton = {
                    target_tab = "DIPLOMACY",
                    target_guild = "guild-pending",
                    enabled = true
                },
                DashboardPendingAcceptButton = {
                    target_tab = "DIPLOMACY",
                    target_guild = "guild-pending",
                    action_id = "ACCEPT",
                    enabled = true
                }
            }
        },
        DIPLOMACY = {
            relations = {
                {
                    guild = { key = "guild-first", name = "First" }
                },
                {
                    guild = { key = "guild-second", name = "Second" }
                }
            },
            navigation_controls = {
                PreviousRelationButton = {
                    step = -1,
                    enabled = true
                },
                NextRelationButton = {
                    step = 1,
                    enabled = false,
                    reason = "Gezinme kapali."
                }
            },
            action_controls = {
                WarRequestButton = {
                    action_id = "DECLARE_WAR",
                    enabled = true
                },
                AllianceRequestButton = {
                    action_id = "ALLIANCE",
                    enabled = false,
                    reason = "Bu aksiyon sunulmuyor."
                }
            }
        },
        ALLIANCE = {
            navigation_controls = {
                PreviousAllianceButton = {
                    step = -1,
                    enabled = true
                },
                NextAllianceButton = {
                    step = 1,
                    enabled = true
                }
            }
        },
        MANAGEMENT = {
            colors = {
                { id = "azure", available = true },
                { id = "cyan", available = false }
            },
            emblems = {
                { id = "wolf", name = "Kurt" },
                { id = "eagle", name = "Kartal" }
            },
            save_control = {
                enabled = true
            }
        }
    }
}
local controller = {
    toggle = function()
        table.insert(calls, { name = "toggle" })
        return { open = false, active_tab = "GUILDS" }, true
    end,
    set_tab = function(_, tab_id)
        table.insert(calls, { name = "set_tab", tab_id = tab_id })
        return true, { open = true, active_tab = tab_id }, true
    end,
    model = function()
        return current_model
    end,
    request_action = function(_, action_id)
        table.insert(calls, {
            name = "request_action",
            action_id = action_id
        })
        return true, { action_id = action_id }
    end,
    navigate_relation = function(_, step)
        table.insert(calls, {
            name = "navigate_relation",
            step = step
        })
        return true, current_model
    end,
    select_guild = function(_, guild_key)
        table.insert(calls, {
            name = "select_guild",
            guild_key = guild_key
        })
        return true, {
            open = true,
            active_tab = "DIPLOMACY",
            selected_guild = guild_key
        }, true
    end,
    open_relation = function(_, tab_id, guild_key)
        table.insert(calls, {
            name = "open_relation",
            tab_id = tab_id,
            guild_key = guild_key
        })
        return true, {
            open = true,
            active_tab = tab_id,
            selected_guild = guild_key
        }, true
    end,
    select_guild_identity = function(_, kind, identity_id)
        table.insert(calls, {
            name = "select_guild_identity",
            kind = kind,
            identity_id = identity_id
        })
        return true, current_model, true
    end,
    request_guild_identity = function()
        table.insert(calls, { name = "request_guild_identity" })
        return true, { queued = true }
    end
}
local router = UIInteractionRouter.new(controller)

local tab_controls = {
    ClanTabButton = "CLAN",
    DiplomacyTabButton = "DIPLOMACY",
    AllianceTabButton = "ALLIANCE",
    ChatTabButton = "GUILDS",
    ManagementTabButton = "MANAGEMENT"
}
for control_name, tab_id in pairs(tab_controls) do
    local handled, model, rendered, route_error =
        router:handle(control_name)
    equal(handled, true, control_name .. " handled")
    equal(model.active_tab, tab_id, control_name .. " tab routed")
    equal(rendered, true, control_name .. " rendered")
    equal(route_error, nil, control_name .. " has no error")
end

local color_handled, color_model, color_rendered, color_error =
    router:handle("GuildIdentityColorButton01")
equal(color_handled, true, "guild identity color handled")
equal(color_model, current_model, "guild identity color model returned")
equal(color_rendered, true, "guild identity color rendered")
equal(color_error, nil, "guild identity color has no error")
equal(calls[#calls].name, "select_guild_identity",
    "guild identity color routed")
equal(calls[#calls].kind, "color", "guild identity color kind")
equal(calls[#calls].identity_id, "azure", "guild identity color id")

local emblem_handled, emblem_model, emblem_rendered, emblem_error =
    router:handle("GuildIdentityEmblemButton02")
equal(emblem_handled, true, "guild identity emblem handled")
equal(emblem_model, current_model, "guild identity emblem model returned")
equal(emblem_rendered, true, "guild identity emblem rendered")
equal(emblem_error, nil, "guild identity emblem has no error")
equal(calls[#calls].name, "select_guild_identity",
    "guild identity emblem routed")
equal(calls[#calls].kind, "emblem", "guild identity emblem kind")
equal(calls[#calls].identity_id, "eagle", "guild identity emblem id")

local identity_saved, identity_save_model, identity_save_rendered,
    identity_save_error = router:handle("GuildIdentitySaveButton")
equal(identity_saved, true, "guild identity save handled")
equal(identity_save_model, current_model, "guild identity save model returned")
equal(identity_save_rendered, true, "guild identity save rendered")
equal(identity_save_error, nil, "guild identity save has no error")
equal(calls[#calls].name, "request_guild_identity",
    "guild identity save routed")

local row_handled, row_model, row_rendered, row_error =
    router:handle("DiplomacyRelationRowButton02")
equal(row_handled, true, "diplomacy relation row handled")
equal(row_model.selected_guild, "guild-second",
    "diplomacy relation row guild selected")
equal(row_rendered, true, "diplomacy relation row rendered")
equal(row_error, nil, "diplomacy relation row has no error")
equal(calls[#calls].name, "select_guild",
    "diplomacy relation row routed to selection")
equal(calls[#calls].guild_key, "guild-second",
    "diplomacy relation row uses visible row guild")

local missing_row, _, missing_row_rendered, missing_row_error =
    router:handle("DiplomacyRelationRowButton06")
equal(missing_row, false, "empty diplomacy relation row rejected")
equal(missing_row_rendered, false,
    "empty diplomacy relation row not rendered")
equal(missing_row_error, "UI kontrol etkilesimi tanimli degil.",
    "empty diplomacy relation row falls through safely")


local quick_handled, quick_model, quick_rendered, quick_error =
    router:handle("DashboardGuildsButton")
equal(quick_handled, true, "dashboard quick action handled")
equal(quick_model.active_tab, "GUILDS", "dashboard target tab")
equal(quick_rendered, true, "dashboard quick action rendered")
equal(quick_error, nil, "dashboard quick action has no error")

local quick_disabled, _, quick_disabled_rendered, quick_disabled_error =
    router:handle("DashboardOffersButton")
equal(quick_disabled, false, "disabled dashboard action rejected")
equal(quick_disabled_rendered, false, "disabled dashboard action not rendered")
equal(quick_disabled_error, "Bekleyen teklif yok.",
    "disabled dashboard reason")

local pending_handled, pending_model, pending_rendered, pending_error =
    router:handle("DashboardPendingButton")
equal(pending_handled, true, "pending dashboard action handled")
equal(pending_model.selected_guild, "guild-pending",
    "pending dashboard guild selected")
equal(pending_rendered, true, "pending dashboard rendered")
equal(pending_error, nil, "pending dashboard has no error")
equal(calls[#calls].name, "open_relation",
    "pending relation opened atomically")

local pending_accept_handled, pending_accept_model,
    pending_accept_rendered, pending_accept_error =
    router:handle("DashboardPendingAcceptButton")
equal(pending_accept_handled, true, "pending accept handled")
equal(pending_accept_model.selected_guild, "guild-pending",
    "pending accept guild selected")
equal(pending_accept_rendered, true, "pending accept rendered")
equal(pending_accept_error, nil, "pending accept has no error")
equal(calls[#calls].name, "request_action",
    "pending accept dispatched after selection")
equal(calls[#calls].action_id, "ACCEPT", "pending accept action id")

local closed, closed_model, close_rendered =
    router:handle("CloseButton")
equal(closed, true, "close handled")
equal(closed_model.open, false, "close model returned")
equal(close_rendered, true, "close rendered")
equal(calls[#calls].name, "toggle", "close routed to toggle")

local navigated, navigation_model, navigation_rendered,
    navigation_error = router:handle("PreviousRelationButton")
equal(navigated, true, "navigation control handled")
equal(navigation_model, current_model, "navigation model returned")
equal(navigation_rendered, true, "navigation rendered")
equal(navigation_error, nil, "navigation has no error")
equal(calls[#calls].name, "navigate_relation", "navigation routed")
equal(calls[#calls].step, -1, "navigation model step used")

local navigation_disabled, _, navigation_dispatched,
    navigation_disabled_error = router:handle("NextRelationButton")
equal(navigation_disabled, false, "disabled navigation rejected")
equal(navigation_dispatched, false, "disabled navigation not dispatched")
equal(navigation_disabled_error, "Gezinme kapali.",
    "disabled navigation reason returned")

current_model.active_tab = "ALLIANCE"
local alliance_navigated, alliance_model, alliance_rendered,
    alliance_error = router:handle("NextAllianceButton")
equal(alliance_navigated, true, "alliance navigation handled")
equal(alliance_model, current_model, "alliance navigation model returned")
equal(alliance_rendered, true, "alliance navigation rendered")
equal(alliance_error, nil, "alliance navigation has no error")
equal(calls[#calls].step, 1, "alliance navigation step used")
current_model.active_tab = "DIPLOMACY"

local action_handled, action_model, action_dispatched, action_error =
    router:handle("WarRequestButton")
equal(action_handled, true, "action control handled")
equal(action_model, current_model, "action model returned")
equal(action_dispatched, true, "action dispatched")
equal(action_error, nil, "action has no error")
equal(calls[#calls].name, "request_action", "action routed")
equal(calls[#calls].action_id, "DECLARE_WAR", "model action id used")

local disabled, disabled_model, disabled_dispatched, disabled_error =
    router:handle("AllianceRequestButton")
equal(disabled, false, "disabled action rejected")
equal(disabled_model, current_model, "disabled model returned")
equal(disabled_dispatched, false, "disabled action not dispatched")
equal(disabled_error, "Bu aksiyon sunulmuyor.", "model reason returned")
equal(calls[#calls].action_id, "DECLARE_WAR", "disabled action not routed")

local unknown, _, unknown_rendered, unknown_error =
    router:handle("UnknownButton")
equal(unknown, false, "unknown control rejected")
equal(unknown_rendered, false, "unknown control not rendered")
equal(
    unknown_error,
    "UI kontrol etkilesimi tanimli degil.",
    "unknown control error"
)

local failed = UIInteractionRouter.new({
    toggle = controller.toggle,
    model = controller.model,
    set_tab = function(_, tab_id)
        return true, { open = true, active_tab = tab_id },
            false, "renderer failed"
    end
})
local failed_handled, failed_model,
    failed_rendered, failed_error =
    failed:handle("ChatTabButton")
equal(failed_handled, false, "renderer failure rejects interaction")
equal(failed_model.active_tab, "GUILDS", "failed interaction model returned")
equal(failed_rendered, false, "renderer failure returned")
equal(failed_error, "renderer failed", "renderer error preserved")

local missing, _, missing_rendered, missing_error =
    UIInteractionRouter.new():handle("ClanTabButton")
equal(missing, false, "missing controller rejected")
equal(missing_rendered, false, "missing controller not rendered")
equal(
    missing_error,
    "UI sunum controller'i hazir degil.",
    "missing controller error"
)

print("PALTR_UI_INTERACTION_ROUTER_TEST_OK")
