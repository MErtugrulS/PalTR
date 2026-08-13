local States = require("PalTR.domain.conquest_states")
local Geometry = require("PalTR.domain.territory_geometry")

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

function Rules.resolve(location, nodes, config, current_node_id, atlas)
    config = config or {}
    if point(location) == nil then return nil end

    local current = nodes and nodes[tostring(current_node_id or "")]
    if eligible(current, config) then
        local hysteresis = finite_number(
            config.territory_exit_hysteresis_meters
        ) or 0
        hysteresis = math.max(0, hysteresis)
        local radius = Rules.radius_for(current, config)
        local measure = Geometry.node_measure(
            location,
            current,
            radius,
            config,
            hysteresis
        )
        if measure ~= nil and measure.ratio <= 1 then
            return current, radius, measure.distance
        end
    end

    local guild_key = atlas and Geometry.guild_at(atlas, location) or nil
    if atlas ~= nil and guild_key == nil then return nil end
    local selected, selected_radius, measure = Geometry.best_node(
        location,
        nodes,
        config,
        Rules.radius_for,
        guild_key
    )
    if selected == nil or measure == nil then return nil end
    if atlas == nil and measure.ratio > 1 then return nil end
    return selected, selected_radius, measure.distance
end

function Rules.build_atlas(nodes, config, terrain_sampler)
    return Geometry.build_atlas(
        nodes,
        config or {},
        Rules.radius_for,
        terrain_sampler
    )
end

function Rules.organic_radius_for(node, config, angle)
    return Geometry.organic_radius(
        node,
        Rules.radius_for(node, config or {}),
        finite_number(angle) or 0,
        config or {}
    )
end

function Rules.contains(component, location)
    return Geometry.contains(component, location)
end

return Rules
