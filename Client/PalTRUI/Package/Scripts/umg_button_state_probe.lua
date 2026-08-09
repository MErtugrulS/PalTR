local UMGButtonStateProbe = {}

local function unwrap(value)
    if value == nil then return nil end
    local ok, result = pcall(function() return value:get() end)
    if ok and result ~= nil then return result end
    return value
end

local function widget_name(widget)
    widget = unwrap(widget)
    if widget == nil then return "" end
    local read, name = pcall(function()
        return widget:GetFName():ToString()
    end)
    return read and tostring(name or "") or ""
end

local function collect(widget, controls, depth)
    widget = unwrap(widget)
    if widget == nil or depth > 64 then return end

    local name = widget_name(widget)
    if name ~= "" then controls[name] = widget end

    local counted, count = pcall(function()
        return widget:GetChildrenCount()
    end)
    if not counted or type(count) ~= "number" then return end
    for index = 0, count - 1 do
        local read, child = pcall(function()
            return widget:GetChildAt(index)
        end)
        if read then collect(child, controls, depth + 1) end
    end
end

function UMGButtonStateProbe.sample(panel, control_names)
    if panel == nil then return false, {}, "PalTR paneli acik degil." end

    local root = unwrap(panel.WidgetTree)
    root = root and unwrap(root.RootWidget) or nil
    if root == nil then
        return false, {}, "PalTR panel widget agaci bulunamadi."
    end

    local controls = {}
    collect(root, controls, 0)
    local result = {}
    for _, name in ipairs(control_names or {}) do
        local control = controls[name]
        if control == nil then
            table.insert(result, {
                control = name,
                available = false,
                pressed = false
            })
        else
            local sampled, pressed = pcall(function()
                return control:IsPressed()
            end)
            table.insert(result, {
                control = name,
                available = sampled,
                pressed = sampled and pressed == true
            })
        end
    end
    return true, result
end

return UMGButtonStateProbe
