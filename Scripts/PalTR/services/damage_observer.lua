local UE = require("PalTR.runtime.ue")
local FileIO = require("PalTR.storage.file_io")
local TSV = require("PalTR.storage.tsv")
local Clock = require("PalTR.core.clock")

local Observer = {}
Observer.__index = Observer

function Observer.new(path, registry, logger)
    return setmetatable({
        path = path,
        registry = registry,
        logger = logger
    }, Observer)
end

function Observer:on_player_damage(context, result_param)
    local pawn = UE.unwrap(context)
    local result = UE.unwrap(result_param)

    local target_player = nil
    local pawn_path = UE.full_name(pawn)
    for _, player in pairs(self.registry.runtime_players) do
        if player.pawn_path == pawn_path then
            target_player = player
            break
        end
    end

    local fields = {}
    for _, field in ipairs({
        "Damage", "DamageAmount", "FinalDamage",
        "Attacker", "DamageCauser", "Instigator",
        "AttackerPlayerUId", "TargetPlayerUId",
        "AttackType", "DamageType", "IsDead"
    }) do
        local value = UE.read(result, field)
        local rendered = UE.text(value)
        if rendered ~= "" then
            table.insert(fields, field .. "=" .. rendered)
        end
    end

    FileIO.append(self.path, TSV.encode({
        Clock.now(),
        pawn_path,
        target_player and target_player.name or "",
        target_player and target_player.guild_key or "",
        table.concat(fields, ";")
    }))

    self.logger:info(
        "Pasif oyuncu hasari kaydedildi: " ..
        (target_player and target_player.name or pawn_path)
    )
end

return Observer
