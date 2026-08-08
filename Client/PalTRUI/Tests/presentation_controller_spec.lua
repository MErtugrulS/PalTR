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

local controller = PresentationController.new(renderer)
equal(controller:model().open, false, "initial panel state")
equal(#rendered, 1, "initial model rendered")
equal(rendered[1], controller:model(), "renderer receives view model")

local toggled = controller:toggle()
equal(toggled.open, true, "toggle returns current model")
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

local invalid_accepted, invalid = controller:apply_snapshot({})
equal(invalid_accepted, false, "invalid snapshot rejected")
equal(invalid.active_tab, "DIPLOMACY", "presentation state preserved")
equal(rendered[#rendered], invalid, "error model rendered")

local without_renderer = PresentationController.new()
equal(without_renderer:model().active_tab, "CLAN", "renderer is optional")

print("PALTR_UI_PRESENTATION_CONTROLLER_TEST_OK")
