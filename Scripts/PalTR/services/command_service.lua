local Parser = require("PalTR.domain.command_parser")
local FileIO = require("PalTR.storage.file_io")
local TSV = require("PalTR.storage.tsv")
local Clock = require("PalTR.core.clock")
local UE = require("PalTR.runtime.ue")
local Announcer = require("PalTR.runtime.announcer")

local CommandService = {}
CommandService.__index = CommandService

local STATE_LABELS = {
    NEUTRAL = "Tarafsiz",
    WAR_PENDING = "Savas hazirligi",
    WAR = "Savas",
    CEASEFIRE_PENDING = "Ateskes teklifi",
    CEASEFIRE = "Ateskes",
    ALLIANCE_PENDING = "Ittifak teklifi",
    ALLIANCE = "Ittifak"
}

local SUCCESS_MESSAGES = {
    DECLARE_WAR = "Savas ilani kaydedildi",
    CEASEFIRE = "Ateskes teklifi kaydedildi",
    ALLIANCE = "Ittifak teklifi kaydedildi",
    ACCEPT = "Teklif kabul edildi",
    REJECT = "Teklif reddedildi"
}

local function guild_name(registry, guild_key)
    local guild = registry.guilds[guild_key]

    if guild and guild.name and guild.name ~= "" then
        return guild.name
    end

    return guild_key
end

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
    if not player then
        return false, "Oyuncu kaydi bulunamadi"
    end

    if player.guild_key == "" then
        return false, "Klan eslemesi henuz hazir degil"
    end

    return true
end

function CommandService:_require_master(player)
    local ok, error_message = self:_require_identity(player)

    if not ok then
        return false, error_message
    end

    if not player.is_master then
        return false, "Bu komutu yalnizca klan lideri kullanabilir"
    end

    return true
end

function CommandService:_target(player, query)
    local target, error_message = self.registry:resolve_guild(query)

    if not target then
        return nil, error_message
    end

    if target.key == player.guild_key then
        return nil, "Kendi klanin hedeflenemez"
    end

    return target
end

function CommandService:_guilds_message()
    local names = {}

    for _, guild in pairs(self.registry.guilds or {}) do
        if guild.name and guild.name ~= "" then
            table.insert(names, guild.name)
        end
    end

    table.sort(names, function(first, second)
        return string.lower(first) < string.lower(second)
    end)

    if #names == 0 then
        return "Kayitli klan bulunamadi"
    end

    return "Klanlar: " .. table.concat(names, ", ")
end

function CommandService:_relations_message(player)
    local ok, error_message = self:_require_identity(player)

    if not ok then
        return false, error_message
    end

    local relations = self.diplomacy:relations_for(player.guild_key)
    local messages = {}

    for _, relation in ipairs(relations) do
        local other_key

        if relation.guild_a == player.guild_key then
            other_key = relation.guild_b
        else
            other_key = relation.guild_a
        end

        local name = guild_name(self.registry, other_key)
        local state = STATE_LABELS[relation.state] or relation.state

        table.insert(messages, name .. "=" .. state)
    end

    table.sort(messages, function(first, second)
        return string.lower(first) < string.lower(second)
    end)

    if #messages == 0 then
        return true, "Iliskiler: Kayitli iliski yok"
    end

    return true, "Iliskiler: " .. table.concat(messages, " | ")
end

function CommandService:_status_message(player)
    local ok, error_message = self:_require_identity(player)

    if not ok then
        return false, error_message
    end

    local relation_ok, relation_message = self:_relations_message(player)

    if not relation_ok then
        return false, relation_message
    end

    local name = guild_name(self.registry, player.guild_key)
    local leader = player.is_master and "Evet" or "Hayir"

    return true,
        "Klan: " .. name ..
        " | Lider: " .. leader ..
        " | " .. relation_message
end

function CommandService:on_chat(controller_param, message_param)
    local controller = UE.unwrap(controller_param)
    local message = UE.text(message_param)
    local parsed = Parser.parse(message)

    if not parsed.ok then
        return
    end

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
            "!durum | !klanlar | !iliskiler | !yardim | " ..
            "!savas KLAN | !ateskes KLAN | !ittifak KLAN | " ..
            "!kabul KLAN | !reddet KLAN"
        )
        return
    end

    if command.action == "STATUS" then
        local ok, response = self:_status_message(player)

        self:_respond(
            controller,
            player,
            command.raw,
            ok,
            response
        )
        return
    end

    if command.action == "GUILDS" then
        self:_respond(
            controller,
            player,
            command.raw,
            true,
            self:_guilds_message()
        )
        return
    end

    if command.action == "RELATIONS" then
        local ok, response = self:_relations_message(player)

        self:_respond(
            controller,
            player,
            command.raw,
            ok,
            response
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
            SUCCESS_MESSAGES[command.action]
                or "Komut basariyla kaydedildi"
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