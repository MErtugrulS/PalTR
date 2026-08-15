local Logger = require("PalTR.core.logger")
local Paths = require("PalTR.core.paths")
local Clock = require("PalTR.core.clock")
local FileIO = require("PalTR.storage.file_io")
local TSV = require("PalTR.storage.tsv")
local HookRegistry = require("PalTR.runtime.hook_registry")
local StructureProbe = require("PalTR.runtime.structure_probe")
local StructurePreDamageProbe = require("PalTR.runtime.structure_predamage_probe")
local Announcer = require("PalTR.runtime.announcer")
local RegistryService = require("PalTR.services.registry_service")
local DiplomacyService = require("PalTR.services.diplomacy_service")
local StatusService = require("PalTR.services.status_service")
local CommandService = require("PalTR.services.command_service")
local DamageObserver = require("PalTR.services.damage_observer")
local DamagePolicy = require("PalTR.services.damage_policy")
local UIActionService = require("PalTR.services.ui_action_service")
local UISnapshotService = require("PalTR.services.ui_snapshot_service")
local UISnapshotPublisher = require("PalTR.services.ui_snapshot_publisher")
local Scheduler = require("PalTR.services.scheduler")

local App = {}
App.__index = App

function App.new(config)
    local paths = Paths.new(config.data_root)

    local registry = RegistryService.new(
        paths,
        Logger.new("Registry")
    )

    local diplomacy = DiplomacyService.new(
        paths,
        config,
        Logger.new("Diplomacy")
    )

    local status = StatusService.new(
        paths,
        registry,
        diplomacy
    )

    local damage_policy = DamagePolicy.new(
        config,
        diplomacy
    )

    local ui_actions = UIActionService.new(config)
    local ui_snapshot = UISnapshotService.new(
        registry,
        diplomacy,
        ui_actions,
        paths
    )
    local ui_publisher = UISnapshotPublisher.new(
        ui_snapshot,
        Logger.new("UITransport")
    )

    return setmetatable({
        config = config,
        paths = paths,
        logger = Logger.new("App"),
        hooks = HookRegistry.new(Logger.new("Hooks")),
        registry = registry,
        diplomacy = diplomacy,
        status = status,
        damage_policy = damage_policy,
        ui_actions = ui_actions,
        ui_snapshot = ui_snapshot,
        ui_publisher = ui_publisher,

        commands = CommandService.new(
            paths,
            registry,
            diplomacy,
            status,
            Logger.new("Commands"),
            function(player)
                return ui_publisher:publish(player, true)
            end
        ),

        damage = DamageObserver.new(
            paths.damage,
            registry,
            damage_policy,
            Logger.new("Damage")
        ),

        scheduler = Scheduler.new(
            Logger.new("Scheduler")
        ),

        last_guild_scan = 0
    }, App)
end

function App:_headers()
    local files = {
        [self.paths.guilds] =
            "guild_key\tguild_name\tguild_id\tobject_path\tfirst_seen\tlast_seen",

        [self.paths.players] =
            "player_key\tplayer_name\tplayer_id\tplayer_uid\tguild_key\trole\tis_master\tplayer_state_path\tpawn_path\tfirst_seen\tlast_seen",

        [self.paths.online] =
            "player_key\tplayer_name\tguild_key\tconnected_at\tlast_seen",

        [self.paths.relations] =
            "pair_key\tguild_a\tguild_b\tstate\tprevious_state\trequested_by\taccepted_by\tcreated_at\tupdated_at\tactive_at\texpires_at\tnote",

        [self.paths.events] =
            "timestamp\tevent_type\tpair_key\tdetail",

        [self.paths.responses] =
            "timestamp\tplayer_name\tguild_key\tcommand\tsuccess\tmessage",

        [self.paths.damage] =
            "timestamp\ttarget_path\tplayer_name\tguild_key\tdetail",

        [self.paths.structure] =
            "timestamp\tfunction\tobject_path\tguild_id\tparameters",

        [self.paths.health] =
            "timestamp\tversion\tstatus"
    }

    for path, header in pairs(files) do
        local file = io.open(path, "r")

        if file then
            file:close()
        else
            FileIO.overwrite(path, { header })
        end
    end
end

function App:_guild_name(guild_key)
    local guild = self.registry.guilds[guild_key]

    if guild and guild.name and guild.name ~= "" then
        return guild.name
    end

    return guild_key
end

function App:_announce_relation(relation, message)
    for _, player in pairs(
        self.registry.runtime_players or {}
    ) do
        local belongs =
            player.guild_key == relation.guild_a
            or player.guild_key == relation.guild_b

        if player.online
            and belongs
            and player.controller ~= nil then

            Announcer.send(
                player.controller,
                message,
                self.logger
            )
        end
    end
end

function App:_handle_diplomacy_events(events)
    for _, event in ipairs(events or {}) do
        local relation = event.relation

        if event.name == "WAR_STARTED" then
            local first = self:_guild_name(
                relation.guild_a
            )

            local second = self:_guild_name(
                relation.guild_b
            )

            self:_announce_relation(
                relation,
                first .. " ile " .. second ..
                " arasindaki savas basladi. " ..
                "Savas yalnizca karsilikli barisla sona erecek."
            )

        elseif event.name == "CEASEFIRE_ENDED" then
            local first = self:_guild_name(
                relation.guild_a
            )

            local second = self:_guild_name(
                relation.guild_b
            )

            self:_announce_relation(
                relation,
                first .. " ile " .. second ..
                " arasindaki 12 saatlik ateskes sona erdi. " ..
                "Savas yeniden basladi."
            )

        elseif event.name == "PROPOSAL_EXPIRED" then
            self:_announce_relation(
                relation,
                "Bekleyen diplomasi teklifinin suresi doldu."
            )

        elseif event.name == "WAR_MADE_INDEFINITE" then
            self.logger:info(
                "Eski savas kaydi suresiz savasa cevrildi: " ..
                tostring(relation.key)
            )

        elseif event.name == "CEASEFIRE_TIMER_REPAIRED" then
            self.logger:info(
                "Eski ateskes kaydina 12 saatlik sure eklendi: " ..
                tostring(relation.key)
            )
        end
    end
end

function App:_register_hooks()
    self.hooks:register(
        "PlayerConnected",
        "/Script/Engine.PlayerController:ServerAcknowledgePossession",
        function(context, pawn)
            local player =
                self.registry:on_connected(
                    context,
                    pawn
                )

            self.registry:scan_guilds()

            self.status:build(
                player,
                "Oyuncu baglandi"
            )
            self.ui_publisher:publish(player, true)
        end
    )

    self.hooks:register(
        "PlayerGuildMapped",
        "/Script/Pal.PalPlayerState:OnUpdatePlayerInfoInGuildBelongTo",
        function(context, guild, uid, _player_info)
            local player =
                self.registry:on_guild_update(
                    context,
                    guild,
                    uid
                )

            if player then
                self.status:build(
                    player,
                    "Oyuncu-klan eslemesi guncellendi"
                )
                self.ui_publisher:publish(player, true)
            end
        end
    )

    self.hooks:register(
        "ChatCommand",
        "/Script/Pal.PalPlayerController:EnterChat_Receive",
        function(context, message, _chat_type)
            local ok, error_message = pcall(function()
                self.commands:on_chat(
                    context,
                    message
                )
            end)

            if not ok then
                self.logger:error(
                    "CHAT_HOOK_HATA | " ..
                    tostring(error_message)
                )
            end
        end
    )

    self.hooks:register(
        "PlayerDamagePassive",
        "/Script/Pal.PalPlayerCharacter:OnDamagePlayer_Server",
        function(context, damage_result)
            self.damage:on_player_damage(
                context,
                damage_result
            )
        end
    )

    self.hooks:register(
        "EnemyPlayerDamageEnforcement",
        "/Script/Pal.PalPlayerController:DamageReactionComponent_ProcessDamage_ToServer_ToEnemyPlayer",
        function(context, info, defender)
            self.damage:on_enemy_player_damage_request(
                context,
                info,
                defender
            )
        end
    )
    if self.config.runtime
        .enable_structure_damage_probe then

        StructureProbe.register(
                self.hooks,
                self.paths.structure,
                self.registry,
                self.damage_policy,
                Logger.new("StructureProbe")
            )

            StructurePreDamageProbe.register(
                self.hooks,
                self.paths.structure,
                self.registry,
                self.damage_policy,
                Logger.new("StructurePreDamage")
            )
    end
end

function App:_tick()
    local diplomacy_events =
        self.diplomacy:tick()

    self:_handle_diplomacy_events(
        diplomacy_events
    )

    if self.config.runtime.player_validity_poll then
        self.registry:poll_validity(
            function(player)
                FileIO.append(
                    self.paths.events,
                    TSV.encode({
                        Clock.now(),
                        "PLAYER_DISCONNECTED_POLL",
                        player.guild_key,
                        player.name
                    })
                )

                self.status:build(
                    player,
                    "Oyuncu cevrimdisi algilandi"
                )
            end
        )
    end

    local now = Clock.now()

    if now - self.last_guild_scan
        >= self.config.runtime.guild_scan_seconds then

        self.registry:scan_guilds()
        self.last_guild_scan = now
    end

    self.ui_publisher:publish_all(
        self.registry.runtime_players
    )
end

function App:start()
    self:_headers()
    self.registry:scan_guilds()
    self.last_guild_scan = Clock.now()
    self:_register_hooks()

    self.scheduler:start(
        self.config.runtime.scheduler_interval_ms,
        function()
            self:_tick()
        end
    )

    FileIO.overwrite(
        self.paths.health,
        {
            "timestamp\tversion\tstatus",

            TSV.encode({
                Clock.now(),
                "0.8.0-dev-faz04",
                "STARTED"
            })
        }
    )

    self.status:build(
        nil,
        "PalTR Faz-04 oyuncu hasar korumasi baslatildi"
    )

    self.logger:info(
        "Faz-04 oyuncu hasar korumasi baslatildi"
    )

    self.logger:info(
        "Oyuncu hasar korumasi aktif"
    )
end

return App
