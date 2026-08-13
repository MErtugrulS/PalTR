local Logger = require("PalTR.core.logger")
local Version = require("PalTR.core.version")
local Paths = require("PalTR.core.paths")
local Clock = require("PalTR.core.clock")
local FileIO = require("PalTR.storage.file_io")
local TSV = require("PalTR.storage.tsv")
local Result = require("PalTR.core.result")
local HookRegistry = require("PalTR.runtime.hook_registry")
local Announcer = require("PalTR.runtime.announcer")
local RegistryService = require("PalTR.services.registry_service")
local DiplomacyService = require("PalTR.services.diplomacy_service")
local StatusService = require("PalTR.services.status_service")
local CommandService = require("PalTR.services.command_service")
local DamageObserver = require("PalTR.services.damage_observer")
local DamagePolicy = require("PalTR.services.damage_policy")
local ProtectionService = require("PalTR.services.protection_service")
local ConquestService = require("PalTR.services.conquest_service")
local TerritoryService = require("PalTR.services.territory_service")
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
        diplomacy,
        Logger.new("Status")
    )

    local damage_policy = DamagePolicy.new(
        config,
        diplomacy
    )

    local protection = ProtectionService.new(
        paths,
        config,
        registry,
        Logger.new("Protection")
    )

    local conquest = ConquestService.new(
        paths,
        config,
        diplomacy,
        Logger.new("Conquest")
    )

    local territory = TerritoryService.new(
        paths,
        config,
        registry,
        conquest,
        Logger.new("Territory")
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
        protection = protection,
        conquest = conquest,
        territory = territory,

        commands = CommandService.new(
            paths,
            registry,
            diplomacy,
            status,
            Logger.new("Commands"),
            conquest
        ),

        damage = DamageObserver.new(
            paths.damage,
            registry,
            damage_policy,
            Logger.new("Damage"),
            {
                audit_enabled = config.runtime.enable_damage_audit == true
            }
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

        [self.paths.protection] =
            "guild_key\tonline_count\tlast_online_at\tlast_hostile_at\tprotected_at\tprotected\treason",

        [self.paths.protection_activity] =
            "guild_key\tlast_hostile_at",

        [self.paths.conquest_nodes] =
            "node_id\tguild_key\tnode_type\tflag_reference\tlocation_x\tlocation_y\tlocation_z\tparent_node_id\tstate\toriginal_owner\tcurrent_controller\tcreated_at\tupdated_at\tflag_state\tlegacy_flag_reference\tdisplay_name\tterritory_radius_meters",

        [self.paths.conquest_edges] =
            "edge_id\tnode_a\tnode_b\tcreated_at",

        [self.paths.conquest_campaigns] =
            "campaign_id\twar_id\tattacker_guild\tdefender_guild\tstate\tactive_target_node_id\tsiege_camp_reference\tsiege_x\tsiege_y\tsiege_z\trearm_until\tprevious_relation_state\tcreated_at\tupdated_at",

        [self.paths.conquest_occupations] =
            "node_id\toriginal_owner\toccupying_guild\twar_id\tstate\tprevious_state\toccupation_started_at\tremaining_seconds\tlast_resumed_at\tloot_manifest_id\tfrontline_state\tupdated_at\tcounter_flag_reference\tcounter_remaining_seconds\tcounter_last_resumed_at\tcounter_flag_x\tcounter_flag_y\tcounter_flag_z",

        [self.paths.conquest_loot] =
            "manifest_id\tnode_id\twar_id\towner_guild\tstate\tcreated_at\textracted_at",

        [self.paths.conquest_loot_items] =
            "item_key\tmanifest_id\titem_id\titem_selector\tquantity\ttier\tcategory",

        [self.paths.conquest_events] =
            "timestamp\tmarker\tdetail",

        [self.paths.conquest_damage_policy] =
            "flag_reference\tnode_id\towner_guild\tallowed_attacker_guild",

        [self.paths.conquest_zone_policy] =
            "node_id\towner_guild\tallowed_attacker_guild\tcenter_x_world\tcenter_y_world\tcenter_z_world\tradius_world",

        [self.paths.territory_snapshot] =
            "node_id\tdisplay_name\tnode_type\tcontroller_guild\tcontroller_name\tcenter_x_meters\tcenter_y_meters\tcenter_z_meters\tradius_meters\tstate\tflag_state",

        [self.paths.conquest_runtime_events] =
            "timestamp\tmarker\tflag_reference",

        [self.paths.relations] =
            "pair_key\tguild_a\tguild_b\tstate\tprevious_state\trequested_by\taccepted_by\tcreated_at\tupdated_at\tactive_at\texpires_at\tnote",

        [self.paths.events] =
            "timestamp\tevent_type\tpair_key\tdetail",

        [self.paths.responses] =
            "timestamp\tplayer_name\tguild_key\tcommand\tsuccess\tmessage",

        [self.paths.health] =
            "timestamp\tversion\tstatus"
    }

    if self.config.runtime.enable_damage_audit == true then
        files[self.paths.damage] =
            "timestamp\ttarget_path\tplayer_name\tguild_key\tdetail"
    end

    for path, header in pairs(files) do
        local file = io.open(path, "r")

        if file then
            file:close()
        else
            local created = FileIO.overwrite(path, { header })
            if not created.ok then return created end
        end
    end

    return { ok = true }
end

function App:_guild_name(guild_key)
    local guild = self.registry.guilds[guild_key]

    if guild and guild.name and guild.name ~= "" then
        return guild.name
    end

    return guild_key
end

function App:_event(marker, pair_key, detail)
    local result = FileIO.append(
        self.paths.events,
        TSV.encode({
            Clock.now(),
            marker or "",
            pair_key or "",
            detail or ""
        })
    )
    if not result.ok then
        self.logger:error(
            "APP_EVENT_WRITE_FAILED | " .. Result.describe(result)
        )
    end
    return result
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

        elseif event.name == "CEASEFIRE_MADE_INDEFINITE" then
            self.logger:info(
                "Eski sureli ateskes suresiz hale getirildi: " ..
                tostring(relation.key)
            )
        end
    end
end

function App:_register_hooks()
    local registered = true

    registered = self.hooks:register(
        "PlayerConnected",
        "/Script/Engine.PlayerController:ServerAcknowledgePossession",
        function(context, pawn)
            local player =
                self.registry:on_connected(
                    context,
                    pawn
                )

            self.registry:scan_guilds()
            self.protection:refresh()

            self.status:build(
                player,
                "Oyuncu baglandi"
            )
        end
    ) and registered

    registered = self.hooks:register(
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
                self.protection:refresh()

                self.status:build(
                    player,
                    "Oyuncu-klan eslemesi guncellendi"
                )
            end
        end
    ) and registered

    registered = self.hooks:register(
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
    ) and registered

    registered = self.hooks:register(
        "EnemyPlayerDamageEnforcement",
        "/Script/Pal.PalPlayerController:DamageReactionComponent_ProcessDamage_ToServer_ToEnemyPlayer",
        function(context, info, defender)
            self.damage:on_enemy_player_damage_request(
                context,
                info,
                defender
            )
        end
    ) and registered

    return registered
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
                self:_event(
                    "PLAYER_DISCONNECTED_POLL",
                    player.guild_key,
                    player.name
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

    self.protection:refresh(now)

    local runtime_events = self.conquest:process_runtime_events(now)

    if not runtime_events.ok then
        self.logger:error(
            "FAZ05_RUNTIME_EVENT_FAILED | " ..
            Result.describe(runtime_events)
        )
    end

    local conquest_result = self.conquest:tick(now)

    if not conquest_result.ok then
        self.logger:error(
            "FAZ05_CONQUEST_TICK_FAILED | " ..
            Result.describe(conquest_result)
        )
    end

    local policy_result = self.conquest:write_damage_policy(now)

    if not policy_result.ok then
        self.logger:error(
            "FAZ05_DAMAGE_POLICY_WRITE_FAILED | " ..
            Result.describe(policy_result)
        )
    end

    local territory_result = self.territory:refresh()
    if not territory_result.ok then
        self.logger:error(
            "FAZ05_TERRITORY_REFRESH_FAILED | " ..
            Result.describe(territory_result)
        )
    end
end

function App:start()
    local headers = self:_headers()
    if not headers.ok then
        error(
            "Zorunlu veri dosyalari hazirlanamadi: " ..
            tostring(headers.error and headers.error.message or "")
        )
    end
    local registry_scan = self.registry:scan_guilds()
    if not registry_scan.ok then
        error("Klan registry ilk taramasi kaydedilemedi")
    end
    self.last_guild_scan = Clock.now()
    if not self.protection:refresh(self.last_guild_scan) then
        error("Offline koruma snapshot'i baslatilamadi")
    end
    local initial_policy = self.conquest:write_damage_policy(
        self.last_guild_scan
    )

    if not initial_policy.ok then
        error(
            "Fetih hasar politikasi baslatilamadi: " ..
            tostring(
                initial_policy.error
                and initial_policy.error.message
                or ""
            )
        )
    end
    local initial_territory = self.territory:refresh()
    if not initial_territory.ok then
        error(
            "Bolge snapshot'i baslatilamadi: " ..
            tostring(
                initial_territory.error
                and initial_territory.error.message
                or ""
            )
        )
    end
    if not self:_register_hooks() then
        error("Zorunlu PalTR hook'larindan biri kaydedilemedi")
    end

    local scheduler_started = self.scheduler:start(
        self.config.runtime.scheduler_interval_ms,
        function()
            self:_tick()
        end
    )
    if not scheduler_started then
        error("PalTR zamanlayicisi baslatilamadi")
    end

    local health = FileIO.overwrite(
        self.paths.health,
        {
            "timestamp\tversion\tstatus",

            TSV.encode({
                Clock.now(),
                Version.version,
                "STARTED"
            })
        }
    )
    if not health.ok then
        error(
            "Health dosyasi yazilamadi: " ..
            tostring(health.error and health.error.message or "")
        )
    end

    self.status:build(
        nil,
        "PalTR Faz-05 fetih domain servisi baslatildi"
    )

    self.logger:info(
        "FAZ05_RULES_LOADED | fetih domain ve persistence servisi aktif"
    )

    self.logger:info(
        "Offline koruma snapshot servisi aktif"
    )
end

return App
