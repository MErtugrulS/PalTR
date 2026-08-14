local Model = {}

Model.DEFAULT_MAX_SEGMENTS = 512
Model.DEFAULT_MAX_NODES = 64

Model.COLORS = {
    OWN = { r = 0.91, g = 0.69, b = 0.27, a = 0.96 },
    ALLIANCE = { r = 0.20, g = 0.80, b = 0.88, a = 0.94 },
    WAR = { r = 0.88, g = 0.25, b = 0.25, a = 0.98 },
    PENDING = { r = 0.95, g = 0.55, b = 0.16, a = 0.95 },
    NEUTRAL = { r = 0.58, g = 0.65, b = 0.72, a = 0.86 }
}

local function text(value)
    return tostring(value or "")
end

local function table_or_empty(value)
    return type(value) == "table" and value or {}
end

local function relation_kind(state)
    state = text(state):upper()
    if state == "WAR" then return "WAR" end
    if state == "ALLIANCE" then return "ALLIANCE" end
    if state:sub(-8) == "_PENDING" then return "PENDING" end
    return "NEUTRAL"
end

local function relations(snapshot)
    local result = {}
    for _, relation in ipairs(table_or_empty(snapshot.relations)) do
        relation = table_or_empty(relation)
        result[text(relation.guild_key)] = relation_kind(relation.state)
    end
    return result
end

local function status_for(guild_key, own_guild, relation_map)
    if text(guild_key) ~= "" and text(guild_key) == text(own_guild) then
        return "OWN"
    end
    return relation_map[text(guild_key)] or "NEUTRAL"
end

local function append_boundary_segments(result, boundary, status)
    local points = table_or_empty(boundary.points)
    for index, first in ipairs(points) do
        local second = points[index % #points + 1]
        if type(first) == "table" and type(second) == "table"
            and tonumber(first.x) ~= nil and tonumber(first.y) ~= nil
            and tonumber(second.x) ~= nil and tonumber(second.y) ~= nil then
            table.insert(result, {
                boundary_id = text(boundary.boundary_id),
                controller_guild = text(boundary.controller_guild),
                controller_name = text(boundary.controller_name),
                status = status,
                color = Model.COLORS[status],
                first = {
                    x = tonumber(first.x) * 100,
                    y = tonumber(first.y) * 100,
                    z = 0
                },
                second = {
                    x = tonumber(second.x) * 100,
                    y = tonumber(second.y) * 100,
                    z = 0
                }
            })
        end
    end
end

local function select_evenly(values, maximum)
    if #values <= maximum then return values end
    local result = {}
    for index = 0, maximum - 1 do
        local source_index = math.floor(index * #values / maximum) + 1
        table.insert(result, values[source_index])
    end
    return result
end

function Model.build(snapshot, limits)
    snapshot = table_or_empty(snapshot)
    limits = table_or_empty(limits)
    local own_guild = text(table_or_empty(snapshot.player).guild_key)
    local relation_map = relations(snapshot)
    local territories = table_or_empty(snapshot.territories)
    local segments = {}

    for _, boundary in ipairs(table_or_empty(territories.boundaries)) do
        boundary = table_or_empty(boundary)
        append_boundary_segments(
            segments,
            boundary,
            status_for(
                boundary.controller_guild,
                own_guild,
                relation_map
            )
        )
    end
    segments = select_evenly(
        segments,
        tonumber(limits.max_segments) or Model.DEFAULT_MAX_SEGMENTS
    )

    local nodes = {}
    for _, node in ipairs(table_or_empty(territories.nodes)) do
        node = table_or_empty(node)
        if #nodes >= (tonumber(limits.max_nodes) or Model.DEFAULT_MAX_NODES) then
            break
        end
        local x, y, z = tonumber(node.x), tonumber(node.y), tonumber(node.z)
        if x ~= nil and y ~= nil and z ~= nil then
            local status = status_for(
                node.controller_guild,
                own_guild,
                relation_map
            )
            table.insert(nodes, {
                node_id = text(node.node_id),
                display_name = text(node.display_name),
                node_type = text(node.node_type),
                controller_guild = text(node.controller_guild),
                controller_name = text(node.controller_name),
                state = text(node.state),
                flag_state = text(node.flag_state),
                status = status,
                color = Model.COLORS[status],
                world = { x = x * 100, y = y * 100, z = z * 100 },
                size = text(node.node_type) == "CAPITAL" and 18 or 11,
                angle = text(node.node_type) == "CAPITAL" and 45 or 0
            })
        end
    end

    return {
        own_guild = own_guild,
        segments = segments,
        nodes = nodes,
        segment_count = #segments,
        node_count = #nodes
    }
end

return Model
