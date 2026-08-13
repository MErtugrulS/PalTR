local Geometry = {}

local TWO_PI = math.pi * 2

local function finite_number(value)
    value = tonumber(value)
    if value == nil or value ~= value
        or value == math.huge or value == -math.huge then
        return nil
    end
    return value
end

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function point(value)
    value = value or {}
    local x = finite_number(value.x)
    local y = finite_number(value.y)
    if x == nil or y == nil then return nil end
    return { x = x, y = y }
end

local function stable_hash(value)
    local hash = 17
    value = tostring(value or "")
    for index = 1, #value do
        hash = (hash * 131 + string.byte(value, index)) % 2147483647
    end
    return hash
end

local function stable_unit(seed, bucket)
    local value = stable_hash(tostring(seed) .. ":" .. tostring(bucket))
    return (value % 100003) / 50001.5 - 1
end

local function angular_noise(seed, angle, bands)
    local position = (angle % TWO_PI) / TWO_PI * bands
    local first = math.floor(position)
    local blend = position - first
    blend = blend * blend * (3 - 2 * blend)
    local second = (first + 1) % bands
    return stable_unit(seed, first) * (1 - blend)
        + stable_unit(seed, second) * blend
end

local function shape_parameters(node, config)
    local irregularity = finite_number(
        config.territory_border_irregularity
    ) or 0.06
    irregularity = clamp(irregularity, 0, 0.10)

    local seed = stable_hash(node and node.node_id)
    return {
        irregularity = irregularity,
        seed_a = seed,
        seed_b = stable_hash(tostring(seed) .. ":ridge"),
        seed_c = stable_hash(tostring(seed) .. ":detail"),
        bands_a = 4 + seed % 2,
        bands_b = 7 + math.floor(seed / 7) % 3,
        bands_c = 13 + math.floor(seed / 31) % 4
    }
end

function Geometry.organic_radius(node, base_radius, angle, config)
    base_radius = finite_number(base_radius) or 0
    if base_radius <= 0 then return 0 end

    config = config or {}
    local shape = shape_parameters(node, config)
    local noise = 0.64 * angular_noise(
        shape.seed_a,
        angle,
        shape.bands_a
    ) + 0.26 * angular_noise(
        shape.seed_b,
        angle,
        shape.bands_b
    ) + 0.10 * angular_noise(
        shape.seed_c,
        angle,
        shape.bands_c
    )
    local offset = shape.irregularity * noise

    -- The three zero-centred bands keep the configured area budget stable.
    local area_scale = math.sqrt(1 + 0.18
        * shape.irregularity * shape.irregularity)
    return base_radius * (1 + offset) / area_scale
end

function Geometry.node_measure(location, node, base_radius, config, extra)
    local node_value = node
    location = point(location)
    node = point(node_value)
    base_radius = finite_number(base_radius) or 0
    extra = math.max(0, finite_number(extra) or 0)
    if location == nil or node == nil or base_radius <= 0 then return nil end

    local dx = location.x - node.x
    local dy = location.y - node.y
    local distance = math.sqrt(dx * dx + dy * dy)
    local angle = math.atan(dy, dx)
    local boundary_radius = Geometry.organic_radius(
        node_value,
        base_radius,
        angle,
        config
    ) + extra

    return {
        distance = distance,
        boundary_radius = boundary_radius,
        ratio = boundary_radius > 0 and distance / boundary_radius or math.huge
    }
end

local function eligible_nodes(nodes, config, radius_for)
    local result = {}
    for _, node in pairs(nodes or {}) do
        local radius = radius_for(node, config)
        if node ~= nil
            and tostring(node.node_id or "") ~= ""
            and tostring(node.current_controller or "") ~= ""
            and radius > 0
            and point(node) ~= nil then
            table.insert(result, {
                node = node,
                radius = radius,
                envelope = radius * (
                    1 + clamp(
                        finite_number(config.territory_border_irregularity)
                            or 0.06,
                        0,
                        0.10
                    )
                )
            })
        end
    end
    table.sort(result, function(first, second)
        return tostring(first.node.node_id) < tostring(second.node.node_id)
    end)
    return result
end

function Geometry.best_node(location, nodes, config, radius_for, guild_key)
    local selected, selected_measure, selected_radius = nil, nil, nil
    for _, entry in ipairs(eligible_nodes(nodes, config or {}, radius_for)) do
        local node = entry.node
        if guild_key == nil
            or tostring(node.current_controller) == tostring(guild_key) then
            local measure = Geometry.node_measure(
                location,
                node,
                entry.radius,
                config or {},
                0
            )
            local selected_id = selected and tostring(selected.node_id) or ""
            local node_id = tostring(node.node_id)
            if measure ~= nil and (
                selected_measure == nil
                or measure.ratio < selected_measure.ratio
                or (measure.ratio == selected_measure.ratio
                    and node_id < selected_id)
            ) then
                selected = node
                selected_measure = measure
                selected_radius = entry.radius
            end
        end
    end
    return selected, selected_radius, selected_measure
end

local function build_clusters(entries, padding)
    local parent = {}
    for index = 1, #entries do parent[index] = index end

    local function root(index)
        while parent[index] ~= index do
            parent[index] = parent[parent[index]]
            index = parent[index]
        end
        return index
    end

    local function join(first, second)
        first = root(first)
        second = root(second)
        if first ~= second then parent[second] = first end
    end

    for first = 1, #entries do
        for second = first + 1, #entries do
            local dx = entries[first].node.x - entries[second].node.x
            local dy = entries[first].node.y - entries[second].node.y
            local reach = entries[first].envelope
                + entries[second].envelope + padding
            if dx * dx + dy * dy <= reach * reach then
                join(first, second)
            end
        end
    end

    local grouped = {}
    for index, entry in ipairs(entries) do
        local key = root(index)
        grouped[key] = grouped[key] or {}
        table.insert(grouped[key], entry)
    end

    local clusters = {}
    for _, cluster in pairs(grouped) do table.insert(clusters, cluster) end
    table.sort(clusters, function(first, second)
        return tostring(first[1].node.node_id)
            < tostring(second[1].node.node_id)
    end)
    return clusters
end

local function classify(location, entries, config)
    local selected, selected_measure = nil, nil
    for _, entry in ipairs(entries) do
        local measure = Geometry.node_measure(
            location,
            entry.node,
            entry.radius,
            config,
            0
        )
        local selected_id = selected and tostring(selected.node.node_id) or ""
        local node_id = tostring(entry.node.node_id)
        if measure ~= nil and measure.ratio <= 1 and (
            selected_measure == nil
            or measure.ratio < selected_measure.ratio
            or (measure.ratio == selected_measure.ratio
                and node_id < selected_id)
        ) then
            selected = entry
            selected_measure = measure
        end
    end
    return selected and tostring(selected.node.current_controller) or nil
end

local CASE_SEGMENTS = {
    [1] = { { "left", "bottom" } },
    [2] = { { "bottom", "right" } },
    [3] = { { "left", "right" } },
    [4] = { { "right", "top" } },
    [6] = { { "bottom", "top" } },
    [7] = { { "left", "top" } },
    [8] = { { "top", "left" } },
    [9] = { { "top", "bottom" } },
    [11] = { { "right", "top" } },
    [12] = { { "left", "right" } },
    [13] = { { "bottom", "right" } },
    [14] = { { "left", "bottom" } }
}

local function case_segments(case_value, center_inside)
    if case_value == 5 then
        if center_inside then
            return { { "bottom", "right" }, { "top", "left" } }
        end
        return { { "left", "bottom" }, { "right", "top" } }
    elseif case_value == 10 then
        if center_inside then
            return { { "left", "bottom" }, { "right", "top" } }
        end
        return { { "bottom", "right" }, { "top", "left" } }
    end
    return CASE_SEGMENTS[case_value] or {}
end

local function edge_point(edge, x, y)
    if edge == "bottom" then return 2 * x + 1, 2 * y end
    if edge == "right" then return 2 * x + 2, 2 * y + 1 end
    if edge == "top" then return 2 * x + 1, 2 * y + 2 end
    return 2 * x, 2 * y + 1
end

local function point_key(x2, y2)
    return tostring(x2) .. ":" .. tostring(y2)
end

local function edge_key(first, second)
    if first < second then return first .. "|" .. second end
    return second .. "|" .. first
end

local function add_segment(graph, coordinates, first, second)
    local first_key = point_key(first.x2, first.y2)
    local second_key = point_key(second.x2, second.y2)
    graph[first_key] = graph[first_key] or {}
    graph[second_key] = graph[second_key] or {}
    table.insert(graph[first_key], second_key)
    table.insert(graph[second_key], first_key)
    coordinates[first_key] = first
    coordinates[second_key] = second
end

local function polygon_area(points)
    local area = 0
    for index, current in ipairs(points) do
        local following = points[index % #points + 1]
        area = area + current.x * following.y - following.x * current.y
    end
    return area / 2
end

local function remove_collinear(points)
    if #points < 4 then return points end
    local result = {}
    for index, current in ipairs(points) do
        local previous = points[(index - 2) % #points + 1]
        local following = points[index % #points + 1]
        local cross = (current.x - previous.x) * (following.y - current.y)
            - (current.y - previous.y) * (following.x - current.x)
        if math.abs(cross) > 0.000001 then table.insert(result, current) end
    end
    return #result >= 3 and result or points
end

local function graph_polygons(graph, coordinates, origin_x, origin_y, step)
    local keys = {}
    for key, neighbours in pairs(graph) do
        table.sort(neighbours)
        table.insert(keys, key)
    end
    table.sort(keys)

    local used = {}
    local polygons = {}
    for _, start in ipairs(keys) do
        for _, first_next in ipairs(graph[start]) do
            if not used[edge_key(start, first_next)] then
                local path = { start }
                local previous = start
                local current = first_next
                used[edge_key(start, first_next)] = true

                while current ~= start and #path <= #keys + 1 do
                    table.insert(path, current)
                    local next_key = nil
                    for _, candidate in ipairs(graph[current] or {}) do
                        local candidate_edge = edge_key(current, candidate)
                        if candidate ~= previous and not used[candidate_edge] then
                            next_key = candidate
                            used[candidate_edge] = true
                            break
                        end
                    end
                    if next_key == nil then break end
                    previous, current = current, next_key
                end

                if current == start and #path >= 3 then
                    local points = {}
                    for _, key in ipairs(path) do
                        local coordinate = coordinates[key]
                        table.insert(points, {
                            x = origin_x + coordinate.x2 * step / 2,
                            y = origin_y + coordinate.y2 * step / 2
                        })
                    end
                    table.insert(polygons, remove_collinear(points))
                end
            end
        end
    end
    return polygons
end

local function component_bounds(points)
    local bounds = {
        min_x = math.huge,
        min_y = math.huge,
        max_x = -math.huge,
        max_y = -math.huge
    }
    for _, value in ipairs(points) do
        bounds.min_x = math.min(bounds.min_x, value.x)
        bounds.min_y = math.min(bounds.min_y, value.y)
        bounds.max_x = math.max(bounds.max_x, value.x)
        bounds.max_y = math.max(bounds.max_y, value.y)
    end
    return bounds
end

local function point_normal(points, index)
    local count = #points
    local previous = points[(index - 2) % count + 1]
    local following = points[index % count + 1]
    local dx = following.x - previous.x
    local dy = following.y - previous.y
    local length = math.sqrt(dx * dx + dy * dy)
    if length < 0.000001 then return nil end
    return { x = -dy / length, y = dx / length }
end

local function sample_terrain(sampler, x, y)
    if sampler == nil then return nil end
    local ok, value
    if type(sampler) == "function" then
        ok, value = pcall(sampler, x, y)
    elseif type(sampler.sample) == "function" then
        ok, value = pcall(sampler.sample, sampler, x, y)
    end
    if not ok or type(value) ~= "table" then return nil end
    local height = finite_number(value.height or value.z)
    if height == nil then return nil end
    return {
        height = height,
        surface = tostring(value.surface or "")
    }
end

local function feature_strength(center, first, second, probe)
    if center == nil then return nil end
    local coast = 0
    if first ~= nil and second ~= nil
        and first.surface ~= "" and second.surface ~= ""
        and first.surface ~= second.surface then
        coast = 4.5
    elseif first ~= nil and first.surface ~= ""
        and center.surface ~= "" and first.surface ~= center.surface then
        coast = 3.5
    elseif second ~= nil and second.surface ~= ""
        and center.surface ~= "" and second.surface ~= center.surface then
        coast = 3.5
    end

    if first == nil or second == nil then return coast end
    local slope = math.abs(first.height - second.height) / (2 * probe)
    local ridge = math.max(
        0,
        center.height - math.max(first.height, second.height)
    ) / probe
    local valley = math.max(
        0,
        math.min(first.height, second.height) - center.height
    ) / probe
    return coast + clamp(slope, 0, 2.5) * 0.75
        + clamp(ridge, 0, 2.5) * 1.6
        + clamp(valley, 0, 2.5) * 1.1
end

local function conform_component(component, sampler, config)
    local points = component.points or {}
    if #points < 6 or sampler == nil
        or config.territory_terrain_conform_enabled == false then
        return component
    end

    local search = clamp(finite_number(
        config.territory_terrain_search_meters
    ) or 24, 4, 60)
    local probe = clamp(finite_number(
        config.territory_terrain_probe_meters
    ) or 14, 4, 40)
    local sample_step = clamp(finite_number(
        config.territory_boundary_sample_meters
    ) or 8, 4, 50)
    local anchor_spacing = clamp(finite_number(
        config.territory_terrain_anchor_spacing_meters
    ) or 24, sample_step, 80)
    local stride = math.max(1, math.floor(anchor_spacing / sample_step + 0.5))
    local candidates = { -1, -0.5, 0, 0.5, 1 }
    local anchors, anchor_offsets = {}, {}

    for index = 1, #points, stride do
        local normal = point_normal(points, index)
        if normal ~= nil then
            local best_offset, best_score = 0, -math.huge
            for _, multiplier in ipairs(candidates) do
                local offset = search * multiplier
                local x = points[index].x + normal.x * offset
                local y = points[index].y + normal.y * offset
                local center = sample_terrain(sampler, x, y)
                local first = sample_terrain(
                    sampler,
                    x - normal.x * probe,
                    y - normal.y * probe
                )
                local second = sample_terrain(
                    sampler,
                    x + normal.x * probe,
                    y + normal.y * probe
                )
                local strength = feature_strength(center, first, second, probe)
                if strength ~= nil then
                    local score = strength - math.abs(multiplier) * 0.32
                    if score > best_score then
                        best_score = score
                        best_offset = offset
                    end
                end
            end
            table.insert(anchors, index)
            anchor_offsets[index] = best_score > 0.12 and best_offset or 0
        end
    end
    if #anchors < 2 then return component end

    local offsets = {}
    for anchor_position, first_index in ipairs(anchors) do
        local second_index = anchors[anchor_position % #anchors + 1]
        local unwrapped_second = second_index
        if unwrapped_second <= first_index then
            unwrapped_second = unwrapped_second + #points
        end
        local span = unwrapped_second - first_index
        for cursor = first_index, unwrapped_second - 1 do
            local index = (cursor - 1) % #points + 1
            local blend = span > 0 and (cursor - first_index) / span or 0
            blend = blend * blend * (3 - 2 * blend)
            offsets[index] = anchor_offsets[first_index] * (1 - blend)
                + anchor_offsets[second_index] * blend
        end
    end

    local smoothed, adjusted = {}, {}
    for index = 1, #points do
        smoothed[index] = (offsets[(index - 2) % #points + 1] or 0) * 0.20
            + (offsets[index] or 0) * 0.60
            + (offsets[index % #points + 1] or 0) * 0.20
    end
    for index, current in ipairs(points) do
        local normal = point_normal(points, index)
        if normal == nil then
            adjusted[index] = { x = current.x, y = current.y }
        else
            adjusted[index] = {
                x = current.x + normal.x * smoothed[index],
                y = current.y + normal.y * smoothed[index]
            }
        end
    end

    component.points = adjusted
    component.area = math.abs(polygon_area(adjusted))
    component.bounds = component_bounds(adjusted)
    component.terrain_conformed = true
    return component
end

local function contour_cluster(cluster, config, configured_step)
    local min_x, min_y = math.huge, math.huge
    local max_x, max_y = -math.huge, -math.huge
    for _, entry in ipairs(cluster) do
        min_x = math.min(min_x, entry.node.x - entry.envelope)
        min_y = math.min(min_y, entry.node.y - entry.envelope)
        max_x = math.max(max_x, entry.node.x + entry.envelope)
        max_y = math.max(max_y, entry.node.y + entry.envelope)
    end

    local padding = configured_step * 2
    min_x, min_y = min_x - padding, min_y - padding
    max_x, max_y = max_x + padding, max_y + padding

    local width, height = max_x - min_x, max_y - min_y
    local max_cells = math.max(1000, finite_number(
        config.territory_boundary_max_cells
    ) or 50000)
    local step = math.max(
        configured_step,
        math.sqrt(math.max(1, width * height / max_cells))
    )
    local columns = math.max(1, math.ceil(width / step))
    local rows = math.max(1, math.ceil(height / step))

    local samples = {}
    for y = 0, rows do
        samples[y] = {}
        for x = 0, columns do
            samples[y][x] = classify({
                x = min_x + x * step,
                y = min_y + y * step
            }, cluster, config)
        end
    end

    local graphs = {}
    local coordinates = {}
    for y = 0, rows - 1 do
        for x = 0, columns - 1 do
            local corners = {
                samples[y][x],
                samples[y][x + 1],
                samples[y + 1][x + 1],
                samples[y + 1][x]
            }
            local guilds = {}
            for corner_index = 1, 4 do
                local guild_key = corners[corner_index]
                if guild_key ~= nil then guilds[guild_key] = true end
            end

            for guild_key in pairs(guilds) do
                local case_value = 0
                if corners[1] == guild_key then case_value = case_value + 1 end
                if corners[2] == guild_key then case_value = case_value + 2 end
                if corners[3] == guild_key then case_value = case_value + 4 end
                if corners[4] == guild_key then case_value = case_value + 8 end

                if case_value > 0 and case_value < 15 then
                    local center_owner = classify({
                        x = min_x + (x + 0.5) * step,
                        y = min_y + (y + 0.5) * step
                    }, cluster, config)
                    graphs[guild_key] = graphs[guild_key] or {}
                    coordinates[guild_key] = coordinates[guild_key] or {}

                    for _, segment in ipairs(case_segments(
                        case_value,
                        center_owner == guild_key
                    )) do
                        local first_x2, first_y2 = edge_point(segment[1], x, y)
                        local second_x2, second_y2 = edge_point(segment[2], x, y)
                        add_segment(
                            graphs[guild_key],
                            coordinates[guild_key],
                            { x2 = first_x2, y2 = first_y2 },
                            { x2 = second_x2, y2 = second_y2 }
                        )
                    end
                end
            end
        end
    end

    local result = {}
    for guild_key, graph in pairs(graphs) do
        for _, points in ipairs(graph_polygons(
            graph,
            coordinates[guild_key],
            min_x,
            min_y,
            step
        )) do
            local area = math.abs(polygon_area(points))
            local minimum_area = math.max(0, finite_number(
                config.territory_boundary_min_component_area_square_meters
            ) or step * step)
            if area >= minimum_area then
                table.insert(result, {
                    controller_guild = guild_key,
                    points = points,
                    area = area,
                    bounds = component_bounds(points)
                })
            end
        end
    end
    return result
end

function Geometry.build_atlas(nodes, config, radius_for, terrain_sampler)
    config = config or {}
    local entries = eligible_nodes(nodes, config, radius_for)
    local configured_step = clamp(finite_number(
        config.territory_boundary_sample_meters
    ) or 12, 4, 50)
    local clusters = build_clusters(entries, configured_step * 2)
    local components = {}

    for _, cluster in ipairs(clusters) do
        for _, component in ipairs(contour_cluster(
            cluster,
            config,
            configured_step
        )) do
            table.insert(components, component)
        end
    end

    if terrain_sampler ~= nil then
        if type(terrain_sampler) == "table"
            and type(terrain_sampler.begin_pass) == "function" then
            pcall(terrain_sampler.begin_pass, terrain_sampler)
        end
        for _, component in ipairs(components) do
            conform_component(component, terrain_sampler, config)
        end
    end

    table.sort(components, function(first, second)
        if first.controller_guild ~= second.controller_guild then
            return first.controller_guild < second.controller_guild
        end
        if first.bounds.min_x ~= second.bounds.min_x then
            return first.bounds.min_x < second.bounds.min_x
        end
        return first.bounds.min_y < second.bounds.min_y
    end)

    local by_guild = {}
    local counts = {}
    for _, component in ipairs(components) do
        local guild_key = component.controller_guild
        counts[guild_key] = (counts[guild_key] or 0) + 1
        component.component_index = counts[guild_key]
        component.boundary_id = guild_key .. "::"
            .. string.format("%03d", component.component_index)
        by_guild[guild_key] = by_guild[guild_key] or {}
        table.insert(by_guild[guild_key], component)
    end

    return {
        components = components,
        components_by_guild = by_guild,
        sample_meters = configured_step
    }
end

local function point_on_segment(value, first, second, tolerance)
    local dx = second.x - first.x
    local dy = second.y - first.y
    local length_squared = dx * dx + dy * dy
    if length_squared == 0 then return false end
    local projection = ((value.x - first.x) * dx
        + (value.y - first.y) * dy) / length_squared
    projection = clamp(projection, 0, 1)
    local x = first.x + projection * dx
    local y = first.y + projection * dy
    local offset_x = value.x - x
    local offset_y = value.y - y
    return offset_x * offset_x + offset_y * offset_y
        <= tolerance * tolerance
end

function Geometry.contains(component, value, tolerance)
    value = point(value)
    if component == nil or value == nil or #(component.points or {}) < 3 then
        return false
    end
    tolerance = math.max(0, finite_number(tolerance) or 0.001)
    local bounds = component.bounds or component_bounds(component.points)
    if value.x < bounds.min_x - tolerance
        or value.x > bounds.max_x + tolerance
        or value.y < bounds.min_y - tolerance
        or value.y > bounds.max_y + tolerance then
        return false
    end

    local inside = false
    for index, first in ipairs(component.points) do
        local second = component.points[index % #component.points + 1]
        if point_on_segment(value, first, second, tolerance) then return true end
        if (first.y > value.y) ~= (second.y > value.y) then
            local crossing_x = (second.x - first.x)
                * (value.y - first.y) / (second.y - first.y) + first.x
            if value.x < crossing_x then inside = not inside end
        end
    end
    return inside
end

function Geometry.guild_at(atlas, value)
    for _, component in ipairs(atlas and atlas.components or {}) do
        if Geometry.contains(component, value) then
            return component.controller_guild, component
        end
    end
    return nil
end

return Geometry
