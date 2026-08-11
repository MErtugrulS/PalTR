package.path = table.concat({
    "Scripts/?.lua",
    "Scripts/?/init.lua",
    package.path
}, ";")

local Rules = require("PalTR.domain.territory_rules")

local function equal(actual, expected, message)
    if actual ~= expected then
        error(message .. ": expected=" .. tostring(expected) ..
            " actual=" .. tostring(actual))
    end
end

local config = {
    territory_default_capital_radius_meters = 250,
    territory_default_outpost_radius_meters = 150,
    territory_exit_hysteresis_meters = 20
}
local nodes = {
    CAPITAL = {
        node_id = "CAPITAL", node_type = "CAPITAL",
        current_controller = "A", x = 0, y = 0
    },
    OUTPOST = {
        node_id = "OUTPOST", node_type = "OUTPOST",
        current_controller = "B", x = 200, y = 0,
        territory_radius_meters = 100
    }
}

equal(Rules.radius_for(nodes.CAPITAL, config), 250, "capital default radius")
equal(Rules.radius_for(nodes.OUTPOST, config), 100, "node override radius")
equal(Rules.resolve({ x = -200, y = 0 }, nodes, config).node_id,
    "CAPITAL", "inside capital")
equal(Rules.resolve({ x = 150, y = 0 }, nodes, config).node_id,
    "OUTPOST", "overlap selects normalized nearest")
equal(Rules.resolve({ x = 90, y = 0 }, nodes, config, "OUTPOST").node_id,
    "OUTPOST", "hysteresis keeps current territory")
equal(Rules.resolve({ x = 79, y = 0 }, nodes, config, "OUTPOST").node_id,
    "CAPITAL", "hysteresis eventually releases territory")
equal(Rules.resolve({ x = 500, y = 0 }, nodes, config), nil,
    "outside all territories")
equal(Rules.radius_for({ node_type = "OUTPOST", territory_radius_meters = -1 }, config),
    0, "negative override fails closed")

print("territory_rules_spec: ok")
