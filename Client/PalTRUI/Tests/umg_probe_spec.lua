local UMGProbe = require("umg_probe")

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

local function reflected_function(name)
    return {
        GetFName = function()
            return { ToString = function() return name end }
        end
    }
end

local panel_class = {
    ForEachFunction = function(_, callback)
        callback(reflected_function("BndEvt__CloseButton_K2Node_ComponentBoundEvent"))
        callback(reflected_function("Construct"))
    end
}

local names, names_error = UMGProbe.function_names(panel_class)
equal(names_error, nil, "panel functions have no error")
equal(#names, 2, "panel function count")
equal(names[1], "BndEvt__CloseButton_K2Node_ComponentBoundEvent",
    "panel functions sorted")
equal(names[2], "Construct", "second panel function")

local missing, missing_error = UMGProbe.function_names()
equal(#missing, 0, "missing panel has no functions")
equal(missing_error, "Panel sinifi bulunamadi.", "missing panel error")

print("PALTR_UI_UMG_PROBE_TEST_OK")
