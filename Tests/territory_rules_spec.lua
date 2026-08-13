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
    territory_exit_hysteresis_meters = 20,
    territory_border_irregularity = 0.06,
    territory_boundary_sample_meters = 8,
    territory_boundary_max_cells = 50000
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
equal(Rules.resolve({ x = 95, y = 0 }, nodes, config, "OUTPOST").node_id,
    "OUTPOST", "hysteresis keeps current territory")
equal(Rules.resolve({ x = 70, y = 0 }, nodes, config, "OUTPOST").node_id,
    "CAPITAL", "hysteresis eventually releases territory")
equal(Rules.resolve({ x = 500, y = 0 }, nodes, config), nil,
    "outside all territories")
equal(Rules.radius_for({ node_type = "OUTPOST", territory_radius_meters = -1 }, config),
    0, "negative override fails closed")

local east_radius = Rules.organic_radius_for(nodes.CAPITAL, config, 0)
local north_radius = Rules.organic_radius_for(nodes.CAPITAL, config, math.pi / 2)
equal(east_radius ~= north_radius, true, "organic edge is not a flat circle")
equal(east_radius > 195 and east_radius < 305, true,
    "organic edge preserves configured area budget")

local union_nodes = {
    A1 = {
        node_id = "A1", node_type = "OUTPOST", current_controller = "A",
        x = 0, y = 0, territory_radius_meters = 100
    },
    A2 = {
        node_id = "A2", node_type = "OUTPOST", current_controller = "A",
        x = 150, y = 0, territory_radius_meters = 100
    },
    A3 = {
        node_id = "A3", node_type = "OUTPOST", current_controller = "A",
        x = 500, y = 0, territory_radius_meters = 100
    }
}
local atlas = Rules.build_atlas(union_nodes, config)
equal(#atlas.components, 2,
    "only physically overlapping same-guild areas merge")
equal(Rules.contains(atlas.components[1], { x = 0, y = 0 }), true,
    "merged polygon contains first node center")
local resolved_union = Rules.resolve(
    { x = 75, y = 0 }, union_nodes, config, nil, atlas
)
equal(resolved_union.current_controller, "A",
    "mechanics consume the rendered atlas")

local deterministic = Rules.build_atlas(union_nodes, config)
equal(#deterministic.components[1].points, #atlas.components[1].points,
    "atlas point count is deterministic")
equal(deterministic.components[1].points[1].x, atlas.components[1].points[1].x,
    "atlas coordinates are deterministic")

local terrain_atlas = Rules.build_atlas(union_nodes, config, function(x, y)
    return {
        height = 30 * math.sin(x / 45) + 12 * math.cos(y / 28),
        surface = x < -65 and "water" or "land"
    }
end)
equal(terrain_atlas.components[1].terrain_conformed, true,
    "available terrain samples conform the political contour")
equal(Rules.contains(terrain_atlas.components[1], { x = 0, y = 0 }), true,
    "terrain-conformed visible polygon remains the mechanical boundary")

print("territory_rules_spec: ok")
