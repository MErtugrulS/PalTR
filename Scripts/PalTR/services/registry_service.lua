local GuildAdapter = require("PalTR.runtime.guild_adapter")
local PlayerAdapter = require("PalTR.runtime.player_adapter")
local Repositories = require("PalTR.storage.repositories")
local Clock = require("PalTR.core.clock")
local Result = require("PalTR.core.result")
local Text = require("PalTR.core.text")
local Tables = require("PalTR.core.table_utils")
local UE = require("PalTR.runtime.ue")

local Registry = {}
Registry.__index = Registry

function Registry.new(paths, logger)
    return setmetatable({
        paths = paths,
        logger = logger,
        guilds = Repositories.load_guilds(paths.guilds),
        players = Repositories.load_players(paths.players),
        runtime_players = {},
        runtime_guilds = {},
        last_player_snapshot_at = 0
    }, Registry)
end

function Registry:_write_failed(label, result)
    if result.ok then return false end
    self.logger:error(
        label .. ": " ..
        tostring(result.error and result.error.message or "")
    )
    return true
end

function Registry:_save_player_state(now)
    local players = Repositories.save_players(
        self.paths.players,
        self.players
    )
    if self:_write_failed("Oyuncu registry yazilamadi", players) then
        return players
    end

    local online = self:save_online()
    if online.ok then
        self.last_player_snapshot_at = tonumber(now) or Clock.now()
    end
    return online
end

function Registry:save(now)
    local guilds = Repositories.save_guilds(
        self.paths.guilds,
        self.guilds
    )
    if self:_write_failed("Klan registry yazilamadi", guilds) then
        return guilds
    end

    return self:_save_player_state(now)
end

function Registry:save_online()
    local lines = {
        "player_key\tplayer_name\tguild_key\tconnected_at\tlast_seen"
    }

    for _, key in ipairs(Tables.sorted_keys(self.runtime_players)) do
        local player = self.runtime_players[key]
        if player.online then
            table.insert(lines, table.concat({
                Text.clean(key),
                Text.clean(player.name),
                Text.clean(player.guild_key),
                tostring(player.first_seen),
                tostring(player.last_seen)
            }, "\t"))
        end
    end

    local FileIO = require("PalTR.storage.file_io")
    local result = FileIO.overwrite(self.paths.online, lines)
    self:_write_failed("Online oyuncu snapshot'i yazilamadi", result)
    return result
end

function Registry:scan_guilds()
    local scanned = GuildAdapter.scan()

    for key, record in pairs(scanned) do
        local existing = self.guilds[key]
        if existing then record.first_seen = existing.first_seen end

        self.runtime_guilds[key] = record.object
        record.object = nil
        self.guilds[key] = record
    end

    local saved = Repositories.save_guilds(
        self.paths.guilds,
        self.guilds
    )
    if self:_write_failed("Klan taramasi yazilamadi", saved) then
        return saved
    end
    self.logger:info("Klan sayisi: " .. tostring(
        require("PalTR.core.table_utils").count(self.guilds)
    ))
    return saved
end

function Registry:on_connected(context, pawn)
    local runtime = PlayerAdapter.from_connection(context, pawn)
    local existing = self.players[runtime.key]

    if existing then
        runtime.first_seen = existing.first_seen
        runtime.uid = existing.uid
        runtime.guild_key = existing.guild_key
        runtime.role = existing.role
        runtime.is_master = existing.is_master
    end

    self.runtime_players[runtime.key] = runtime
    self.players[runtime.key] = runtime
    self:_save_player_state()
    return runtime
end

function Registry:on_guild_update(player_state_param, guild_param, uid_param)
    local player_state = UE.unwrap(player_state_param)
    local guild = UE.unwrap(guild_param)
    local uid = UE.unwrap(uid_param)

    local guild_record = GuildAdapter.from_object(guild)
    if not guild_record then return nil end

    local existing_guild = self.guilds[guild_record.key]
    if existing_guild then
        guild_record.first_seen = existing_guild.first_seen
    end
    self.runtime_guilds[guild_record.key] = guild
    guild_record.object = nil
    self.guilds[guild_record.key] = guild_record

    local player_state_path = UE.full_name(player_state)
    local matched = nil

    for _, player in pairs(self.runtime_players) do
        if player.player_state_path == player_state_path then
            matched = player
            break
        end
    end

    if not matched then
        local name = UE.text(UE.read(player_state, "PlayerNamePrivate"))
        local player_id = UE.text(UE.read(player_state, "PlayerId"))
        local key = name .. "#" .. player_id
        matched = {
            key = key,
            name = name,
            player_id = player_id,
            uid = UE.guid(uid),
            guild_key = guild_record.key,
            role = -1,
            is_master = false,
            player_state = player_state,
            player_state_path = player_state_path,
            pawn_path = "",
            first_seen = Clock.now(),
            last_seen = Clock.now(),
            online = true
        }
        self.runtime_players[key] = matched
    end

    matched.uid = UE.guid(uid)
    matched.guild_key = guild_record.key
    matched.last_seen = Clock.now()
    PlayerAdapter.refresh_authority(matched, guild, uid)

    self.players[matched.key] = matched
    self:save()
    return matched
end

-- PALTR_STRUCTURE_IDENTITY_V1
local function normalize_registry_id(value)
    return tostring(value or "")
        :gsub("[^0-9A-Fa-f]", "")
        :upper()
end

function Registry:find_by_uid(uid)
    local wanted = normalize_registry_id(uid)

    if wanted == "" then
        return nil
    end

    for _, player in pairs(
        self.runtime_players or {}
    ) do
        if normalize_registry_id(player.uid) == wanted then
            return player
        end
    end

    for _, player in pairs(
        self.players or {}
    ) do
        if normalize_registry_id(player.uid) == wanted then
            return player
        end
    end

    return nil
end

function Registry:find_guild_by_id(guild_id)
    local wanted = normalize_registry_id(guild_id)

    if wanted == "" then
        return nil
    end

    for _, guild in pairs(
        self.guilds or {}
    ) do
        if normalize_registry_id(guild.id) == wanted then
            return guild
        end
    end

    return nil
end

function Registry:resolve_structure_identity(
    build_player_uid,
    attacker_group_id
)
    local owner = self:find_by_uid(
        build_player_uid
    )

    local target_guild_key = ""

    if owner ~= nil then
        target_guild_key =
            tostring(owner.guild_key or "")
    end

    if target_guild_key == ""
        and self.guilds[
            tostring(build_player_uid or "")
        ] ~= nil
    then
        target_guild_key =
            tostring(build_player_uid)
    end

    local attacker_guild =
        self:find_guild_by_id(
            attacker_group_id
        )

    local attacker_guild_key = ""

    if attacker_guild ~= nil then
        attacker_guild_key =
            tostring(attacker_guild.key or "")
    end

    return target_guild_key,
        attacker_guild_key,
        owner
end
function Registry:find_by_controller(controller)
    local path = UE.full_name(controller)
    for _, player in pairs(self.runtime_players) do
        if player.controller_path == path then return player end
    end
    return nil
end

function Registry:resolve_guild(query)
    query = Text.clean(query)
    if query == "" then return nil, "Hedef klan belirtilmedi" end

    if self.guilds[query] then return self.guilds[query] end

    local lower_query = Text.lower_ascii(query)
    local matches = {}

    for _, guild in pairs(self.guilds) do
        local lower_name = Text.lower_ascii(guild.name)
        local lower_key = Text.lower_ascii(guild.key)

        if lower_name == lower_query or lower_key == lower_query then
            return guild
        end

        if Text.starts_with(lower_name, lower_query)
            or Text.starts_with(lower_key, lower_query) then
            table.insert(matches, guild)
        end
    end

    if #matches == 1 then return matches[1] end
    if #matches > 1 then return nil, "Birden fazla klan eslesti" end
    return nil, "Klan bulunamadi"
end

function Registry:poll_validity(on_disconnected, snapshot_seconds, now)
    now = tonumber(now) or Clock.now()
    local disconnected = false

    for key, player in pairs(self.runtime_players) do
        if player.online and not UE.valid(player.controller) then
            player.online = false
            player.last_seen = now
            self.players[key] = player
            disconnected = true
            if on_disconnected then on_disconnected(player) end
        elseif player.online then
            player.last_seen = now
        end
    end

    local interval = math.max(tonumber(snapshot_seconds) or 60, 1)
    if disconnected
        or now - self.last_player_snapshot_at >= interval then
        return self:_save_player_state(now)
    end

    return Result.ok(false)
end

return Registry
