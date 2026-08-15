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
    for _, spec in ipairs(control_names or {}) do
        local widget_name = spec
        local routed_name = spec
        if type(spec) == "table" then
            widget_name = spec.widget or spec.name or spec.control
            routed_name = spec.control or widget_name
        end
        widget_name = tostring(widget_name or "")
        routed_name = tostring(routed_name or widget_name)
        local control = controls[widget_name]
        if control == nil then
            table.insert(result, {
                control = routed_name,
                widget = widget_name,
                available = false,
                pressed = false,
                hovered_available = false,
                hovered = false
            })
        else
            local sampled, pressed = pcall(function()
                return control:IsPressed()
            end)
            local hover_sampled, hovered = pcall(function()
                return control:IsHovered()
            end)
            table.insert(result, {
                control = routed_name,
                widget = widget_name,
                available = sampled,
                pressed = sampled and pressed == true,
                hovered_available = hover_sampled,
                hovered = hover_sampled and hovered == true
            })
        end
    end
    return true, result
end

return UMGButtonStateProbe
