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
    views = {
        DIPLOMACY = {
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
        }
    }
}
local controller = {
    toggle = function()
        table.insert(calls, { name = "toggle" })
        return { open = false, active_tab = "CHAT" }, true
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
    end
}
local router = UIInteractionRouter.new(controller)

local tab_controls = {
    ClanTabButton = "CLAN",
    DiplomacyTabButton = "DIPLOMACY",
    AllianceTabButton = "ALLIANCE",
    ChatTabButton = "CHAT"
}
for control_name, tab_id in pairs(tab_controls) do
    local handled, model, rendered, route_error =
        router:handle(control_name)
    equal(handled, true, control_name .. " handled")
    equal(model.active_tab, tab_id, control_name .. " tab routed")
    equal(rendered, true, control_name .. " rendered")
    equal(route_error, nil, control_name .. " has no error")
end

local closed, closed_model, close_rendered =
    router:handle("CloseButton")
equal(closed, true, "close handled")
equal(closed_model.open, false, "close model returned")
equal(close_rendered, true, "close rendered")
equal(calls[#calls].name, "toggle", "close routed to toggle")

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
    set_tab = function(_, tab_id)
        return true, { open = true, active_tab = tab_id },
            false, "renderer failed"
    end
})
local failed_handled, failed_model,
    failed_rendered, failed_error =
    failed:handle("ChatTabButton")
equal(failed_handled, false, "renderer failure rejects interaction")
equal(failed_model.active_tab, "CHAT", "failed interaction model returned")
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
