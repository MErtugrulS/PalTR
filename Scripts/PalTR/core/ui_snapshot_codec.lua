local Codec = {}

local function escape(value)
    return tostring(value == nil and "" or value):gsub(
        "([^%w%-%._~])",
        function(character)
            return string.format("%%%02X", string.byte(character))
        end
    )
end

local function unescape(value)
    local index = 1
    while true do
        local position = value:find("%", index, true)
        if position == nil then break end
        local encoded = value:sub(position + 1, position + 2)
        if #encoded ~= 2 or not encoded:match("^%x%x$") then
            return nil
        end
        index = position + 3
    end
    return value:gsub("%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end)
end

local function boolean(value)
    return value == true and "1" or "0"
end

local function add(lines, key, value)
    table.insert(lines, key .. "	" .. escape(value))
end

local function encode_points(points)
    local values = {}
    for _, point in ipairs(type(points) == "table" and points or {}) do
        table.insert(values, string.format(
            "%.3f,%.3f",
            tonumber(point.x) or 0,
            tonumber(point.y) or 0
        ))
    end
    return table.concat(values, ";")
end

function Codec.encode(snapshot)
    if type(snapshot) ~= "table" then return nil, "snapshot" end
    local player = type(snapshot.player) == "table" and snapshot.player or {}
    local guild = type(snapshot.guild) == "table" and snapshot.guild or {}
    local guilds = type(snapshot.guilds) == "table" and snapshot.guilds or {}
    local members = type(snapshot.members) == "table" and snapshot.members or {}
    local relations = type(snapshot.relations) == "table" and snapshot.relations or {}
    local territories = type(snapshot.territories) == "table"
        and snapshot.territories or {}
    local territory_nodes = type(territories.nodes) == "table"
        and territories.nodes or {}
    local territory_boundaries = type(territories.boundaries) == "table"
        and territories.boundaries or {}
    local lines = {}

    add(lines, "schema_version", snapshot.schema_version)
    add(lines, "generated_at", snapshot.generated_at)
    add(lines, "player.name", player.name)
    add(lines, "player.guild_key", player.guild_key)
    add(lines, "player.role", player.role)
    add(lines, "player.is_master", boolean(player.is_master))
    add(lines, "guild.key", guild.key)
    add(lines, "guild.name", guild.name)

    add(lines, "guilds.count", #guilds)
    for index, item in ipairs(guilds) do
        local prefix = "guilds." .. index .. "."
        add(lines, prefix .. "key", item.key)
        add(lines, prefix .. "name", item.name)
        add(lines, prefix .. "member_count", item.member_count)
        add(lines, prefix .. "online_count", item.online_count)
        add(lines, prefix .. "active", boolean(item.active))
    end

    add(lines, "members.count", #members)
    for index, item in ipairs(members) do
        local prefix = "members." .. index .. "."
        add(lines, prefix .. "key", item.key)
        add(lines, prefix .. "name", item.name)
        add(lines, prefix .. "role", item.role)
        add(lines, prefix .. "is_master", boolean(item.is_master))
        add(lines, prefix .. "online", boolean(item.online))
    end

    add(lines, "relations.count", #relations)
    for index, item in ipairs(relations) do
        local prefix = "relations." .. index .. "."
        for _, field in ipairs({
            "guild_key", "guild_name", "state", "previous_state",
            "requested_by", "accepted_by", "proposal_direction",
            "active_at", "expires_at", "note", "action_reason"
        }) do
            add(lines, prefix .. field, item[field])
        end
        add(lines, prefix .. "can_manage", boolean(item.can_manage))
        local actions = type(item.actions) == "table" and item.actions or {}
        add(lines, prefix .. "actions.count", #actions)
        for action_index, action in ipairs(actions) do
            local action_prefix = prefix .. "actions." .. action_index .. "."
            add(lines, action_prefix .. "id", action.id)
            add(lines, action_prefix .. "label", action.label)
        end
    end
    add(lines, "territories.nodes.count", #territory_nodes)
    for index, item in ipairs(territory_nodes) do
        local prefix = "territories.nodes." .. index .. "."
        for _, field in ipairs({
            "node_id", "display_name", "node_type", "controller_guild",
            "controller_name", "x", "y", "z", "radius", "state",
            "flag_state"
        }) do
            add(lines, prefix .. field, item[field])
        end
    end

    add(lines, "territories.boundaries.count", #territory_boundaries)
    for index, item in ipairs(territory_boundaries) do
        local prefix = "territories.boundaries." .. index .. "."
        for _, field in ipairs({
            "boundary_id", "controller_guild", "controller_name",
            "component_index", "min_x", "min_y", "max_x", "max_y"
        }) do
            add(lines, prefix .. field, item[field])
        end
        add(lines, prefix .. "points", encode_points(item.points))
    end
    return table.concat(lines, "\n")
end

local function number(values, key)
    return tonumber(values[key] or "")
end

local function count(values, key)
    local value = number(values, key)
    if value == nil or value < 0 or value ~= math.floor(value) then return nil end
    return value
end

local function flag(values, key)
    return values[key] == "1"
end

local function valid_flag(values, key)
    return values[key] == "0" or values[key] == "1"
end

local function present(values, keys)
    for _, key in ipairs(keys) do
        if values[key] == nil then return false end
    end
    return true
end

local function optional_count(values, key)
    if values[key] == nil then return 0 end
    return count(values, key)
end

local function decode_points(value)
    local points = {}
    for encoded in (tostring(value or "") .. ";"):gmatch("(.-);") do
        if encoded ~= "" then
            local x, y = encoded:match("^([^,]+),([^,]+)$")
            x, y = tonumber(x), tonumber(y)
            if x == nil or y == nil then return nil end
            table.insert(points, { x = x, y = y })
            if #points > 1024 then return nil end
        end
    end
    return points
end

function Codec.decode(payload)
    if type(payload) ~= "string" then return nil, "payload" end
    local values = {}
    local record_count = 0
    for line in (payload .. "\n"):gmatch("(.-)\n") do
        if line ~= "" then
            local key, encoded = line:match("^([^	]+)	(.*)$")
            if key == nil or values[key] ~= nil then return nil, "record" end
            local value = unescape(encoded)
            if value == nil then return nil, "escape" end
            values[key] = value
            record_count = record_count + 1
        end
    end

    local guild_count = count(values, "guilds.count")
    local member_count = count(values, "members.count")
    local relation_count = count(values, "relations.count")
    local territory_node_count = optional_count(
        values,
        "territories.nodes.count"
    )
    local territory_boundary_count = optional_count(
        values,
        "territories.boundaries.count"
    )
    if number(values, "schema_version") == nil
        or number(values, "generated_at") == nil
        or guild_count == nil or member_count == nil
        or relation_count == nil or territory_node_count == nil
        or territory_boundary_count == nil then
        return nil, "header"
    end
    if guild_count > record_count
        or member_count > record_count
        or relation_count > record_count
        or territory_node_count > record_count
        or territory_boundary_count > record_count then
        return nil, "count"
    end
    if not present(values, {
        "player.name", "player.guild_key", "player.role",
        "player.is_master", "guild.key", "guild.name"
    }) or number(values, "player.role") == nil
        or not valid_flag(values, "player.is_master") then
        return nil, "identity"
    end

    local snapshot = {
        schema_version = number(values, "schema_version"),
        generated_at = number(values, "generated_at"),
        player = {
            name = values["player.name"] or "",
            guild_key = values["player.guild_key"] or "",
            role = number(values, "player.role") or -1,
            is_master = flag(values, "player.is_master")
        },
        guild = {
            key = values["guild.key"] or "",
            name = values["guild.name"] or ""
        },
        guilds = {},
        members = {},
        relations = {},
        territories = { nodes = {}, boundaries = {} }
    }

    for index = 1, guild_count do
        local prefix = "guilds." .. index .. "."
        if not present(values, {
            prefix .. "key", prefix .. "name",
            prefix .. "member_count", prefix .. "online_count",
            prefix .. "active"
        }) or number(values, prefix .. "member_count") == nil
            or number(values, prefix .. "online_count") == nil
            or not valid_flag(values, prefix .. "active") then
            return nil, "guilds"
        end
        table.insert(snapshot.guilds, {
            key = values[prefix .. "key"] or "",
            name = values[prefix .. "name"] or "",
            member_count = number(values, prefix .. "member_count") or 0,
            online_count = number(values, prefix .. "online_count") or 0,
            active = flag(values, prefix .. "active")
        })
    end
    for index = 1, member_count do
        local prefix = "members." .. index .. "."
        if not present(values, {
            prefix .. "key", prefix .. "name", prefix .. "role",
            prefix .. "is_master", prefix .. "online"
        }) or number(values, prefix .. "role") == nil
            or not valid_flag(values, prefix .. "is_master")
            or not valid_flag(values, prefix .. "online") then
            return nil, "members"
        end
        table.insert(snapshot.members, {
            key = values[prefix .. "key"] or "",
            name = values[prefix .. "name"] or "",
            role = number(values, prefix .. "role") or -1,
            is_master = flag(values, prefix .. "is_master"),
            online = flag(values, prefix .. "online")
        })
    end
    for index = 1, relation_count do
        local prefix = "relations." .. index .. "."
        if not present(values, {
            prefix .. "guild_key", prefix .. "guild_name",
            prefix .. "state", prefix .. "previous_state",
            prefix .. "requested_by", prefix .. "accepted_by",
            prefix .. "proposal_direction", prefix .. "active_at",
            prefix .. "expires_at", prefix .. "note",
            prefix .. "action_reason", prefix .. "can_manage",
            prefix .. "actions.count"
        }) or number(values, prefix .. "active_at") == nil
            or number(values, prefix .. "expires_at") == nil
            or not valid_flag(values, prefix .. "can_manage") then
            return nil, "relations"
        end
        local relation = {
            guild_key = values[prefix .. "guild_key"] or "",
            guild_name = values[prefix .. "guild_name"] or "",
            state = values[prefix .. "state"] or "",
            previous_state = values[prefix .. "previous_state"] or "",
            requested_by = values[prefix .. "requested_by"] or "",
            accepted_by = values[prefix .. "accepted_by"] or "",
            proposal_direction = values[prefix .. "proposal_direction"] or "",
            active_at = number(values, prefix .. "active_at") or 0,
            expires_at = number(values, prefix .. "expires_at") or 0,
            note = values[prefix .. "note"] or "",
            can_manage = flag(values, prefix .. "can_manage"),
            action_reason = values[prefix .. "action_reason"] or "",
            actions = {}
        }
        local action_count = count(values, prefix .. "actions.count")
        if action_count == nil then return nil, "actions" end
        if action_count > record_count then return nil, "count" end
        for action_index = 1, action_count do
            local action_prefix = prefix .. "actions." .. action_index .. "."
            if not present(values, {
                action_prefix .. "id", action_prefix .. "label"
            }) then
                return nil, "actions"
            end
            table.insert(relation.actions, {
                id = values[action_prefix .. "id"] or "",
                label = values[action_prefix .. "label"] or ""
            })
        end
        table.insert(snapshot.relations, relation)
    end
    for index = 1, territory_node_count do
        local prefix = "territories.nodes." .. index .. "."
        if not present(values, {
            prefix .. "node_id", prefix .. "display_name",
            prefix .. "node_type", prefix .. "controller_guild",
            prefix .. "controller_name", prefix .. "x", prefix .. "y",
            prefix .. "z", prefix .. "radius", prefix .. "state",
            prefix .. "flag_state"
        }) or number(values, prefix .. "x") == nil
            or number(values, prefix .. "y") == nil
            or number(values, prefix .. "z") == nil
            or number(values, prefix .. "radius") == nil then
            return nil, "territory_nodes"
        end
        table.insert(snapshot.territories.nodes, {
            node_id = values[prefix .. "node_id"] or "",
            display_name = values[prefix .. "display_name"] or "",
            node_type = values[prefix .. "node_type"] or "",
            controller_guild = values[prefix .. "controller_guild"] or "",
            controller_name = values[prefix .. "controller_name"] or "",
            x = number(values, prefix .. "x") or 0,
            y = number(values, prefix .. "y") or 0,
            z = number(values, prefix .. "z") or 0,
            radius = number(values, prefix .. "radius") or 0,
            state = values[prefix .. "state"] or "",
            flag_state = values[prefix .. "flag_state"] or ""
        })
    end
    for index = 1, territory_boundary_count do
        local prefix = "territories.boundaries." .. index .. "."
        if not present(values, {
            prefix .. "boundary_id", prefix .. "controller_guild",
            prefix .. "controller_name", prefix .. "component_index",
            prefix .. "min_x", prefix .. "min_y", prefix .. "max_x",
            prefix .. "max_y", prefix .. "points"
        }) then return nil, "territory_boundaries" end
        local points = decode_points(values[prefix .. "points"])
        if points == nil or #points < 3 then
            return nil, "territory_boundaries"
        end
        table.insert(snapshot.territories.boundaries, {
            boundary_id = values[prefix .. "boundary_id"] or "",
            controller_guild = values[prefix .. "controller_guild"] or "",
            controller_name = values[prefix .. "controller_name"] or "",
            component_index = number(values, prefix .. "component_index") or 0,
            min_x = number(values, prefix .. "min_x") or 0,
            min_y = number(values, prefix .. "min_y") or 0,
            max_x = number(values, prefix .. "max_x") or 0,
            max_y = number(values, prefix .. "max_y") or 0,
            points = points
        })
    end
    return snapshot
end

return Codec
