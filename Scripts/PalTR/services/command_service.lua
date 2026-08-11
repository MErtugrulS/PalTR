local Parser = require("PalTR.domain.command_parser")
local States = require("PalTR.domain.states")
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

    PEACE_PENDING = "Baris teklifi",

    ALLIANCE_PENDING = "Ittifak teklifi",
    ALLIANCE = "Ittifak"
}

local SUCCESS_MESSAGES = {
    DECLARE_WAR =
        "Savas ilani kaydedildi. Hazirlik suresi basladi",

    CEASEFIRE =
        "Ateskes teklifi kaydedildi",

    BREAK_CEASEFIRE =
        "Ateskes bozuldu. Savas yeniden basladi",

    PEACE =
        "Baris teklifi kaydedildi",

    ALLIANCE =
        "Ittifak teklifi kaydedildi",

    ACCEPT = "Teklif kabul edildi",
    REJECT = "Teklif reddedildi",
    CANCEL = "Teklif iptal edildi",

    NEUTRALIZE =
        "Ittifak sona erdirildi"
}

local function guild_name(registry, guild_key)
    local guild = registry.guilds[guild_key]

    if guild and guild.name and guild.name ~= "" then
        return guild.name
    end

    return guild_key
end

local function format_duration(total_seconds)
    local seconds = math.max(
        0,
        math.floor(tonumber(total_seconds) or 0)
    )

    local days = math.floor(seconds / 86400)
    seconds = seconds % 86400

    local hours = math.floor(seconds / 3600)
    seconds = seconds % 3600

    local minutes = math.floor(seconds / 60)
    seconds = seconds % 60

    local parts = {}

    if days > 0 then
        table.insert(parts, tostring(days) .. " gun")
    end

    if hours > 0 then
        table.insert(parts, tostring(hours) .. " saat")
    end

    if minutes > 0 then
        table.insert(parts, tostring(minutes) .. " dk")
    end

    if #parts == 0 then
        table.insert(parts, tostring(seconds) .. " sn")
    end

    return table.concat(parts, " ")
end

function CommandService.new(
    paths,
    registry,
    diplomacy,
    status,
    logger
)
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

    FileIO.append(self.paths.responses, TSV.encode({
        Clock.now(),
        player and player.name or "",
        player and player.guild_key or "",
        raw,
        tostring(success),
        message
    }))

    self.status:build(player, message)
    self.logger:info("KOMUT_SONUC | " .. message)

    Announcer.send(controller, message, self.logger)
end

function CommandService:_announce_guild(guild_key, message)
    for _, player in pairs(
        self.registry.runtime_players or {}
    ) do
        if player.online
            and player.guild_key == guild_key
            and player.controller ~= nil then

            Announcer.send(
                player.controller,
                message,
                self.logger
            )
        end
    end
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
    local ok, error_message =
        self:_require_identity(player)

    if not ok then
        return false, error_message
    end

    if not player.is_master then
        return false,
            "Bu komutu yalnizca klan lideri kullanabilir"
    end

    return true
end

function CommandService:_target(player, query)
    local target, error_message =
        self.registry:resolve_guild(query)

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

function CommandService:_relation_entry(player, relation)
    local other_key

    if relation.guild_a == player.guild_key then
        other_key = relation.guild_b
    else
        other_key = relation.guild_a
    end

    local name = guild_name(self.registry, other_key)
    local state = STATE_LABELS[relation.state]
        or relation.state
    local now = Clock.now()

    if relation.state == States.WAR_PENDING
        and relation.active_at > now then

        state = state ..
            " (" ..
            format_duration(relation.active_at - now) ..
            ")"

    elseif relation.state == States.WAR
        and relation.active_at > 0 then

        state = state ..
            " (" ..
            format_duration(now - relation.active_at) ..
            ")"

    elseif relation.state == States.CEASEFIRE
        and relation.active_at > 0 then

        state = state ..
            " (" ..
            format_duration(now - relation.active_at) ..
            ")"

    elseif (relation.state == States.CEASEFIRE_PENDING
        or relation.state == States.PEACE_PENDING
        or relation.state == States.ALLIANCE_PENDING)
        and relation.expires_at > now then

        state = state ..
            " (" ..
            format_duration(relation.expires_at - now) ..
            ")"
    end

    return name .. "=" .. state
end

function CommandService:_relations_message(player)
    local ok, error_message =
        self:_require_identity(player)

    if not ok then
        return false, error_message
    end

    local relations =
        self.diplomacy:relations_for(player.guild_key)

    local messages = {}

    for _, relation in ipairs(relations) do
        table.insert(
            messages,
            self:_relation_entry(player, relation)
        )
    end

    table.sort(messages, function(first, second)
        return string.lower(first) < string.lower(second)
    end)

    if #messages == 0 then
        return true, "Iliskiler: Kayitli iliski yok"
    end

    return true,
        "Iliskiler: " .. table.concat(messages, " | ")
end

function CommandService:_status_message(player)
    local ok, error_message =
        self:_require_identity(player)

    if not ok then
        return false, error_message
    end

    local relation_ok, relation_message =
        self:_relations_message(player)

    if not relation_ok then
        return false, relation_message
    end

    local name = guild_name(
        self.registry,
        player.guild_key
    )

    local leader = player.is_master and "Evet" or "Hayir"

    return true,
        "Klan: " .. name ..
        " | Lider: " .. leader ..
        " | " .. relation_message
end

function CommandService:on_chat(
    controller_param,
    message_param
)
    local controller = UE.unwrap(controller_param)
    local message = UE.text(message_param)
    local parsed = Parser.parse(message)

    if not parsed.ok then
        return
    end

    local player =
        self.registry:find_by_controller(controller)

    local command = parsed.value

    if command.action == "HELP" then
        self:_respond(
            controller,
            player,
            command.raw,
            true,
            "!durum | !klanlar | !iliskiler | !yardim | " ..
            "!savas KLAN | !ateskes KLAN | " ..
            "!ateskesboz KLAN | !baris KLAN | " ..
            "!ittifak KLAN | !kabul KLAN | " ..
            "!reddet KLAN | !iptal KLAN | " ..
            "!tarafsiz KLAN"
        )
        return
    end

    if command.action == "STATUS" then
        local ok, response =
            self:_status_message(player)

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
        local ok, response =
            self:_relations_message(player)

        self:_respond(
            controller,
            player,
            command.raw,
            ok,
            response
        )
        return
    end

    local allowed, error_message =
        self:_require_master(player)

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

    local pending_state = nil

    if command.action == "ACCEPT" then
        local pending_relation =
            self.diplomacy:get(
                player.guild_key,
                target.key
            )

        if pending_relation then
            pending_state = pending_relation.state
        end
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

    elseif command.action == "BREAK_CEASEFIRE" then
        result = self.diplomacy:break_ceasefire(
            player.guild_key,
            target.key,
            player.name
        )

    elseif command.action == "PEACE" then
        result = self.diplomacy:request_peace(
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

    elseif command.action == "CANCEL" then
        result = self.diplomacy:cancel(
            player.guild_key,
            target.key,
            player.name
        )

    elseif command.action == "NEUTRALIZE" then
        result = self.diplomacy:return_neutral(
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
        return
    end

    if not result.ok then
        self:_respond(
            controller,
            player,
            command.raw,
            false,
            result.error.message
        )
        return
    end

    local success_message =
        SUCCESS_MESSAGES[command.action]
        or "Komut basariyla kaydedildi"

    self:_respond(
        controller,
        player,
        command.raw,
        true,
        success_message
    )

    local own_name = guild_name(
        self.registry,
        player.guild_key
    )

    local target_name = guild_name(
        self.registry,
        target.key
    )

    if command.action == "DECLARE_WAR" then
        local minutes =
            self.diplomacy.config.diplomacy
                .war_preparation_minutes

        self:_announce_guild(
            target.key,
            own_name ..
            " klani size savas ilan etti. Savas " ..
            tostring(minutes) ..
            " dakika sonra baslayacak."
        )

    elseif command.action == "CEASEFIRE" then
        self:_announce_guild(
            target.key,
            own_name ..
            " klani 12 saatlik ateskes teklif etti. " ..
            "!kabul " .. own_name ..
            " veya !reddet " .. own_name
        )

    elseif command.action == "PEACE" then
        self:_announce_guild(
            target.key,
            own_name ..
            " klani kalici baris teklif etti. " ..
            "!kabul " .. own_name ..
            " veya !reddet " .. own_name
        )

    elseif command.action == "BREAK_CEASEFIRE" then
        local message_text =
            own_name ..
            " klani ateskesi bozdu. " ..
            "Savas yeniden basladi."

        self:_announce_guild(
            player.guild_key,
            message_text
        )

        self:_announce_guild(
            target.key,
            message_text
        )

    elseif command.action == "ACCEPT" then
        local accepted_text =
            "Teklif kabul edildi"

        if pending_state == States.CEASEFIRE_PENDING then
            accepted_text =
                own_name .. " ile " .. target_name ..
                " arasinda 12 saatlik ateskes basladi."

        elseif pending_state == States.PEACE_PENDING then
            accepted_text =
                own_name .. " ile " .. target_name ..
                " arasindaki savas baris anlasmasiyla sona erdi."

        elseif pending_state == States.ALLIANCE_PENDING then
            accepted_text =
                own_name .. " ile " .. target_name ..
                " ittifak kurdu."
        end

        self:_announce_guild(
            player.guild_key,
            accepted_text
        )

        self:_announce_guild(
            target.key,
            accepted_text
        )

    elseif command.action == "REJECT" then
        self:_announce_guild(
            target.key,
            own_name ..
            " klani teklifinizi reddetti."
        )

    elseif command.action == "CANCEL" then
        self:_announce_guild(
            target.key,
            own_name ..
            " klani teklifini iptal etti."
        )

    elseif command.action == "NEUTRALIZE" then
        self:_announce_guild(
            target.key,
            own_name ..
            " klani ittifaktan ayrildi."
        )
    end
end

return CommandService
