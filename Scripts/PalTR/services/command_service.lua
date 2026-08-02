local Parser = require("PalTR.domain.command_parser")
local FileIO = require("PalTR.storage.file_io")
local TSV = require("PalTR.storage.tsv")
local Clock = require("PalTR.core.clock")
local UE = require("PalTR.runtime.ue")
local Announcer = require("PalTR.runtime.announcer")

local CommandService = {}
CommandService.__index = CommandService

function CommandService.new(paths, registry, diplomacy, status, logger)
    return setmetatable({
        paths = paths,
        registry = registry,
        diplomacy = diplomacy,
        status = status,
        logger = logger,
        last_response_key = "",
        last_response_at = 0
    }, CommandService)
end

function CommandService:_respond(
    controller,
    player,
    raw,
    success,
    message
)
    local now = os.time()
    local response_key = table.concat({
        tostring(controller),
        tostring(raw),
        tostring(success),
        tostring(message)
    }, "|")

    -- EnterChat hook ayni olayi iki kez bildirirse ikinci cevabi engeller.
    if self.last_response_key == response_key
        and self.last_response_at == now then
        return
    end

    self.last_response_key = response_key
    self.last_response_at = now

    local line = TSV.encode({
        Clock.now(),
        player and player.name or "",
        player and player.guild_key or "",
        raw,
        tostring(success),
        message
    })

    FileIO.append(self.paths.responses, line)
    self.status:build(player, message)
    self.logger:info("KOMUT_SONUC | " .. message)

    Announcer.send(controller, message, self.logger)
end

function CommandService:_require_identity(player)
    if not player then return false, "Oyuncu kaydi bulunamadi" end
    if player.guild_key == "" then
        return false, "Klan eslemesi henuz hazir degil"
    end
    return true
end

function CommandService:_require_master(player)
    local ok, error_message = self:_require_identity(player)
    if not ok then return false, error_message end
    if not player.is_master then
        return false, "Bu komutu yalnizca klan lideri kullanabilir"
    end
    return true
end

function CommandService:_target(player, query)
    local target, error_message = self.registry:resolve_guild(query)
    if not target then return nil, error_message end
    if target.key == player.guild_key then
        return nil, "Kendi klanin hedeflenemez"
    end
    return target
end

function CommandService:on_chat(controller_param, message_param)
    local controller = UE.unwrap(controller_param)
    local message = UE.text(message_param)
    local parsed = Parser.parse(message)

    if not parsed.ok then return end

    local player = self.registry:find_by_controller(controller)
    local command = parsed.value

    if command.action == "TEST" then
        self:_respond(
            controller,
            player,
            command.raw,
            true,
            "[FAZ-01] SOHBET KANALI CALISIYOR"
        )
        return
    end

    if command.action == "HELP" then
        self:_respond(
            controller,
            player,
            command.raw,
            true,
            "!durum | !klanlar | !yardim | !savas KLAN | " ..
            "!ateskes KLAN | !ittifak KLAN | !kabul KLAN | " ..
            "!reddet KLAN"
        )
        return
    end

    if command.action == "STATUS" then
        local ok, error_message = self:_require_identity(player)
        self:_respond(
            controller,
            player,
            command.raw,
            ok,
            ok and "Durum dosyasi guncellendi" or error_message
        )
        return
    end

    if command.action == "GUILDS" then
        self:_respond(
            controller,
            player,
            command.raw,
            true,
            "Klan listesi durum dosyasina yazildi"
        )
        return
    end

    local allowed, error_message = self:_require_master(player)
    if not allowed then
        self:_respond(
            controller,
            player,
            command.raw,
            false,
            error_message
        )
        return
    end

    local target, target_error = self:_target(
        player,
        command.target
    )

    if not target then
        self:_respond(
            controller,
            player,
            command.raw,
            false,
            target_error
        )
        return
    end

    local result

    if command.action == "DECLARE_WAR" then
        result = self.diplomacy:declare_war(
            player.guild_key,
            target.key,
            player.name
        )
    elseif command.action == "CEASEFIRE" then
        result = self.diplomacy:request_ceasefire(
            player.guild_key,
            target.key,
            player.name
        )
    elseif command.action == "ALLIANCE" then
        result = self.diplomacy:request_alliance(
            player.guild_key,
            target.key,
            player.name
        )
    elseif command.action == "ACCEPT" then
        result = self.diplomacy:accept(
            player.guild_key,
            target.key,
            player.name
        )
    elseif command.action == "REJECT" then
        result = self.diplomacy:reject(
            player.guild_key,
            target.key,
            player.name
        )
    end

    if not result then
        self:_respond(
            controller,
            player,
            command.raw,
            false,
            "Komut uygulanamadi"
        )
    elseif result.ok then
        self:_respond(
            controller,
            player,
            command.raw,
            true,
            command.action .. " basariyla kaydedildi"
        )
    else
        self:_respond(
            controller,
            player,
            command.raw,
            false,
            result.error.message
        )
    end
end

return CommandService
