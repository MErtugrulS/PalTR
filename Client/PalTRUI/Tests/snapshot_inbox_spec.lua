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

local function snapshot(generated_at)
    return {
        schema_version = 1,
        generated_at = generated_at,
        player = { name = "Ada", guild_key = "own", role = 1, is_master = true },
        guild = { key = "own", name = "Anka" },
        members = {},
        relations = {}
    }
end

local renders = 0
local controller = PresentationController.new({
    render = function()
        renders = renders + 1
        return true
    end
})
local inbox = SnapshotInbox.new(controller)

local received, model, rendered, receive_error = inbox:receive(snapshot(20))
equal(received, true, "new snapshot received")
equal(model.generated_at, 20, "new snapshot model returned")
equal(rendered, true, "new snapshot rendered")
equal(receive_error, nil, "new snapshot has no error")

local renders_before_stale = renders
local stale, stale_model, stale_rendered, stale_error =
    inbox:receive(snapshot(19))
equal(stale, false, "stale snapshot rejected")
equal(stale_model.generated_at, 20, "newer model preserved")
equal(stale_rendered, false, "stale snapshot not rendered")
equal(stale_error, "Eski sunucu snapshoti reddedildi.",
    "stale snapshot error")
equal(renders, renders_before_stale, "stale snapshot skips renderer")

local same_time, same_model = inbox:receive(snapshot(20))
equal(same_time, true, "same timestamp snapshot accepted")
equal(same_model.generated_at, 20, "same timestamp model returned")

local invalid = snapshot(21)
invalid.relations = { "invalid" }
local invalid_received, invalid_model, invalid_rendered, invalid_error =
    inbox:receive(invalid)
equal(invalid_received, false, "invalid snapshot rejected")
equal(invalid_rendered, true, "invalid snapshot error rendered")
equal(invalid_model.generated_at, 20, "invalid snapshot preserves data")
equal(invalid_error, "Sunucu UI verisi geçersiz: relations.item",
    "invalid snapshot reason returned")
equal(inbox.last_generated_at, 20, "invalid timestamp not committed")

local missing, _, missing_rendered, missing_error =
    SnapshotInbox.new():receive(snapshot(1))
equal(missing, false, "missing controller rejected")
equal(missing_rendered, false, "missing controller not rendered")
equal(missing_error, "UI sunum controller'i hazir degil.",
    "missing controller error")

print("PALTR_UI_SNAPSHOT_INBOX_TEST_OK")
