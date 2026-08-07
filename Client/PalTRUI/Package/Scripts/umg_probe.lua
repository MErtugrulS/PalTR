local Probe = {}

local function full_name(object)
    if object == nil then return "" end
    local ok, result = pcall(function() return object:GetFullName() end)
    if ok and result ~= nil then return tostring(result) end
    return ""
end

local function collect(class_name, limit)
    local result = {}

    if type(FindAllOf) ~= "function" then
        return result
    end

    local ok, objects = pcall(FindAllOf, class_name)
    if not ok or objects == nil then
        return result
    end

    for _, object in ipairs(objects) do
        local name = full_name(object)
        if name ~= "" then
            table.insert(result, name)
            if #result >= limit then break end
        end
    end

    table.sort(result)
    return result
end

local function dump_group(label, values)
    print(string.format("[PalTRUI][UMG] %s | count=%d\n", label, #values))
    for _, value in ipairs(values) do
        print(string.format("[PalTRUI][UMG] %s\n", value))
    end
end

function Probe.scan()
    local result = {
        widgets = collect("UserWidget", 120),
        widget_classes = collect("WidgetBlueprintGeneratedClass", 120),
        huds = collect("HUD", 40)
    }

    dump_group("USER_WIDGET", result.widgets)
    dump_group("WIDGET_CLASS", result.widget_classes)
    dump_group("HUD", result.huds)

    print("[PalTRUI][UMG] PALTR_UI_UMG_PROBE_OK\n")
    return result
end

return Probe
