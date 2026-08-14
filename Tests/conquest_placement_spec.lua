package.path = table.concat({
    "Scripts/?.lua",
    "Scripts/?/init.lua",
    package.path
}, ";")

local Rules = require("PalTR.domain.conquest_rules")
local Conquest = require("PalTR.services.conquest_service")
local Result = require("PalTR.core.result")

local function equal(actual, expected, message)
    if actual ~= expected then
        error(message .. ": expected=" .. tostring(expected) ..
            " actual=" .. tostring(actual))
    end
end

local config = {
    territory_default_capital_radius_meters = 100,
    territory_default_outpost_radius_meters = 60,
    territory_node_min_distance_ratio = 0.55,
    territory_outpost_link_max_ratio = 0.90,
    territory_enemy_buffer_meters = 10,
    outpost_link_max_distance_meters = 1500
}
local capital = {
    node_id = "A_CAP", node_type = "CAPITAL",
    current_controller = "A", x = 0, y = 0, z = 0
}
local child = {
    node_id = "A_OUT", node_type = "OUTPOST",
    current_controller = "A", x = 100, y = 0, z = 0
}

equal(
    Rules.validate_node_placement(capital, child, { A_CAP = capital }, config).allow,
    true,
    "connected outpost accepted"
)
child.x = 40
equal(
    Rules.validate_node_placement(capital, child, { A_CAP = capital }, config).reason,
    "TERRITORY_NODE_TOO_CLOSE",
    "overlapping icons rejected"
)
child.x = 145
equal(
    Rules.validate_node_placement(capital, child, { A_CAP = capital }, config).reason,
    "OUTPOST_LINK_TOO_FAR",
    "disconnected outpost rejected"
)
child.x = 100
local enemy = {
    node_id = "B_CAP", node_type = "CAPITAL",
    current_controller = "B", x = 250, y = 0, z = 0
}
equal(
    Rules.validate_node_placement(
        capital,
        child,
        { A_CAP = capital, B_CAP = enemy },
        config
    ).reason,
    "ENEMY_TERRITORY_OVERLAP",
    "enemy territory buffer enforced"
)

local repository = {
    load_nodes = function() return {} end,
    load_edges = function() return {} end,
    load_campaigns = function() return {} end,
    load_occupations = function() return {} end,
    load_loot_manifests = function() return {} end,
    load_loot_items = function() return {} end,
    save_nodes = function() return Result.ok(true) end,
    save_edges = function() return Result.ok(true) end
}
local identity = { allowed = false }
function identity:has_identity() return self.allowed end
local service = Conquest.new({}, { conquest = config }, nil, nil, {
    repository = repository,
    guild_identity = identity
})
local registration = {
    node_id = "NEW_CAPITAL",
    guild_key = "A",
    node_type = "CAPITAL",
    actor_role = "LEADER",
    x = 0,
    y = 0,
    z = 0
}
config.operator_roles = { LEADER = true }
local missing_identity = service:register_node(registration)
equal(missing_identity.error.code, "GUILD_IDENTITY_REQUIRED",
    "identity required before first territory")
identity.allowed = true
equal(service:register_node(registration).ok, true,
    "identified guild registers valid capital")

print("conquest_placement_spec: ok")
