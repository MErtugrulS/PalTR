local Logger = require("PalTR.core.logger")
local Paths = require("PalTR.core.paths")
local Clock = require("PalTR.core.clock")
local FileIO = require("PalTR.storage.file_io")
local TSV = require("PalTR.storage.tsv")
local UE = require("PalTR.runtime.ue")
local HookRegistry = require("PalTR.runtime.hook_registry")
local StructureProbe = require("PalTR.runtime.structure_probe")
local RegistryService = require("PalTR.services.registry_service")
local DiplomacyService = require("PalTR.services.diplomacy_service")
local StatusService = require("PalTR.services.status_service")
local CommandService = require("PalTR.services.command_service")
local DamageObserver = require("PalTR.services.damage_observer")
local Scheduler = require("PalTR.services.scheduler")

local App = {}
App.__index = App

function App.new(config)
    local paths = Paths.new(config.data_root)
    local registry = RegistryService.new(
        paths, Logger.new("Registry")
    )
    local diplomacy = DiplomacyService.new(
        paths, config, Logger.new("Diplomacy")
    )
    local status = StatusService.new(paths, registry, diplomacy)

    return setmetatable({
        config = config,
        paths = paths,
        logger = Logger.new("App"),
        hooks = HookRegistry.new(Logger.new("Hooks")),
        registry = registry,
        diplomacy = diplomacy,
        status = status,
        commands = CommandService.new(
            paths, registry, diplomacy, status,
            Logger.new("Commands")
        ),
        damage = DamageObserver.new(
            paths.damage, registry, Logger.new("Damage")
        ),
        scheduler = Scheduler.new(Logger.new("Scheduler")),
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
        if file then file:close()
        else FileIO.overwrite(path, { header }) end
    end
end

function App:_register_hooks()
    self.hooks:register(
        "PlayerConnected",
        "/Script/Engine.PlayerController:ServerAcknowledgePossession",
        function(context, pawn)
            local player = self.registry:on_connected(context, pawn)
            self.registry:scan_guilds()
            self.status:build(player, "Oyuncu baglandi")
        end
    )

    self.hooks:register(
        "PlayerGuildMapped",
        "/Script/Pal.PalPlayerState:OnUpdatePlayerInfoInGuildBelongTo",
        function(context, guild, uid, _player_info)
            local player = self.registry:on_guild_update(
                context, guild, uid
            )
            if player then
                self.status:build(
                    player,
                    "Oyuncu-klan eslemesi guncellendi"
                )
            end
        end
    )

    self.hooks:register(
        "ChatCommand",
        "/Script/Pal.PalPlayerController:EnterChat_Receive",
        function(context, message, _chat_type)
            self.commands:on_chat(context, message)
        end
    )

    self.hooks:register(
        "PlayerDamagePassive",
        "/Script/Pal.PalPlayerCharacter:OnDamagePlayer_Server",
        function(context, damage_result)
            self.damage:on_player_damage(context, damage_result)
        end
    )

    if self.config.runtime.enable_structure_damage_probe then
        StructureProbe.register(
            self.hooks,
            self.paths.structure,
            Logger.new("StructureProbe")
        )
    end
end

function App:_tick()
    self.diplomacy:tick()

    if self.config.runtime.player_validity_poll then
        self.registry:poll_validity(function(player)
            FileIO.append(self.paths.events, TSV.encode({
                Clock.now(),
                "PLAYER_DISCONNECTED_POLL",
                player.guild_key,
                player.name
            }))
            self.status:build(player, "Oyuncu cevrimdisi algilandi")
        end)
    end

    local now = Clock.now()
    if now - self.last_guild_scan
        >= self.config.runtime.guild_scan_seconds then
        self.registry:scan_guilds()
        self.last_guild_scan = now
    end
end

function App:start()
    self:_headers()
    self.registry:scan_guilds()
    self.last_guild_scan = Clock.now()
    self:_register_hooks()

    self.scheduler:start(
        self.config.runtime.scheduler_interval_ms,
        function() self:_tick() end
    )

    FileIO.overwrite(self.paths.health, {
        "timestamp\tversion\tstatus",
        TSV.encode({ Clock.now(), "0.6.0-dev", "STARTED" })
    })

    self.status:build(nil, "PalTR pasif diplomasi alfa baslatildi")
    self.logger:info("Pasif diplomasi alfa baslatildi")
    self.logger:warn("Gercek hasar engelleme kapali")
end

return App
