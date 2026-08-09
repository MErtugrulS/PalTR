local UMGButtonPoller = require("umg_button_poller")

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

local frames = {
    { pressed = true, hovered = true },
    { pressed = false, hovered = true }
}
local frame_index = 0
local routed = {}
local results = {}
local scheduled = nil
local poller = UMGButtonPoller.new({
    widget_provider = function() return {} end,
    control_names = { "ClanTabButton" },
    sampler = {
        sample = function()
            frame_index = frame_index + 1
            local frame = frames[frame_index]
            return true, {
                {
                    control = "ClanTabButton",
                    available = true,
                    pressed = frame.pressed,
                    hovered_available = true,
                    hovered = frame.hovered
                }
            }
        end
    },
    router = {
        handle = function(_, control)
            table.insert(routed, control)
            return true, { open = true }, true
        end
    },
    schedule_loop = function(_, callback) scheduled = callback end,
    execute_in_game_thread = function(callback) callback() end,
    on_result = function(control, handled)
        table.insert(results, { control = control, handled = handled })
    end
})

equal(poller:start(), true, "poller started")
equal(poller.active, true, "poller active")
equal(type(scheduled), "function", "poll loop scheduled")
equal(scheduled(), false, "press frame keeps loop active")
equal(#routed, 0, "press does not route before release")
equal(scheduled(), false, "release frame keeps loop active")
equal(routed[1], "ClanTabButton", "release over button routed")
equal(results[1].handled, true, "route result reported")

poller:stop()
equal(scheduled(), true, "stopped poller ends loop")
equal(poller.active, false, "poller inactive")

local unavailable, unavailable_error = UMGButtonPoller.new():start()
equal(unavailable, false, "missing router rejected")
equal(unavailable_error, "UI etkilesim router'i hazir degil.",
    "missing router error")

print("PALTR_UI_UMG_BUTTON_POLLER_TEST_OK")
