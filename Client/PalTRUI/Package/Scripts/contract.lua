local Contract = {}
Contract.SCHEMA_VERSION = 1
Contract.DEFAULT_TAB = "CLAN"
Contract.TABS = {
    { id = "CLAN", label = "Klanım" },
    { id = "DIPLOMACY", label = "Diplomasi" },
    { id = "ALLIANCE", label = "İttifak" },
    { id = "CHAT", label = "Sohbet" }
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

function Contract.validate(snapshot)
    if type(snapshot) ~= "table" then return false, "snapshot" end
    if tonumber(snapshot.schema_version) ~= Contract.SCHEMA_VERSION then
        return false, "schema_version"
    end
    if type(snapshot.player) ~= "table" then return false, "player" end
    if type(snapshot.guild) ~= "table" then return false, "guild" end
    if type(snapshot.members) ~= "table" then return false, "members" end
    if type(snapshot.relations) ~= "table" then return false, "relations" end

    if not optional_type(snapshot.player, "name", "string")
        or not optional_type(snapshot.player, "guild_key", "string")
        or not optional_type(snapshot.player, "role", "number")
        or not optional_type(snapshot.player, "is_master", "boolean") then
        return false, "player.fields"
    end
    if not optional_type(snapshot.guild, "key", "string")
        or not optional_type(snapshot.guild, "name", "string") then
        return false, "guild.fields"
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
    return true
end

return Contract
