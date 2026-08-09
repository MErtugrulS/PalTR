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
local sampled_before = frame
hook_callback()
equal(frame, sampled_before, "inactive hook does not touch UMG")

print("PALTR_UI_UMG_BUTTON_HOOK_POLLER_TEST_OK")
