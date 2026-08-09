local Clock = require("PalTR.core.clock")

local Snapshot = {}
Snapshot.__index = Snapshot

function Snapshot.new(registry, diplomacy, actions)
    return setmetatable({ registry = registry, diplomacy = diplomacy, actions = actions }, Snapshot)
end

local function guild_name(registry, key)
    local guild = registry.guilds and registry.guilds[key]
    if guild and guild.name and guild.name ~= "" then return guild.name end
    return key or ""
end

local function proposal_direction(relation, own)
    if not relation or relation.requested_by == nil or relation.requested_by == "" then return "none" end
    if relation.requested_by == own then return "outgoing" end
    return "incoming"
end

local function member_identity(player_key, player)
    local uid = tostring(player and player.uid or "")
        :gsub("[^0-9A-Fa-f]", "")
        :upper()
    if uid ~= "" and not uid:match("^0+$") then
        return "uid:" .. uid
    end

    return "key:" .. tostring(player_key or "")
end

local function guild_members(registry, guild_key)
    local unique = {}
    for player_key, stored in pairs(registry.players or {}) do
        if stored.guild_key == guild_key then
            local identity = member_identity(player_key, stored)
            local runtime = registry.runtime_players
                and registry.runtime_players[player_key]
            local online = runtime ~= nil and runtime.online == true
            local existing = unique[identity]
            if existing == nil then
                unique[identity] = {
                    key = player_key,
                    name = stored.name or "",
                    role = stored.role or -1,
                    is_master = stored.is_master == true,
                    online = online,
                    last_seen = tonumber(stored.last_seen) or 0
                }
            else
                existing.is_master = existing.is_master
                    or stored.is_master == true
                existing.online = existing.online or online
                local last_seen = tonumber(stored.last_seen) or 0
                if online or last_seen > existing.last_seen then
                    existing.key = player_key
                    existing.name = stored.name or existing.name
                    existing.role = stored.role or existing.role
                    existing.last_seen = last_seen
                end
            end
        end
    end

    local result = {}
    for _, member in pairs(unique) do
        member.last_seen = nil
        table.insert(result, member)
    end
    table.sort(result, function(a, b)
        if a.is_master ~= b.is_master then return a.is_master end
        if a.online ~= b.online then return a.online end
        return string.lower(a.name) < string.lower(b.name)
    end)
    return result
end

local function guild_catalog(registry, own)
    local counts = {}
    for key in pairs(registry.guilds or {}) do
        local members = guild_members(registry, key)
        local online = 0
        for _, member in ipairs(members) do
            if member.online then online = online + 1 end
        end
        counts[key] = { members = #members, online = online }
    end

    local result = {}
    for key, guild in pairs(registry.guilds or {}) do
        if key ~= own then
            local count = counts[key] or { members = 0, online = 0 }
            table.insert(result, {
                key = key,
                name = guild.name or key,
                member_count = count.members,
                online_count = count.online,
                active = (registry.runtime_guilds
                    and registry.runtime_guilds[key] ~= nil)
                    or count.online > 0
            })
        end
    end

    table.sort(result, function(a, b)
        if a.active ~= b.active then return a.active end
        return string.lower(a.name) < string.lower(b.name)
    end)
    return result
end

function Snapshot:build(player)
    local own = player and player.guild_key or ""
    local result = {
        schema_version = 1,
        generated_at = Clock.now(),
        player = {
            name = player and player.name or "",
            guild_key = own,
            role = player and player.role or -1,
            is_master = player and player.is_master == true or false
        },
        guild = { key = own, name = guild_name(self.registry, own) },
        guilds = guild_catalog(self.registry, own),
        members = {},
        relations = {}
    }

    if own == "" then return result end

    result.members = guild_members(self.registry, own)

    for _, relation in ipairs(self.diplomacy:relations_for(own)) do
        local other = relation.guild_a == own and relation.guild_b or relation.guild_a
        local action_state = self.actions and self.actions:for_relation(player, relation) or { can_manage = false, reason = "", actions = {} }
        table.insert(result.relations, {
            guild_key = other,
            guild_name = guild_name(self.registry, other),
            state = relation.state or "",
            previous_state = relation.previous_state or "",
            requested_by = relation.requested_by or "",
            accepted_by = relation.accepted_by or "",
            proposal_direction = proposal_direction(relation, own),
            active_at = relation.active_at or 0,
            expires_at = relation.expires_at or 0,
            note = relation.note or "",
            can_manage = action_state.can_manage,
            action_reason = action_state.reason,
            actions = action_state.actions
        })
    end

    table.sort(result.relations, function(a, b)
        return string.lower(a.guild_name) < string.lower(b.guild_name)
    end)

    return result
end

return Snapshot
