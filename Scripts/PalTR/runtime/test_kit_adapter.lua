local Result = require("PalTR.core.result")
local UE = require("PalTR.runtime.ue")

local Adapter = {}
Adapter.__index = Adapter

function Adapter.new(ue)
    return setmetatable({ ue = ue or UE }, Adapter)
end

function Adapter:grant(controller, config)
    config = config or {}

    local define = self.ue.find_object(
        "/Script/Pal.Default__PalDefine"
    )
    if not self.ue.valid(define) then
        return Result.err("PAL_DEFINE_UNAVAILABLE", "Agirlik stat tanimi bulunamadi")
    end

    local ok_weight_name, weight_name = self.ue.call(
        define,
        "StatusPointName_AddMaxInventoryWeight"
    )
    if not ok_weight_name or weight_name == nil then
        return Result.err("WEIGHT_STAT_UNAVAILABLE", "Agirlik stat adi cozumlenemedi")
    end

    local cheat_manager = self.ue.unwrap(
        self.ue.read(controller, "CheatManager")
    )
    if not self.ue.valid(cheat_manager) then
        self.ue.call(controller, "EnableCheats")
        cheat_manager = self.ue.unwrap(
            self.ue.read(controller, "CheatManager")
        )
    end
    if not self.ue.valid(cheat_manager) then
        return Result.err("CHEAT_MANAGER_UNAVAILABLE", "Test kiti cheat yoneticisi acilamadi")
    end

    local ok_exp = self.ue.call(
        controller,
        "Debug_AddPlayerExp_ToServer",
        tonumber(config.player_exp) or 0
    )
    local ok_weight = self.ue.call(
        controller,
        "Debug_SetStatusPoint_ToServer",
        weight_name,
        tonumber(config.weight_status_level) or 0
    )
    local ok_pal = self.ue.call(
        cheat_manager,
        "SpawnMonsterForPlayer",
        tostring(config.pal_id or ""),
        tonumber(config.pal_count) or 1,
        tonumber(config.pal_level) or 1
    )
    local ok_weapon = self.ue.call(
        cheat_manager,
        "GetItem",
        tostring(config.weapon_item_id or ""),
        tonumber(config.weapon_count) or 1
    )
    local ok_ammo = self.ue.call(
        cheat_manager,
        "GetItem",
        tostring(config.ammo_item_id or ""),
        tonumber(config.ammo_count) or 1
    )

    if not ok_exp or not ok_weight or not ok_pal or not ok_weapon or not ok_ammo then
        return Result.err("TEST_KIT_GRANT_FAILED", "Test kitinin bir bolumu verilemedi")
    end

    return Result.ok(true)
end

return Adapter
