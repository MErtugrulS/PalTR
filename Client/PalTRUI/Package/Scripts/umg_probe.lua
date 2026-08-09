local Probe = {}
local UMGContext = require("umg_context")
local UMGAssetLoader = require("umg_asset_loader")

local function unwrap(value)
    if value == nil then return nil end
    local ok, result = pcall(function() return value:get() end)
    if ok and result ~= nil then return result end
    return value
end

local function full_name(object)
    object = unwrap(object)
    if object == nil then return "" end
    local ok, result = pcall(function() return object:GetFullName() end)
    if ok and result ~= nil then return tostring(result) end
    return ""
end

local function collect_objects(class_name, limit)
    local result = {}

    if type(FindAllOf) ~= "function" then
        return result
    end

    local ok, objects = pcall(FindAllOf, class_name)
    if not ok or objects == nil then
        return result
    end

    for _, object in ipairs(objects) do
        table.insert(result, object)
        if #result >= limit then break end
    end

    return result
end

local function collect(class_name, limit)
    local result = {}

    for _, object in ipairs(collect_objects(class_name, limit)) do
        local name = full_name(object)
        if name ~= "" then table.insert(result, name) end
    end

    table.sort(result)
    return result
end

local function read_property(object, property_name)
    if object == nil then return nil end

    local direct_ok, direct_value = pcall(function()
        return object[property_name]
    end)
    if direct_ok and direct_value ~= nil then return unwrap(direct_value) end

    local getter_ok, getter_value = pcall(function()
        return object:GetPropertyValue(property_name)
    end)
    if getter_ok then return unwrap(getter_value) end
    return nil
end

local function dump_group(label, values)
    print(string.format("[PalTRUI][UMG] %s | count=%d\n", label, #values))
    for _, value in ipairs(values) do
        print(string.format("[PalTRUI][UMG] %s\n", value))
    end
end

local function dump_hud_details()
    for _, hud in ipairs(collect_objects("PalHUDInGame", 10)) do
        print(string.format(
            "[PalTRUI][UMG] PAL_HUD_DETAIL | hud=%s | layout=%s | controller=%s\n",
            full_name(hud),
            full_name(read_property(hud, "HUDLayout")),
            full_name(read_property(hud, "PlayerOwner"))
        ))
    end
end

function Probe.function_names(panel_class)
    local names = {}
    if panel_class == nil then return names, "Panel sinifi bulunamadi." end

    local iterated, iterate_error = pcall(function()
        panel_class:ForEachFunction(function(ufunction)
            local read, function_name = pcall(function()
                return ufunction:GetFName():ToString()
            end)
            if read and function_name ~= nil then
                table.insert(names, tostring(function_name))
            end
        end)
    end)
    if not iterated then
        return names,
            "Panel UFunction listesi okunamadi: " .. tostring(iterate_error)
    end
    table.sort(names)
    return names
end

local function collect_panel_functions()
    local loaded, panel_class, load_error =
        UMGAssetLoader.new():load_panel_class()
    if loaded ~= true then return {}, load_error end
    return Probe.function_names(panel_class)
end

function Probe.scan()
    local context = UMGContext.discover()
    local panel_functions, panel_function_error =
        collect_panel_functions()
    local result = {
        widgets = collect("UserWidget", 120),
        widget_classes = collect("WidgetBlueprintGeneratedClass", 120),
        huds = collect("HUD", 40),
        pal_huds = collect("PalHUDInGame", 10),
        hud_services = collect("PalHUDService", 20),
        hud_layouts = collect("PalUIHUDLayoutBase", 20),
        pal_widgets = collect("PalUserWidget", 120),
        stackable_widgets = collect("PalUserWidgetStackableUI", 120),
        context = context,
        panel_functions = panel_functions,
        panel_function_error = panel_function_error
    }

    dump_group("USER_WIDGET", result.widgets)
    dump_group("WIDGET_CLASS", result.widget_classes)
    dump_group("HUD", result.huds)
    dump_group("PAL_HUD", result.pal_huds)
    dump_group("HUD_SERVICE", result.hud_services)
    dump_group("HUD_LAYOUT", result.hud_layouts)
    dump_group("PAL_WIDGET", result.pal_widgets)
    dump_group("STACKABLE_WIDGET", result.stackable_widgets)
    dump_group("PALTR_PANEL_FUNCTION", result.panel_functions)
    if result.panel_function_error ~= nil then
        print(string.format(
            "[PalTRUI][UMG] PALTR_PANEL_FUNCTION_ERROR | %s\n",
            tostring(result.panel_function_error)
        ))
    end
    dump_hud_details()
    print(string.format(
        "[PalTRUI][UMG] PAL_CONTEXT | ready=%s | hud=%s | service=%s | layout=%s | controller=%s\n",
        tostring(context.ready),
        context.names.hud,
        context.names.service,
        context.names.layout,
        context.names.player_controller
    ))

    print("[PalTRUI][UMG] PALTR_UI_UMG_PROBE_OK\n")
    return result
end

return Probe
