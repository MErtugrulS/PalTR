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

function Codec.encode(snapshot)
    if type(snapshot) ~= "table" then return nil, "snapshot" end
    local player = type(snapshot.player) == "table" and snapshot.player or {}
    local guild = type(snapshot.guild) == "table" and snapshot.guild or {}
    local guilds = type(snapshot.guilds) == "table" and snapshot.guilds or {}
    local members = type(snapshot.members) == "table" and snapshot.members or {}
    local relations = type(snapshot.relations) == "table" and snapshot.relations or {}
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
    if number(values, "schema_version") == nil
        or number(values, "generated_at") == nil
        or guild_count == nil or member_count == nil
        or relation_count == nil then
        return nil, "header"
    end
    if guild_count > record_count
        or member_count > record_count
        or relation_count > record_count then
        return nil, "count"
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
        relations = {}
    }

    for index = 1, guild_count do
        local prefix = "guilds." .. index .. "."
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
            table.insert(relation.actions, {
                id = values[action_prefix .. "id"] or "",
                label = values[action_prefix .. "label"] or ""
            })
        end
        table.insert(snapshot.relations, relation)
    end
    return snapshot
end

return Codec
