local Model = {}

Model.DEFAULT_MAX_SEGMENTS = 512
Model.DEFAULT_MAX_NODES = 64
Model.DEFAULT_MAX_BANNERS = 16
Model.NEUTRAL_COLOR = { r = 0.43, g = 0.49, b = 0.55, a = 0.94 }

local EMBLEM_LABELS = {
    wolf = "KURT", eagle = "KARTAL", stag = "GEYIK",
    lion = "ASLAN", raven = "KUZGUN", serpent = "YILAN",
    bear = "AYI", boar = "YABAN", dragon = "EJDER",
    sun = "GUNES", moon = "AY", tower = "KULE"
}

local function text(value) return tostring(value or "") end
local function table_or_empty(value)
    return type(value) == "table" and value or {}
end

local function copy_color(color, alpha)
    color = type(color) == "table" and color or Model.NEUTRAL_COLOR
    return {
        r = tonumber(color.r) or Model.NEUTRAL_COLOR.r,
        g = tonumber(color.g) or Model.NEUTRAL_COLOR.g,
        b = tonumber(color.b) or Model.NEUTRAL_COLOR.b,
        a = tonumber(alpha) or tonumber(color.a) or Model.NEUTRAL_COLOR.a
    }
end

local function color_from_hex(value)
    local hex = text(value):match("^#?(%x%x%x%x%x%x)$")
    if hex == nil then return nil end
    return {
        r = tonumber(hex:sub(1, 2), 16) / 255,
        g = tonumber(hex:sub(3, 4), 16) / 255,
        b = tonumber(hex:sub(5, 6), 16) / 255,
        a = 0.96
    }
end

local function relation_kind(state)
    state = text(state):upper()
    if state == "WAR" then return "WAR" end
    if state == "ALLIANCE" then return "ALLIANCE" end
    if state:sub(-8) == "_PENDING" then return "PENDING" end
    return "NEUTRAL"
end

local function relation_map(snapshot)
    local result = {}
    for _, relation in ipairs(table_or_empty(snapshot.relations)) do
        relation = table_or_empty(relation)
        result[text(relation.guild_key)] = relation_kind(relation.state)
    end
    return result
end

local function status_for(guild_key, own_guild, relations)
    if text(guild_key) ~= "" and text(guild_key) == text(own_guild) then
        return "OWN"
    end
    return relations[text(guild_key)] or "NEUTRAL"
end

local function identity_colors(snapshot)
    local palette, identities = {}, {}
    for _, color in ipairs(table_or_empty(
        table_or_empty(snapshot.guild_identity).colors
    )) do
        local parsed = color_from_hex(color.hex)
        if parsed ~= nil then palette[text(color.id)] = parsed end
    end
    local own = table_or_empty(snapshot.guild)
    identities[text(own.key)] = {
        color_id = text(own.color_id), emblem_id = text(own.emblem_id),
        name = text(own.name)
    }
    for _, guild in ipairs(table_or_empty(snapshot.guilds)) do
        guild = table_or_empty(guild)
        identities[text(guild.key)] = {
            color_id = text(guild.color_id), emblem_id = text(guild.emblem_id),
            name = text(guild.name)
        }
    end
    return palette, identities
end

local function guild_style(key, fallback_name, palette, identities)
    local identity = identities[text(key)] or {}
    local color = palette[text(identity.color_id)] or Model.NEUTRAL_COLOR
    return {
        color = copy_color(color),
        fill_color = copy_color(color, 0.14),
        color_id = text(identity.color_id),
        emblem_id = text(identity.emblem_id),
        emblem_label = EMBLEM_LABELS[text(identity.emblem_id)] or "KLAN",
        name = text(identity.name) ~= "" and text(identity.name)
            or text(fallback_name)
    }
end

local function valid_points(points)
    local result = {}
    for _, point in ipairs(table_or_empty(points)) do
        local x, y = tonumber(point.x), tonumber(point.y)
        if x ~= nil and y ~= nil then table.insert(result, { x = x, y = y }) end
    end
    return result
end

local function polygon_area(points)
    local twice = 0
    for index, first in ipairs(points) do
        local second = points[index % #points + 1]
        twice = twice + first.x * second.y - second.x * first.y
    end
    return math.abs(twice) / 2
end

local function point_in_polygon(point, points)
    local inside, previous = false, #points
    for index = 1, #points do
        local first, second = points[index], points[previous]
        if ((first.y > point.y) ~= (second.y > point.y)) then
            local crossing = (second.x - first.x) * (point.y - first.y)
                / ((second.y - first.y) + 1e-12) + first.x
            if point.x < crossing then inside = not inside end
        end
        previous = index
    end
    return inside
end

local function distance_to_segment(point, first, second)
    local dx, dy = second.x - first.x, second.y - first.y
    local length_squared = dx * dx + dy * dy
    local ratio = length_squared > 0
        and ((point.x - first.x) * dx + (point.y - first.y) * dy)
            / length_squared or 0
    ratio = math.max(0, math.min(1, ratio))
    local x, y = first.x + ratio * dx, first.y + ratio * dy
    local px, py = point.x - x, point.y - y
    return math.sqrt(px * px + py * py)
end

local function interior_center(points)
    local min_x, min_y, max_x, max_y
    local cx, cy = 0, 0
    for _, point in ipairs(points) do
        min_x = min_x == nil and point.x or math.min(min_x, point.x)
        min_y = min_y == nil and point.y or math.min(min_y, point.y)
        max_x = max_x == nil and point.x or math.max(max_x, point.x)
        max_y = max_y == nil and point.y or math.max(max_y, point.y)
        cx, cy = cx + point.x, cy + point.y
    end
    local average = { x = cx / #points, y = cy / #points }
    local best, best_distance = nil, -1
    local function consider(candidate)
        if not point_in_polygon(candidate, points) then return end
        local minimum = math.huge
        for index, first in ipairs(points) do
            minimum = math.min(minimum, distance_to_segment(
                candidate, first, points[index % #points + 1]
            ))
        end
        if minimum > best_distance then best, best_distance = candidate, minimum end
    end
    consider(average)
    for yi = 1, 9 do
        for xi = 1, 9 do
            consider({
                x = min_x + (max_x - min_x) * xi / 10,
                y = min_y + (max_y - min_y) * yi / 10
            })
        end
    end
    return best or average
end

local function simplify_closed(points, maximum)
    if #points <= maximum then return points end
    local result, step = {}, #points / maximum
    for index = 0, maximum - 1 do
        table.insert(result, points[math.floor(index * step) + 1])
    end
    return result
end

local function smooth_closed(points, maximum)
    if #points < 4 then return points end
    local rounded = {}
    for index, current in ipairs(points) do
        local following = points[index % #points + 1]
        table.insert(rounded, {
            x = current.x * 0.75 + following.x * 0.25,
            y = current.y * 0.75 + following.y * 0.25
        })
        table.insert(rounded, {
            x = current.x * 0.25 + following.x * 0.75,
            y = current.y * 0.25 + following.y * 0.75
        })
    end
    return simplify_closed(rounded, maximum)
end

local function allocate_quotas(boundaries, maximum)
    local total = 0
    for _, boundary in ipairs(boundaries) do total = total + #boundary.points end
    if total <= maximum then
        for _, boundary in ipairs(boundaries) do boundary.quota = #boundary.points end
        return
    end
    local assigned = 0
    for _, boundary in ipairs(boundaries) do
        boundary.quota = math.max(3, math.floor(
            maximum * #boundary.points / total
        ))
        assigned = assigned + boundary.quota
    end
    while assigned > maximum do
        local candidate
        for _, boundary in ipairs(boundaries) do
            if boundary.quota > 3 and (candidate == nil
                or boundary.quota > candidate.quota) then candidate = boundary end
        end
        if candidate == nil then break end
        candidate.quota, assigned = candidate.quota - 1, assigned - 1
    end
    while assigned < maximum do
        local candidate
        for _, boundary in ipairs(boundaries) do
            if boundary.quota < #boundary.points and (candidate == nil
                or #boundary.points - boundary.quota
                    > #candidate.points - candidate.quota) then
                candidate = boundary
            end
        end
        if candidate == nil then break end
        candidate.quota, assigned = candidate.quota + 1, assigned + 1
    end
end

function Model.scanline_spans(points, options)
    points, options = valid_points(points), table_or_empty(options)
    if #points < 3 then return {} end
    local min_y, max_y = points[1].y, points[1].y
    for _, point in ipairs(points) do
        min_y, max_y = math.min(min_y, point.y), math.max(max_y, point.y)
    end
    local maximum = math.max(1, tonumber(options.max_spans) or 384)
    local minimum_spacing = options.normalized == true and 0.0005 or 2
    local spacing = math.max(minimum_spacing, tonumber(options.spacing) or 4)
    local function produce(step)
        local spans, y = {}, min_y + step / 2
        while y < max_y do
            local intersections = {}
            for index, first in ipairs(points) do
                local second = points[index % #points + 1]
                if (first.y <= y and second.y > y)
                    or (second.y <= y and first.y > y) then
                    table.insert(intersections, first.x + (y - first.y)
                        * (second.x - first.x) / (second.y - first.y))
                end
            end
            table.sort(intersections)
            for index = 1, #intersections - 1, 2 do
                table.insert(spans, {
                    x = intersections[index], y = y,
                    width = math.max(0, intersections[index + 1]
                        - intersections[index]), height = step
                })
            end
            y = y + step
        end
        return spans
    end
    local spans = produce(spacing)
    while #spans > maximum do
        spacing = spacing * math.max(1.25, #spans / maximum)
        spans = produce(spacing)
    end
    return spans
end

function Model.build(snapshot, limits)
    snapshot, limits = table_or_empty(snapshot), table_or_empty(limits)
    local own_guild = text(table_or_empty(snapshot.player).guild_key)
    local relations = relation_map(snapshot)
    local palette, identities = identity_colors(snapshot)
    local territories = table_or_empty(snapshot.territories)
    local raw_boundaries = {}
    for _, raw in ipairs(table_or_empty(territories.boundaries)) do
        raw = table_or_empty(raw)
        local points = valid_points(raw.points)
        if #points >= 3 then
            table.insert(raw_boundaries, { raw = raw, points = points })
        end
    end
    allocate_quotas(raw_boundaries,
        tonumber(limits.max_segments) or Model.DEFAULT_MAX_SEGMENTS)

    local boundaries, segments = {}, {}
    for _, source in ipairs(raw_boundaries) do
        local raw = source.raw
        local points = smooth_closed(
            simplify_closed(source.points, source.quota),
            source.quota
        )
        local style = guild_style(raw.controller_guild,
            raw.controller_name, palette, identities)
        local status = status_for(raw.controller_guild, own_guild, relations)
        local boundary = {
            boundary_id = text(raw.boundary_id),
            controller_guild = text(raw.controller_guild),
            controller_name = style.name,
            status = status, color = style.color,
            fill_color = style.fill_color, points = {},
            source_points = points, area = polygon_area(points)
        }
        for _, point in ipairs(points) do
            table.insert(boundary.points, {
                x = point.x * 100, y = point.y * 100, z = 0
            })
        end
        table.insert(boundaries, boundary)
        for index, first in ipairs(boundary.points) do
            table.insert(segments, {
                boundary_id = boundary.boundary_id,
                controller_guild = boundary.controller_guild,
                controller_name = boundary.controller_name,
                status = status, color = boundary.color, first = first,
                second = boundary.points[index % #boundary.points + 1]
            })
        end
    end

    local nodes, groups = {}, {}
    for _, raw in ipairs(table_or_empty(territories.nodes)) do
        raw = table_or_empty(raw)
        if #nodes >= (tonumber(limits.max_nodes) or Model.DEFAULT_MAX_NODES) then
            break
        end
        local x, y, z = tonumber(raw.x), tonumber(raw.y), tonumber(raw.z)
        if x ~= nil and y ~= nil and z ~= nil then
            local key = text(raw.controller_guild)
            local style = guild_style(key, raw.controller_name, palette, identities)
            local status = status_for(key, own_guild, relations)
            local node_type = text(raw.node_type)
            local node = {
                node_id = text(raw.node_id), display_name = text(raw.display_name),
                node_type = node_type, controller_guild = key,
                controller_name = style.name, state = text(raw.state),
                flag_state = text(raw.flag_state), status = status,
                color = style.color, color_id = style.color_id,
                emblem_id = style.emblem_id,
                world = { x = x * 100, y = y * 100, z = z * 100 },
                meters = { x = x, y = y },
                size = node_type == "CAPITAL" and 20 or 14,
                icon = node_type == "CAPITAL" and "KALE" or "KULE"
            }
            table.insert(nodes, node)
            local group = groups[key]
            if group == nil then
                group = {
                    key = key, name = style.name, color = style.color,
                    emblem_id = style.emblem_id,
                    emblem_label = style.emblem_label,
                    status = status, nodes = {}, capitals = 0, outposts = 0
                }
                groups[key] = group
            end
            table.insert(group.nodes, node)
            if node_type == "CAPITAL" then
                group.capitals = group.capitals + 1
                group.capital = node
            else
                group.outposts = group.outposts + 1
            end
        end
    end

    local banners = {}
    for key, group in pairs(groups) do
        if #banners >= (tonumber(limits.max_banners)
            or Model.DEFAULT_MAX_BANNERS) then break end
        local primary
        for _, boundary in ipairs(boundaries) do
            if boundary.controller_guild == key and group.capital ~= nil
                and point_in_polygon(group.capital.meters,
                    boundary.source_points)
                and (primary == nil or boundary.area > primary.area) then
                primary = boundary
            end
        end
        if primary == nil and group.capital ~= nil then
            for _, boundary in ipairs(boundaries) do
                if boundary.controller_guild == key
                    and (primary == nil or boundary.area > primary.area) then
                    primary = boundary
                end
            end
        end
        local world
        if primary ~= nil then
            local center = interior_center(primary.source_points)
            world = { x = center.x * 100, y = center.y * 100, z = 0 }
        elseif group.capital ~= nil then
            world = group.capital.world
        end
        if world ~= nil then
            table.insert(banners, {
                guild_key = key, guild_name = group.name,
                emblem_id = group.emblem_id,
                emblem_label = group.emblem_label,
                color = group.color, status = group.status, world = world,
                region_count = #group.nodes,
                capital_count = group.capitals,
                outpost_count = group.outposts,
                region_text = string.format(
                    "%d Bolge (%d Baskent, %d Karakol)",
                    #group.nodes, group.capitals, group.outposts
                ),
                power_text = "Guc: Yakinda"
            })
        end
    end
    table.sort(banners, function(a, b)
        return string.lower(a.guild_name) < string.lower(b.guild_name)
    end)

    return {
        own_guild = own_guild, boundaries = boundaries,
        segments = segments, nodes = nodes, banners = banners,
        segment_count = #segments, node_count = #nodes,
        banner_count = #banners
    }
end

Model.point_in_polygon = point_in_polygon
Model.interior_center = interior_center

return Model
