local Poller = require("umg_button_hook_poller")

local function equal(actual, expected, label)
    if actual ~= expected then
        error(string.format("%s | expected=%s actual=%s",
            label, tostring(expected), tostring(actual)))
    end
end

local hook_callback = nil
local frames = {
    { pressed = true, hovered = true },
    { pressed = false, hovered = true },
    { pressed = false, hovered = false }
}
local frame = 0
local routed = {}
local resumed = 0
local now = 10
local poll_now = 0
local callback_registry = {}
local poller = Poller.new({
    widget_provider = function() return {} end,
    control_names = { "ClanTabButton" },
    sampler = {
        sample = function()
            frame = frame + 1
            local state = frames[frame]
            return true, {{
                control = "ClanTabButton",
                pressed = state.pressed,
                hovered_available = true,
                hovered = state.hovered
            }}
        end
    },
    router = {
        handle = function(_, control)
            table.insert(routed, control)
            return true, { open = true }, true
        end
    },
    register_hook = function(path, callback)
        equal(path, Poller.HOOK_PATH, "game-thread HUD tick hook")
        hook_callback = callback
        return "pre", "post"
    end,
    now = function() return now end,
    poll_now = function()
        poll_now = poll_now + 0.05
        return poll_now
    end,
    callback_registry = callback_registry,
    callback_key = "test_button_tick",
    on_resume = function() resumed = resumed + 1 end
})

equal(poller:start(), true, "hook poller started")
equal(type(hook_callback), "function", "hook callback retained")
hook_callback()
equal(#routed, 0, "press waits for release")
hook_callback()
equal(routed[1], "ClanTabButton", "release routed on game thread")
now = 12
hook_callback()
equal(resumed, 1, "tick gap refreshes input")
poller:stop()
equal(poller.active, false, "poller stopped without unregistering hook")
equal(poller.registered, true, "stable hook remains registered")
equal(callback_registry.test_button_tick, hook_callback,
    "hook callback retained outside poller instance")
local sampled_before = frame
hook_callback()
equal(frame, sampled_before, "inactive hook does not touch UMG")

local toggle_frame = 0
local toggle_routed = {}
local toggle_callback = nil
local toggle_poller = Poller.new({
    widget_provider = function() return {} end,
    control_names = { "DiplomacyTabButton" },
    sampler = {
        sample = function()
            toggle_frame = toggle_frame + 1
            return true, {{
                control = "DiplomacyTabButton",
                pressed = false,
                checked_available = true,
                checked = toggle_frame >= 2,
                hovered_available = true,
                hovered = toggle_frame >= 2
            }}
        end
    },
    router = {
        handle = function(_, control)
            table.insert(toggle_routed, control)
            return true, { open = true }, true
        end
    },
    register_hook = function(_, callback)
        toggle_callback = callback
        return "toggle-pre", "toggle-post"
    end,
    now = function() return 20 end,
    poll_now = function() return toggle_frame + 1 end,
    poll_interval_seconds = 0
})
equal(toggle_poller:start(), true, "toggle hook poller started")
toggle_callback()
equal(#toggle_routed, 0, "initial checkbox state is not routed")
toggle_callback()
equal(toggle_routed[1], "DiplomacyTabButton",
    "checkbox change routes through runtime hook poller")
toggle_poller:stop()

print("PALTR_UI_UMG_BUTTON_HOOK_POLLER_TEST_OK")
