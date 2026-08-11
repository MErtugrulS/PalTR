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

    local player_state = self.ue.unwrap(
        self.ue.read(controller, "PlayerState")
    )
    if not self.ue.valid(player_state) then
        return Result.err("PLAYER_STATE_UNAVAILABLE", "Oyuncu durumu bulunamadi")
    end

    local ok_inventory, inventory = self.ue.call(
        player_state,
        "GetInventoryData"
    )
    inventory = self.ue.unwrap(inventory)
    if not ok_inventory or not self.ue.valid(inventory) then
        return Result.err("INVENTORY_UNAVAILABLE", "Oyuncu envanteri bulunamadi")
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
        player_state,
        "RequestSpawnMonsterForPlayer",
        tostring(config.pal_id or ""),
        tonumber(config.pal_count) or 1,
        tonumber(config.pal_level) or 1
    )
    local ok_weapon = self.ue.call(
        inventory,
        "AddItem_ServerInternal",
        tostring(config.weapon_item_id or ""),
        tonumber(config.weapon_count) or 1,
        false,
        0.0,
        true
    )
    local ok_ammo = self.ue.call(
        inventory,
        "AddItem_ServerInternal",
        tostring(config.ammo_item_id or ""),
        tonumber(config.ammo_count) or 1,
        false,
        0.0,
        true
    )

    if not ok_exp or not ok_weight or not ok_pal or not ok_weapon or not ok_ammo then
        return Result.err("TEST_KIT_GRANT_FAILED", "Test kitinin bir bolumu verilemedi")
    end

    return Result.ok(true)
end

return Adapter
