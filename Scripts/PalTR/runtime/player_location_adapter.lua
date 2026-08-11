local UE = require("PalTR.runtime.ue")

local Adapter = {}

local function coordinate(ue, vector, field)
    return tonumber(ue.unwrap(ue.read(vector, field)))
end

function Adapter.read(player, config, ue)
    ue = ue or UE
    local scale = tonumber(config and config.world_units_per_meter) or 0
    if scale <= 0 then return nil end

    local ok, vector = ue.call(
        player and player.pawn,
        "K2_GetActorLocation"
    )
    vector = ue.unwrap(vector)
    if not ok or vector == nil then return nil end

    local x = coordinate(ue, vector, "X")
    local y = coordinate(ue, vector, "Y")
    local z = coordinate(ue, vector, "Z")
    if x == nil or y == nil or z == nil then return nil end

    return {
        x = x / scale,
        y = y / scale,
        z = z / scale
    }
end

return Adapter
