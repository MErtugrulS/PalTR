local PresentationController = require("presentation_controller")

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

local function snapshot()
    return {
        schema_version = 1,
        generated_at = 12345,
        player = {
            name = "Ada",
            guild_key = "guild-own",
            role = 1,
            is_master = true
        },
        guild = {
            key = "guild-own",
            name = "Anka"
        },
        members = {},
        relations = {
            {
                guild_key = "guild-other",
                guild_name = "Diger Klan",
                state = "NEUTRAL",
                can_manage = true,
                action_reason = "",
                actions = {
                    { id = "DECLARE_WAR", label = "Savas Ilan Et" }
                }
            }
        }
    }
end

local rendered = {}
local renderer = {
    render = function(_, model)
        table.insert(rendered, model)
    end
}

local dispatched = {}
local action_sink = {
    dispatch = function(_, intent)
        table.insert(dispatched, intent)
        return true, intent
    end
}

local controller = PresentationController.new(renderer, action_sink)
equal(controller:model().open, false, "initial panel state")
equal(#rendered, 1, "initial model rendered")
equal(rendered[1], controller:model(), "renderer receives view model")

local toggled, toggled_rendered, toggle_error = controller:toggle()
equal(toggled.open, true, "toggle returns current model")
equal(toggled_rendered, true, "toggle reports renderer success")
equal(toggle_error, nil, "successful toggle has no renderer error")
equal(#rendered, 2, "toggle rendered")
equal(rendered[2], toggled, "toggle model rendered")

local accepted, diplomacy = controller:set_tab("DIPLOMACY")
equal(accepted, true, "known tab accepted")
equal(diplomacy.active_tab, "DIPLOMACY", "tab model updated")
equal(rendered[#rendered], diplomacy, "tab model rendered")

local snapshot_accepted, populated = controller:apply_snapshot(snapshot())
equal(snapshot_accepted, true, "snapshot accepted")
equal(populated.selected_guild, "guild-other", "relation selected")
equal(rendered[#rendered], populated, "snapshot model rendered")
equal(
    populated.views.DIPLOMACY.selected_relation.actions[1].id,
    "DECLARE_WAR",
    "server action preserved"
)

local action_dispatched, intent = controller:request_action("DECLARE_WAR")
equal(action_dispatched, true, "offered action dispatched")
equal(#dispatched, 1, "single action intent dispatched")
equal(intent, dispatched[1], "action sink result preserved")
equal(intent.guild_key, "guild-other", "selected guild dispatched")

local rejected, rejection = controller:request_action("PEACE")
equal(rejected, false, "unoffered action not dispatched")
equal(#dispatched, 1, "rejected action does not reach sink")
equal(
    rejection,
    "Aksiyon guncel sunucu snapshotinda sunulmuyor.",
    "rejection returned"
)

local chat_model = controller:set_chat_available(true)
equal(chat_model.views.CHAT.available, true, "chat availability rendered")

local chat_accepted, chat_populated = controller:append_chat({
    id = "message-1",
    sender = "Ada",
    text = "Merhaba",
    timestamp = 12346,
    kind = "GUILD"
})
equal(chat_accepted, true, "chat append accepted")
equal(chat_populated.views.CHAT.message_count, 1, "chat rendered")
equal(rendered[#rendered], chat_populated, "chat model sent to renderer")

local invalid_chat, unchanged_chat = controller:append_chat("invalid")
equal(invalid_chat, false, "invalid chat rejected")
equal(unchanged_chat.views.CHAT.message_count, 1, "chat preserved")
equal(rendered[#rendered], chat_populated, "invalid chat not rendered")

local invalid_accepted, invalid = controller:apply_snapshot({})
equal(invalid_accepted, false, "invalid snapshot rejected")
equal(invalid.active_tab, "DIPLOMACY", "presentation state preserved")
equal(rendered[#rendered], invalid, "error model rendered")

local without_renderer = PresentationController.new()
equal(without_renderer:model().active_tab, "CLAN", "renderer is optional")

local failed_renderer = PresentationController.new({
    render = function()
        return false, "renderer failed"
    end
})
local failed_model, failed_rendered, failed_error = failed_renderer:toggle()
equal(failed_model.open, true, "failed renderer preserves panel state")
equal(failed_rendered, false, "renderer failure returned")
equal(failed_error, "renderer failed", "renderer error returned")

local transport_missing, transport_error =
    without_renderer:request_action("DECLARE_WAR")
equal(transport_missing, false, "missing transport rejected")
equal(
    transport_error,
    "Diplomasi kaydi secilmedi.",
    "model validation precedes transport"
)

print("PALTR_UI_PRESENTATION_CONTROLLER_TEST_OK")
