local ApplicationFocusGuard = require("application_focus_guard")

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

local callback = nil
local lost = 0
local gained = 0
local registered, hook_ids = ApplicationFocusGuard.register({
    register_hook = function(path, handler)
        equal(path, ApplicationFocusGuard.HOOK_PATH, "verified focus hook path")
        callback = handler
        return "pre", "post"
    end,
    on_focus_lost = function() lost = lost + 1 end,
    on_focus_gained = function() gained = gained + 1 end
})
equal(registered, true, "focus guard registered")
equal(hook_ids.pre_id, "pre", "pre hook retained")
equal(type(callback), "function", "focus callback retained")

callback(nil, { get = function() return false end })
equal(lost, 1, "focus loss handled")
equal(gained, 0, "focus loss does not gain")
callback(nil, { get = function() return true end })
equal(gained, 1, "focus gain handled")
callback(nil, { get = function() return nil end })
equal(lost, 1, "unknown focus ignored")
equal(gained, 1, "unknown focus does not gain")

print("PALTR_UI_APPLICATION_FOCUS_GUARD_TEST_OK")
