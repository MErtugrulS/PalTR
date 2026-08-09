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

local deferred = nil
local execute_count = 0
local resume_ticks = nil
local deferred_loop = nil
local guarded = UMGButtonPoller.new({
    widget_provider = function() return {} end,
    control_names = {},
    sampler = { sample = function() return true, {} end },
    router = { handle = function() return true, { open = true } end },
    schedule_loop = function(_, callback) deferred_loop = callback end,
    execute_in_game_thread = function(callback)
        execute_count = execute_count + 1
        deferred = callback
    end,
    on_resume = function(delayed_ticks) resume_ticks = delayed_ticks end,
    resume_after_delayed_ticks = 3
})

equal(guarded:start(), true, "guarded poller started")
equal(deferred_loop(), false, "first game-thread callback queued")
equal(execute_count, 1, "one game-thread callback queued")
for _ = 1, 5 do equal(deferred_loop(), false, "backlog tick skipped") end
equal(execute_count, 1, "game-thread backlog is bounded")
deferred()
equal(resume_ticks, 5, "delayed game thread reports resume")
equal(guarded.game_thread_pending, false, "pending state cleared")
equal(deferred_loop(), false, "polling continues after resume")
equal(execute_count, 2, "next callback queued after resume")
guarded:stop()

local unavailable, unavailable_error = UMGButtonPoller.new():start()
equal(unavailable, false, "missing router rejected")
equal(unavailable_error, "UI etkilesim router'i hazir degil.",
    "missing router error")

print("PALTR_UI_UMG_BUTTON_POLLER_TEST_OK")
