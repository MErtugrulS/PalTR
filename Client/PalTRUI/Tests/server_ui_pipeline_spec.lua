local ActionOutbox = require("action_outbox")
local PresentationController = require("presentation_controller")
local SnapshotInbox = require("snapshot_inbox")

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

package.loaded["PalTR.core.clock"] = {
    now = function() return 700 end
}
package.loaded["PalTR.services.ui_snapshot_service"] = nil
local UISnapshotService = require("PalTR.services.ui_snapshot_service")

local registry = {
    guilds = {
        own = { name = "Anka" },
        other = { name = "Rakipler" }
    },
    players = {},
    runtime_players = {}
}
local diplomacy = {
    relations_for = function()
        return {
            {
                guild_a = "own",
                guild_b = "other",
                state = "NEUTRAL",
                previous_state = "NEUTRAL",
                requested_by = "",
                accepted_by = "",
                active_at = 0,
                expires_at = 0,
                note = ""
            }
        }
    end
}
local actions = {
    for_relation = function()
        return {
            can_manage = true,
            reason = "",
            actions = {
                { id = "DECLARE_WAR", label = "Savas Ilan Et" }
            }
        }
    end
}

local snapshot = UISnapshotService.new(
    registry,
    diplomacy,
    actions
):build({
    name = "Ada",
    guild_key = "own",
    role = 1,
    is_master = true
})

local envelopes = {}
local outbox = ActionOutbox.new({
    send = function(_, envelope)
        table.insert(envelopes, envelope)
        return true, envelope
    end
})
local controller = PresentationController.new(nil, outbox)
local received, model = SnapshotInbox.new(controller):receive(snapshot)
equal(received, true, "server snapshot enters client inbox")
equal(model.capabilities.action_transport_ready, true,
    "server pipeline exposes action transport capability")
equal(model.selected_guild, "other", "server relation selected")
equal(
    model.views.DIPLOMACY.action_controls.WarRequestButton.enabled,
    true,
    "server action enables presentation control"
)

local dispatched, envelope = controller:request_action("DECLARE_WAR")
equal(dispatched, true, "server offered action dispatched")
equal(#envelopes, 1, "single action envelope sent")
equal(envelope.kind, "DIPLOMACY_ACTION", "pipeline action kind")
equal(envelope.guild_key, "other", "pipeline target guild")
equal(envelope.action_id, "DECLARE_WAR", "pipeline action id")
equal(envelope.snapshot_generated_at, 700, "pipeline snapshot timestamp")

local unavailable, unavailable_error = controller:request_action("ALLIANCE")
equal(unavailable, false, "server unoffered action rejected")
equal(unavailable_error,
    "Aksiyon guncel sunucu snapshotinda sunulmuyor.",
    "server action list remains authoritative")
equal(#envelopes, 1, "rejected action does not reach outbox")

print("PALTR_UI_SERVER_PIPELINE_TEST_OK")
