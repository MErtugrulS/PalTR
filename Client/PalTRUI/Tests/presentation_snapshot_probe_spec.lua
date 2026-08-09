local PresentationController = require("presentation_controller")
local PresentationSnapshotProbe = require("presentation_snapshot_probe")
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

local controller = PresentationController.new()
local applied, model, apply_error = PresentationSnapshotProbe.apply(
    controller,
    SnapshotInbox.new(controller)
)
equal(applied, true, "presentation snapshot applied")
equal(apply_error, nil, "presentation snapshot has no error")
equal(model.active_tab, "DIPLOMACY", "probe opens diplomacy")
equal(model.selected_guild, "probe-neutral", "probe relation selected")
equal(model.views.CLAN.member_count, 2, "probe clan members")
equal(model.views.DIPLOMACY.action_controls.WarRequestButton.enabled,
    true, "probe war action enabled")
equal(model.views.DIPLOMACY.action_controls.AllianceRequestButton.enabled,
    true, "probe alliance action enabled")
equal(model.views.ALLIANCE.empty, false, "probe alliance populated")
equal(PresentationSnapshotProbe.is_active(model), true, "probe model active")
equal(PresentationSnapshotProbe.is_active({}), false, "normal model inactive")

local cycled, cycled_model, cycle_error =
    PresentationSnapshotProbe.select_next(PresentationController.new())
equal(cycled, false, "empty relation cycle rejected")
equal(cycle_error, "Secilebilir diplomasi kaydi bulunamadi.",
    "empty relation cycle error")

local cycle_controller = PresentationController.new()
PresentationSnapshotProbe.apply(
    cycle_controller,
    SnapshotInbox.new(cycle_controller)
)
local selected_next, next_model, next_error =
    PresentationSnapshotProbe.select_next(cycle_controller)
equal(selected_next, true, "next relation selected")
equal(next_error, nil, "next relation has no error")
equal(next_model.selected_guild, "probe-alliance", "relation wraps")
equal(next_model.views.DIPLOMACY.title_text, "Müttefikler",
    "selected relation rendered")
equal(next_model.views.DIPLOMACY.list_text,
    "> Müttefikler | İttifak\n  Tarafsızlar | Tarafsız",
    "selected relation marked")

local rejected, _, rejection = PresentationSnapshotProbe.apply()
equal(rejected, false, "missing controller rejected")
equal(rejection, "UI sunum controller'i hazir degil.",
    "missing controller error")

print("PALTR_UI_PRESENTATION_SNAPSHOT_PROBE_TEST_OK")
