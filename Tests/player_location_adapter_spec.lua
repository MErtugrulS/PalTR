package.path = table.concat({
    "Scripts/?.lua",
    "Scripts/?/init.lua",
    package.path
}, ";")

local Adapter = require("PalTR.runtime.player_location_adapter")

local function equal(actual, expected, message)
    if actual ~= expected then
        error(message .. ": expected=" .. tostring(expected) ..
            " actual=" .. tostring(actual))
    end
end

local ue = {
    call = function(object, method)
        equal(method, "K2_GetActorLocation", "verified location method")
        return object ~= nil, { X = 12500, Y = -2500, Z = 300 }
    end,
    unwrap = function(value) return value end,
    read = function(object, field) return object[field] end
}

local location = Adapter.read(
    { pawn = {} },
    { world_units_per_meter = 100 },
    ue
)
equal(location.x, 125, "x converted to meters")
equal(location.y, -25, "y converted to meters")
equal(location.z, 3, "z converted to meters")
equal(Adapter.read({ pawn = {} }, { world_units_per_meter = 0 }, ue), nil,
    "invalid scale fails closed")

print("player_location_adapter_spec: ok")
