local UE = {}

function UE.safe(fn)
    local ok, result = pcall(fn)
    if ok then return true, result end
    return false, result
end

function UE.unwrap(value)
    if value == nil then return nil end
    local ok, result = UE.safe(function() return value:get() end)
    if ok and result ~= nil then return result end
    return value
end

function UE.valid(object)
    if object == nil then return false end
    local ok, result = UE.safe(function() return object:IsValid() end)
    return ok and result == true
end

function UE.full_name(object)
    if not UE.valid(object) then return "<gecersiz>" end
    local ok, result = UE.safe(function() return object:GetFullName() end)
    if ok then return tostring(result) end
    return "<adsiz>"
end

function UE.read(object, field)
    if object == nil then return nil end

    if UE.valid(object) then
        local ok, result = UE.safe(function()
            return object:GetPropertyValue(field)
        end)
        if ok then return result end
    end

    local ok, result = UE.safe(function() return object[field] end)
    if ok then return UE.unwrap(result) end
    return nil
end

function UE.text(value)
    value = UE.unwrap(value)
    if value == nil then return "" end

    local kind = type(value)
    if kind == "string" or kind == "number" or kind == "boolean" then
        return tostring(value)
    end

    local ok, result = UE.safe(function() return value:ToString() end)
    if ok and result ~= nil and tostring(result) ~= "" then
        return tostring(result)
    end

    if UE.valid(value) then return UE.full_name(value) end
    return ""
end

function UE.guid(value)
    value = UE.unwrap(value)
    if value == nil then return "" end

    local parts = {}
    for _, field in ipairs({"A", "B", "C", "D"}) do
        local direct = UE.read(value, field)
        table.insert(parts, tonumber(UE.unwrap(direct)))
    end

    if parts[1] and parts[2] and parts[3] and parts[4] then
        return string.format(
            "%08X%08X%08X%08X",
            parts[1], parts[2], parts[3], parts[4]
        )
    end
    return UE.text(value)
end

function UE.call(object, method_name, ...)
    if not UE.valid(object) then return false, nil end
    local args = {...}
    return UE.safe(function()
        local method = object[method_name]
        if method == nil then error("metot-yok:" .. method_name) end
        return method(object, table.unpack(args))
    end)
end

function UE.find_all(class_name)
    local ok, objects = pcall(FindAllOf, class_name)
    if not ok or objects == nil then return {} end
    return objects
end

return UE
