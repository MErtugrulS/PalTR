local UMGContext = {}

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

local function first_of(class_name)
    if type(FindAllOf) ~= "function" then return nil end
    local ok, objects = pcall(FindAllOf, class_name)
    if not ok or objects == nil then return nil end
    for _, object in ipairs(objects) do
        return unwrap(object)
    end
    return nil
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

function UMGContext.discover()
    local hud = first_of("PalHUDInGame")
    local service = first_of("PalHUDService")
    local layout = read_property(hud, "HUDLayout")

    return {
        ready = hud ~= nil and service ~= nil and layout ~= nil,
        hud = hud,
        service = service,
        layout = layout,
        names = {
            hud = full_name(hud),
            service = full_name(service),
            layout = full_name(layout)
        }
    }
end

return UMGContext
