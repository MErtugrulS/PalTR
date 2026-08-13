local FileIO = require("PalTR.storage.file_io")
local Clock = require("PalTR.core.clock")
local Tables = require("PalTR.core.table_utils")
local Result = require("PalTR.core.result")

local Status = {}
Status.__index = Status

function Status.new(paths, registry, diplomacy, logger)
    return setmetatable({
        paths = paths,
        registry = registry,
        diplomacy = diplomacy,
        logger = logger
    }, Status)
end

function Status:build(player, response)
    local lines = {
        "PalTR Modu - Sunucu Durumu",
        "==================================",
        "Guncelleme: " .. os.date("%Y-%m-%d %H:%M:%S", Clock.now()),
        "",
        "SON KOMUT",
        response or "Henuz komut yok.",
        "",
        "OYUNCU",
        "Ad: " .. (player and player.name or ""),
        "Klan: " .. (player and player.guild_key or ""),
        "Rol: " .. tostring(player and player.role or ""),
        "Lider: " .. tostring(player and player.is_master or false),
        "",
        "KLANLAR"
    }

    for _, key in ipairs(Tables.sorted_keys(self.registry.guilds)) do
        local guild = self.registry.guilds[key]
        table.insert(lines, "- " .. guild.name .. " | " .. guild.key)
    end

    table.insert(lines, "")
    table.insert(lines, "DIPLOMASI")

    local own = player and player.guild_key or ""
    local relations = own ~= "" and self.diplomacy:relations_for(own) or {}

    if #relations == 0 then
        table.insert(lines, "Kayitli iliski yok.")
    else
        for _, relation in ipairs(relations) do
            local other = relation.guild_a == own
                and relation.guild_b or relation.guild_a
            local other_name = self.registry.guilds[other]
                and self.registry.guilds[other].name or other
            table.insert(lines,
                "- " .. other_name .. ": " .. relation.state ..
                " | aktif=" .. tostring(relation.active_at) ..
                " | bitis=" .. tostring(relation.expires_at)
            )
        end
    end

    local result = FileIO.overwrite(self.paths.latest_status, lines)
    if not result.ok and self.logger then
        self.logger:error(
            "STATUS_WRITE_FAILED | " .. Result.describe(result)
        )
    end
    return result
end

return Status
