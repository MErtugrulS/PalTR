local GuildAdapter = require("PalTR.runtime.guild_adapter")
local PlayerAdapter = require("PalTR.runtime.player_adapter")
local Repositories = require("PalTR.storage.repositories")
local Clock = require("PalTR.core.clock")
local Text = require("PalTR.core.text")
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
        runtime_guilds = {}
    }, Registry)
end

function Registry:save()
    Repositories.save_guilds(self.paths.guilds, self.guilds)
    Repositories.save_players(self.paths.players, self.players)
    self:save_online()
end

function Registry:save_online()
    local lines = {
        "player_key\tplayer_name\tguild_key\tconnected_at\tlast_seen"
    }

    for key, player in pairs(self.runtime_players) do
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
    FileIO.overwrite(self.paths.online, lines)
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

    Repositories.save_guilds(self.paths.guilds, self.guilds)
    self.logger:info("Klan sayisi: " .. tostring(
        require("PalTR.core.table_utils").count(self.guilds)
    ))
end

function Registry:on_connected(context, pawn)
    local runtime = PlayerAdapter.from_connection(context, pawn)
    local existing = self.players[runtime.key]

    if existing then runtime.first_seen = existing.first_seen end

    self.runtime_players[runtime.key] = runtime
    self.players[runtime.key] = runtime
    self:save()
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

function Registry:poll_validity(on_disconnected)
    for key, player in pairs(self.runtime_players) do
        if player.online and not UE.valid(player.controller) then
            player.online = false
            player.last_seen = Clock.now()
            self.players[key] = player
            if on_disconnected then on_disconnected(player) end
        elseif player.online then
            player.last_seen = Clock.now()
        end
    end
    self:save()
end

return Registry
