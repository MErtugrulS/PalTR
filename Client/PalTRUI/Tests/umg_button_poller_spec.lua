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
equal(poller.loop_callback, scheduled, "poll loop callback retained")
equal(scheduled(), false, "press frame keeps loop active")
equal(#routed, 0, "press does not route before release")
equal(scheduled(), false, "release frame keeps loop active")
equal(routed[1], "ClanTabButton", "release over button routed")
equal(results[1].handled, true, "route result reported")

poller:stop()
equal(scheduled(), true, "stopped poller ends loop")
equal(poller.active, false, "poller inactive")
equal(poller.loop_callback, nil, "stopped loop callback released")
equal(poller.game_thread_callback, nil,
    "stopped game-thread callback released")

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
equal(guarded.game_thread_callback, deferred,
    "pending game-thread callback retained")
for _ = 1, 5 do equal(deferred_loop(), false, "backlog tick skipped") end
equal(execute_count, 1, "game-thread backlog is bounded")
deferred()
equal(resume_ticks, 5, "delayed game thread reports resume")
equal(guarded.game_thread_pending, false, "pending state cleared")
equal(guarded.game_thread_callback, nil,
    "completed game-thread callback released")
equal(deferred_loop(), false, "polling continues after resume")
equal(execute_count, 2, "next callback queued after resume")
guarded:stop()

local stale_callback = nil
local current_loop = nil
local stale_polls = 0
local generation_guard = UMGButtonPoller.new({
    widget_provider = function() return {} end,
    control_names = {},
    sampler = {
        sample = function()
            stale_polls = stale_polls + 1
            return true, {}
        end
    },
    router = { handle = function() return true, { open = true } end },
    schedule_loop = function(_, callback) current_loop = callback end,
    execute_in_game_thread = function(callback) stale_callback = callback end
})
generation_guard:start()
local first_loop = current_loop
first_loop()
generation_guard:stop()
generation_guard:start()
stale_callback()
equal(stale_polls, 0, "stale game-thread callback ignored after restart")
equal(first_loop(), true, "stale loop generation ends")
generation_guard:stop()

local unavailable, unavailable_error = UMGButtonPoller.new():start()
equal(unavailable, false, "missing router rejected")
equal(unavailable_error, "UI etkilesim router'i hazir degil.",
    "missing router error")

local aliased_routes = {}
local aliased_frames = {
    { pressed = true, hovered = true },
    { pressed = false, hovered = true }
}
local aliased_index = 0
local AliasedStateProbe = require("umg_button_state_probe")
local aliased_button = {
    IsPressed = function()
        return aliased_frames[aliased_index].pressed
    end,
    IsHovered = function()
        return aliased_frames[aliased_index].hovered
    end,
    GetFName = function()
        return { ToString = function() return "C_DiplomacyButton" end }
    end,
    GetChildrenCount = function() return 0 end
}
local aliased_root = {
    GetFName = function()
        return { ToString = function() return "Root" end }
    end,
    GetChildrenCount = function() return 1 end,
    GetChildAt = function() return aliased_button end
}
local aliased_panel = { WidgetTree = { RootWidget = aliased_root } }
local aliased_poller = UMGButtonPoller.new({
    widget_provider = function() return aliased_panel end,
    control_names = {
        { widget = "C_DiplomacyButton", control = "DiplomacyTabButton" }
    },
    sampler = {
        sample = function(panel, controls)
            aliased_index = aliased_index + 1
            return AliasedStateProbe.sample(panel, controls)
        end
    },
    router = {
        handle = function(_, control)
            table.insert(aliased_routes, control)
            return true, { open = true }, true
        end
    },
    schedule_loop = function() end,
    execute_in_game_thread = function(callback) callback() end
})
equal(aliased_poller:start(), true, "aliased poller started")
equal(aliased_poller:poll_once(), true, "aliased press sampled")
equal(aliased_poller:poll_once(), true, "aliased release sampled")
equal(aliased_routes[1], "DiplomacyTabButton",
    "blueprint widget aliases to logical diplomacy control")
aliased_poller:stop()

print("PALTR_UI_UMG_BUTTON_POLLER_TEST_OK")
