local States = require("PalTR.domain.conquest_states")

local Rules = {}

local function finite_number(value)
    value = tonumber(value)
    if value == nil or value ~= value
        or value == math.huge or value == -math.huge then
        return nil
    end
    return value
end

local function point(value)
    value = value or {}
    local x = finite_number(value.x)
    local y = finite_number(value.y)
    if x == nil or y == nil then return nil end
    return { x = x, y = y }
end

function Rules.radius_for(node, config)
    node = node or {}
    config = config or {}

    local override = finite_number(node.territory_radius_meters)
    if override ~= nil and override ~= 0 then
        return override > 0 and override or 0
    end

    local key = "territory_default_outpost_radius_meters"
    if node.node_type == States.NODE_TYPE.CAPITAL then
        key = "territory_default_capital_radius_meters"
    elseif node.node_type ~= States.NODE_TYPE.OUTPOST then
        return 0
    end

    local default = finite_number(config[key])
    return default ~= nil and default > 0 and default or 0
end

function Rules.horizontal_distance(first, second)
    first = point(first)
    second = point(second)
    if first == nil or second == nil then return nil end

    local dx = first.x - second.x
    local dy = first.y - second.y
    return math.sqrt(dx * dx + dy * dy)
end

local function eligible(node, config)
    return node ~= nil
        and tostring(node.node_id or "") ~= ""
        and tostring(node.current_controller or "") ~= ""
        and Rules.radius_for(node, config) > 0
end

function Rules.resolve(location, nodes, config, current_node_id)
    config = config or {}
    if point(location) == nil then return nil end

    local current = nodes and nodes[tostring(current_node_id or "")]
    if eligible(current, config) then
        local distance = Rules.horizontal_distance(location, current)
        local hysteresis = finite_number(
            config.territory_exit_hysteresis_meters
        ) or 0
        hysteresis = math.max(0, hysteresis)
        local radius = Rules.radius_for(current, config)
        if distance ~= nil and distance <= radius + hysteresis then
            return current, radius, distance
        end
    end

    local selected, selected_radius, selected_distance = nil, nil, nil
    local selected_ratio = math.huge

    for _, node in pairs(nodes or {}) do
        if eligible(node, config) then
            local radius = Rules.radius_for(node, config)
            local distance = Rules.horizontal_distance(location, node)
            local ratio = distance and distance / radius or math.huge
            local node_id = tostring(node.node_id)
            local selected_id = selected and tostring(selected.node_id) or ""

            if ratio <= 1 and (
                ratio < selected_ratio
                or (ratio == selected_ratio and node_id < selected_id)
            ) then
                selected = node
                selected_radius = radius
                selected_distance = distance
                selected_ratio = ratio
            end
        end
    end

    return selected, selected_radius, selected_distance
end

return Rules
