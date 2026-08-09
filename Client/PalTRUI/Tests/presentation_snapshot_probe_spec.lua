local PresentationController = require("presentation_controller")
local PresentationSnapshotProbe = require("presentation_snapshot_probe")

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

local applied, model, apply_error = PresentationSnapshotProbe.apply(
    PresentationController.new()
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

local rejected, _, rejection = PresentationSnapshotProbe.apply()
equal(rejected, false, "missing controller rejected")
equal(rejection, "UI sunum controller'i hazir degil.",
    "missing controller error")

print("PALTR_UI_PRESENTATION_SNAPSHOT_PROBE_TEST_OK")
