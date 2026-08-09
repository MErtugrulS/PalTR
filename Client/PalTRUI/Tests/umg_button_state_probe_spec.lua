local UMGButtonStateProbe = require("umg_button_state_probe")

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

local function widget(name, children, pressed)
    return {
        GetFName = function()
            return { ToString = function() return name end }
        end,
        GetChildrenCount = function() return #(children or {}) end,
        GetChildAt = function(_, index) return children[index + 1] end,
        IsPressed = function() return pressed == true end
        ,IsHovered = function() return pressed == true end
    }
end

local button = widget("ClanTabButton", {}, true)
local root = widget("Root", { button }, false)
local sampled, states, sample_error = UMGButtonStateProbe.sample({
    WidgetTree = { RootWidget = root }
}, { "ClanTabButton", "MissingButton" })
equal(sampled, true, "button states sampled")
equal(sample_error, nil, "button states have no error")
equal(states[1].available, true, "reflected IsPressed available")
equal(states[1].pressed, true, "pressed state returned")
equal(states[1].hovered_available, true, "reflected IsHovered available")
equal(states[1].hovered, true, "hovered state returned")
equal(states[2].available, false, "missing button unavailable")

local closed, _, closed_error = UMGButtonStateProbe.sample()
equal(closed, false, "closed panel rejected")
equal(closed_error, "PalTR paneli acik degil.", "closed panel error")

print("PALTR_UI_UMG_BUTTON_STATE_PROBE_TEST_OK")
