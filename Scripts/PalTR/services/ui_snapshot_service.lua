local Clock = require("PalTR.core.clock")
local TerritorySnapshotReader = require(
    "PalTR.services.territory_snapshot_reader"
)

local Snapshot = {}
Snapshot.__index = Snapshot

local function unavailable_protection()
    return {
        available = false,
        protected = false,
        reason = "",
        online_count = 0,
        protected_at = 0,
        raid_open = false,
        raid_window_start = "",
        raid_window_end = ""
    }
end

function Snapshot.new(registry, diplomacy, actions, paths, options)
    options = options or {}
    return setmetatable({
        registry = registry,
        diplomacy = diplomacy,
        actions = actions,
        paths = paths or {},
        conquest_config = type(options.config) == "table"
            and (options.config.conquest or options.config) or {},
        protection_reader = options.protection_reader
            or unavailable_protection,
        territory_reader = options.territory_reader
            or TerritorySnapshotReader.read,
        guild_identity = options.guild_identity
    }, Snapshot)
end

function Snapshot:set_guild_identity(service)
    self.guild_identity = service
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

local function identity_for(service, guild_key)
    if service == nil or guild_key == nil or guild_key == "" then
        return { color_id = "", emblem_id = "" }
    end
    local ok, record = pcall(service.get, service, guild_key)
    if not ok or type(record) ~= "table" then
        return { color_id = "", emblem_id = "" }
    end
    return {
        color_id = tostring(record.color_id or ""),
        emblem_id = tostring(record.emblem_id or "")
    }
end

local function guild_catalog(registry, own, identity_service)
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
            local identity = identity_for(identity_service, key)
            table.insert(result, {
                key = key,
                name = guild.name or key,
                color_id = identity.color_id,
                emblem_id = identity.emblem_id,
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

local function player_conquest_role(player, config)
    if player and player.is_master == true then return "LEADER" end
    local role = player and player.role
    local mapped = type(config.game_role_map) == "table"
        and config.game_role_map[tonumber(role)] or nil
    return mapped or tostring(role or "")
end

local function identity_catalog(service, guild_key, role)
    local fallback = {
        palette_version = 0,
        selected_color_id = "",
        selected_emblem_id = "",
        locked = false,
        can_manage = false,
        colors = {}, emblems = {}
    }
    if service == nil or guild_key == "" then return fallback end
    local ok, catalog = pcall(service.catalog_for, service, guild_key, role)
    if not ok or type(catalog) ~= "table" then return fallback end
    return catalog
end

function Snapshot:build(player)
    local own = player and player.guild_key or ""
    local result = {
        schema_version = 2,
        generated_at = Clock.now(),
        player = {
            name = player and player.name or "",
            guild_key = own,
            role = player and player.role or -1,
            is_master = player and player.is_master == true or false
        },
        guild = { key = own, name = guild_name(self.registry, own) },
        guilds = guild_catalog(self.registry, own, self.guild_identity),
        guild_identity = identity_catalog(
            self.guild_identity,
            own,
            player_conquest_role(player, self.conquest_config)
        ),
        members = {},
        relations = {},
        protection = unavailable_protection(),
        territories = { nodes = {}, boundaries = {} }
    }

    local own_identity = identity_for(self.guild_identity, own)
    result.guild.color_id = own_identity.color_id
    result.guild.emblem_id = own_identity.emblem_id

    local protection_ok, protection = pcall(
        self.protection_reader,
        self.paths,
        own,
        result.generated_at,
        self.conquest_config
    )
    if protection_ok and type(protection) == "table" then
        result.protection = protection
    end

    local territory_ok, territories = pcall(
        self.territory_reader,
        self.paths
    )
    if territory_ok and type(territories) == "table" then
        result.territories.nodes = type(territories.nodes) == "table"
            and territories.nodes or {}
        result.territories.boundaries =
            type(territories.boundaries) == "table"
                and territories.boundaries or {}
    end

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
