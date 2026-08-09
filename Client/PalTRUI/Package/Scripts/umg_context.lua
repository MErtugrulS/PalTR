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

local function first_of(class_name, find_all)
    if type(find_all) ~= "function" then return nil end
    local ok, objects = pcall(find_all, class_name)
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

function UMGContext.discover(api)
    api = type(api) == "table" and api or {}
    local find_all = type(api.find_all) == "function"
        and api.find_all or FindAllOf
    local hud = first_of("PalHUDInGame", find_all)
    local service = first_of("PalHUDService", find_all)
    local layout = read_property(hud, "HUDLayout")
    local player_controller = read_property(hud, "PlayerOwner")

    return {
        ready = hud ~= nil
            and service ~= nil
            and layout ~= nil
            and player_controller ~= nil,
        hud = hud,
        service = service,
        layout = layout,
        player_controller = player_controller,
        names = {
            hud = full_name(hud),
            service = full_name(service),
            layout = full_name(layout),
            player_controller = full_name(player_controller)
        }
    }
end

return UMGContext
