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

local function guild_catalog(registry, own)
    local counts = {}
    for player_key, player in pairs(registry.players or {}) do
        local key = player.guild_key or ""
        if key ~= "" then
            local count = counts[key] or { members = 0, online = 0 }
            count.members = count.members + 1
            local runtime = registry.runtime_players
                and registry.runtime_players[player_key]
            if runtime ~= nil and runtime.online == true then
                count.online = count.online + 1
            end
            counts[key] = count
        end
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

    for key, stored in pairs(self.registry.players or {}) do
        if stored.guild_key == own then
            local runtime = self.registry.runtime_players and self.registry.runtime_players[key]
            table.insert(result.members, {
                key = key,
                name = stored.name or "",
                role = stored.role or -1,
                is_master = stored.is_master == true,
                online = runtime ~= nil and runtime.online == true
            })
        end
    end

    table.sort(result.members, function(a, b)
        if a.is_master ~= b.is_master then return a.is_master end
        if a.online ~= b.online then return a.online end
        return string.lower(a.name) < string.lower(b.name)
    end)

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
