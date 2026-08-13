package.path = table.concat({
    "Scripts/?.lua",
    "Scripts/?/init.lua",
    package.path
}, ";")

local Sampler = require("PalTR.runtime.territory_terrain_sampler")

local function equal(actual, expected, message)
    if actual ~= expected then
        error(message .. ": expected=" .. tostring(expected)
            .. " actual=" .. tostring(actual))
    end
end

local calls = 0
local sampler = Sampler.new({
    world_units_per_meter = 100,
    territory_terrain_max_traces_per_pass = 2
}, {
    context = {},
    trace = function(_, x, y)
        calls = calls + 1
        return {
            height = x * 0.5 + y * 0.25,
            surface = x < 0 and "water" or "land"
        }
    end
})

sampler:begin_pass()
equal(sampler:sample(10, 20).height, 10, "height sample returned")
equal(sampler:sample(10, 20).height, 10, "cached height returned")
equal(calls, 1, "cache avoids repeated line trace")
equal(sampler:sample(-5, 0).surface, "water", "surface preserved")
equal(sampler:sample(20, 0), nil, "trace budget fails closed")

print("territory_terrain_sampler_spec: ok")
