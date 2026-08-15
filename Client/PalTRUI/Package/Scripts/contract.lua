local Contract = {}
Contract.SCHEMA_VERSION = 2
Contract.MIN_SCHEMA_VERSION = 1
Contract.DEFAULT_TAB = "CLAN"
Contract.TABS = {
    { id = "CLAN", label = "Klanım" },
    { id = "DIPLOMACY", label = "Diplomasi" },
    { id = "ALLIANCE", label = "İttifak" },
    { id = "GUILDS", label = "Klanlar" },
    { id = "MANAGEMENT", label = "Yönetim" }
}

function Contract.accepts(snapshot)
    local accepted = Contract.validate(snapshot)
    return accepted
end

local function optional_type(record, field, expected)
    return record[field] == nil or type(record[field]) == expected
end

local function validate_actions(actions)
    if type(actions) ~= "table" then
        return false, "relations.actions"
    end
    for _, action in ipairs(actions) do
        if type(action) ~= "table"
            or type(action.id) ~= "string"
            or type(action.label) ~= "string" then
            return false, "relations.actions.item"
        end
    end
    return true
end

local function validate_territories(territories)
    if territories == nil then return true end
    if type(territories) ~= "table"
        or type(territories.nodes) ~= "table"
        or type(territories.boundaries) ~= "table" then
        return false, "territories"
    end
    for _, node in ipairs(territories.nodes) do
        if type(node) ~= "table"
            or type(node.node_id) ~= "string"
            or type(node.node_type) ~= "string"
            or type(node.controller_guild) ~= "string"
            or type(node.x) ~= "number"
            or type(node.y) ~= "number"
            or type(node.z) ~= "number"
            or type(node.radius) ~= "number" then
            return false, "territories.nodes.item"
        end
    end
    for _, boundary in ipairs(territories.boundaries) do
        if type(boundary) ~= "table"
            or type(boundary.boundary_id) ~= "string"
            or type(boundary.controller_guild) ~= "string"
            or type(boundary.points) ~= "table"
            or #boundary.points < 3 then
            return false, "territories.boundaries.item"
        end
        for _, point in ipairs(boundary.points) do
            if type(point) ~= "table"
                or type(point.x) ~= "number"
                or type(point.y) ~= "number" then
                return false, "territories.boundaries.points"
            end
        end
    end
    return true
end

local function validate_protection(protection)
    if protection == nil then return true end
    if type(protection) ~= "table"
        or not optional_type(protection, "available", "boolean")
        or not optional_type(protection, "protected", "boolean")
        or not optional_type(protection, "reason", "string")
        or not optional_type(protection, "online_count", "number")
        or not optional_type(protection, "protected_at", "number")
        or not optional_type(protection, "raid_open", "boolean")
        or not optional_type(protection, "raid_window_start", "string")
        or not optional_type(protection, "raid_window_end", "string") then
        return false, "protection"
    end
    return true
end

local function validate_recent_events(events)
    if events == nil then return true end
    if type(events) ~= "table" then return false, "recent_events" end
    for _, event in ipairs(events) do
        if type(event) ~= "table"
            or type(event.timestamp) ~= "number"
            or type(event.event_type) ~= "string"
            or type(event.message) ~= "string" then
            return false, "recent_events.item"
        end
    end
    return true
end

local function validate_guild_identity(identity, required)
    if identity == nil then
        return required ~= true, "guild_identity"
    end
    if type(identity) ~= "table"
        or type(identity.palette_version) ~= "number"
        or type(identity.selected_color_id) ~= "string"
        or type(identity.selected_emblem_id) ~= "string"
        or type(identity.locked) ~= "boolean"
        or type(identity.can_manage) ~= "boolean"
        or type(identity.colors) ~= "table"
        or type(identity.emblems) ~= "table" then
        return false, "guild_identity"
    end
    for _, color in ipairs(identity.colors) do
        if type(color) ~= "table" or type(color.id) ~= "string"
            or type(color.hex) ~= "string"
            or type(color.available) ~= "boolean" then
            return false, "guild_identity.colors.item"
        end
    end
    for _, emblem in ipairs(identity.emblems) do
        if type(emblem) ~= "table" or type(emblem.id) ~= "string"
            or type(emblem.name) ~= "string" then
            return false, "guild_identity.emblems.item"
        end
    end
    return true
end

function Contract.validate(snapshot)
    if type(snapshot) ~= "table" then return false, "snapshot" end
    local schema_version = tonumber(snapshot.schema_version)
    if schema_version == nil
        or schema_version < Contract.MIN_SCHEMA_VERSION
        or schema_version > Contract.SCHEMA_VERSION then
        return false, "schema_version"
    end
    if type(snapshot.generated_at) ~= "number" then
        return false, "generated_at"
    end
    if type(snapshot.player) ~= "table" then return false, "player" end
    if type(snapshot.guild) ~= "table" then return false, "guild" end
    if snapshot.guilds ~= nil and type(snapshot.guilds) ~= "table" then
        return false, "guilds"
    end
    if type(snapshot.members) ~= "table" then return false, "members" end
    if type(snapshot.relations) ~= "table" then return false, "relations" end

    if not optional_type(snapshot.player, "name", "string")
        or not optional_type(snapshot.player, "guild_key", "string")
        or not optional_type(snapshot.player, "role", "number")
        or not optional_type(snapshot.player, "is_master", "boolean") then
        return false, "player.fields"
    end
    if not optional_type(snapshot.guild, "key", "string")
        or not optional_type(snapshot.guild, "name", "string")
        or not optional_type(snapshot.guild, "color_id", "string")
        or not optional_type(snapshot.guild, "emblem_id", "string") then
        return false, "guild.fields"
    end

    for _, guild in ipairs(snapshot.guilds or {}) do
        if type(guild) ~= "table"
            or not optional_type(guild, "key", "string")
            or not optional_type(guild, "name", "string")
            or not optional_type(guild, "color_id", "string")
            or not optional_type(guild, "emblem_id", "string")
            or not optional_type(guild, "member_count", "number")
            or not optional_type(guild, "online_count", "number")
            or not optional_type(guild, "active", "boolean") then
            return false, "guilds.item"
        end
    end

    for _, member in ipairs(snapshot.members) do
        if type(member) ~= "table"
            or not optional_type(member, "key", "string")
            or not optional_type(member, "name", "string")
            or not optional_type(member, "role", "number")
            or not optional_type(member, "is_master", "boolean")
            or not optional_type(member, "online", "boolean") then
            return false, "members.item"
        end
    end

    for _, relation in ipairs(snapshot.relations) do
        if type(relation) ~= "table"
            or not optional_type(relation, "guild_key", "string")
            or not optional_type(relation, "guild_name", "string")
            or not optional_type(relation, "state", "string")
            or not optional_type(relation, "can_manage", "boolean") then
            return false, "relations.item"
        end
        local actions_valid, actions_error = validate_actions(
            relation.actions or {}
        )
        if not actions_valid then return false, actions_error end
    end
    local territories_valid, territories_error = validate_territories(
        snapshot.territories
    )
    if not territories_valid then return false, territories_error end
    local protection_valid, protection_error = validate_protection(
        snapshot.protection
    )
    if not protection_valid then return false, protection_error end
    local events_valid, events_error = validate_recent_events(
        snapshot.recent_events
    )
    if not events_valid then return false, events_error end
    local identity_valid, identity_error = validate_guild_identity(
        snapshot.guild_identity,
        schema_version >= 2
    )
    if not identity_valid then return false, identity_error end
    return true
end

return Contract
