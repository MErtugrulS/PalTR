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

local function collect(widget, controls, depth, visited)
    widget = unwrap(widget)
    if widget == nil or depth > 64 then return end
    visited = visited or {}
    if visited[widget] then return end
    visited[widget] = true

    local name = widget_name(widget)
    if name ~= "" then controls[name] = widget end

    local tree_read, tree = pcall(function() return widget.WidgetTree end)
    local root_read, nested_root = pcall(function()
        return tree_read and unwrap(tree) and unwrap(tree).RootWidget or nil
    end)
    if root_read and nested_root ~= nil and nested_root ~= widget then
        collect(nested_root, controls, depth + 1, visited)
    end

    local counted, count = pcall(function()
        return widget:GetChildrenCount()
    end)
    if not counted or type(count) ~= "number" then return end
    for index = 0, count - 1 do
        local read, child = pcall(function()
            return widget:GetChildAt(index)
        end)
        if read then collect(child, controls, depth + 1, visited) end
    end
end

local function widget_candidates(spec)
    if type(spec) ~= "table" then return { tostring(spec or "") } end
    local candidates = spec.widgets or spec.widget or spec.name or spec.control
    if type(candidates) ~= "table" then candidates = { candidates } end
    local result = {}
    for _, candidate in ipairs(candidates) do
        candidate = tostring(candidate or "")
        if candidate ~= "" then table.insert(result, candidate) end
    end
    return result
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
        local candidates = widget_candidates(spec)
        local routed_name = type(spec) == "table" and spec.control or spec
        routed_name = tostring(routed_name or candidates[1] or "")
        local selected_name, control = candidates[1] or "", nil
        for _, candidate in ipairs(candidates) do
            if controls[candidate] ~= nil then
                selected_name, control = candidate, controls[candidate]
                break
            end
        end
        if control == nil then
            table.insert(result, {
                control = routed_name,
                widget = selected_name,
                available = false,
                pressed = false,
                checked_available = false,
                checked = false,
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
            local checked_sampled, checked = pcall(function()
                return control:IsChecked()
            end)
            table.insert(result, {
                control = routed_name,
                widget = selected_name,
                available = sampled or checked_sampled,
                pressed = sampled and pressed == true,
                checked_available = checked_sampled,
                checked = checked_sampled and checked == true,
                hovered_available = hover_sampled,
                hovered = hover_sampled and hovered == true
            })
        end
    end
    return true, result
end

return UMGButtonStateProbe
