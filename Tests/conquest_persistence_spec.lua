package.path = table.concat({
    "Scripts/?.lua",
    "Scripts/?/init.lua",
    package.path
}, ";")

local Conquest = require("PalTR.services.conquest_service")
local Result = require("PalTR.core.result")
local States = require("PalTR.domain.conquest_states")

local function equal(actual, expected, message)
    if actual ~= expected then
        error(message .. ": expected=" .. tostring(expected)
            .. " actual=" .. tostring(actual))
    end
end

local function copy(source)
    local result = {}
    for key, value in pairs(source or {}) do
        result[key] = type(value) == "table" and copy(value) or value
    end
    return result
end

local capital = {
    key = "CAPITAL",
    node_id = "CAPITAL",
    guild_key = "GUILD_A",
    node_type = States.NODE_TYPE.CAPITAL,
    flag_reference = "CAPITAL_FLAG",
    flag_state = States.FLAG.BOUND,
    x = 0, y = 0, z = 0,
    parent_node_id = "",
    state = States.NODE.PROTECTED,
    original_owner = "GUILD_A",
    current_controller = "GUILD_A",
    display_name = "Old Name",
    territory_radius_meters = 150,
    created_at = 1,
    updated_at = 1
}

local fail_edges_once = true
local fail_nodes_once = false
local last_nodes = nil
local last_edges = nil
local repository = {
    load_nodes = function() return { CAPITAL = copy(capital) } end,
    load_edges = function() return {} end,
    load_campaigns = function() return {} end,
    load_occupations = function() return {} end,
    load_loot_manifests = function() return {} end,
    load_loot_items = function() return {} end,
    save_nodes = function(_, records)
        last_nodes = copy(records)
        if fail_nodes_once then
            fail_nodes_once = false
            return Result.err("WRITE_FAILED", "disk full")
        end
        return Result.ok(true)
    end,
    save_edges = function(_, records)
        if fail_edges_once then
            fail_edges_once = false
            return Result.err("WRITE_FAILED", "disk full")
        end
        last_edges = copy(records)
        return Result.ok(true)
    end,
    save_campaigns = function() return Result.ok(true) end,
    save_occupations = function() return Result.ok(true) end,
    save_loot_manifests = function() return Result.ok(true) end,
    save_loot_items = function() return Result.ok(true) end
}

local service = Conquest.new(
    {},
    {
        conquest = {
            max_outposts_per_clan = 10,
            outpost_link_max_distance_meters = 1500,
            flag_rebind_radius_meters = 30,
            territory_name_max_length = 64,
            territory_min_radius_meters = 50,
            territory_max_radius_meters = 1000,
            operator_roles = { LEADER = true }
        }
    },
    { relations = {} },
    { info = function() end, error = function() end },
    { repository = repository }
)

local registered = service:register_node({
    node_id = "OUTPOST",
    guild_key = "GUILD_A",
    node_type = States.NODE_TYPE.OUTPOST,
    flag_reference = "OUTPOST_FLAG",
    parent_node_id = "CAPITAL",
    actor_role = "LEADER",
    x = 10, y = 0, z = 0,
    now = 2
})
equal(registered.ok, false, "partial node persistence failure returned")
equal(service.nodes.OUTPOST, nil, "failed node removed from memory")
equal(next(service.edges), nil, "failed edge removed from memory")
equal(last_nodes.OUTPOST, nil, "node file compensated after edge failure")
equal(last_edges, nil, "failed atomic edge write keeps prior file")

fail_nodes_once = true
local renamed = service:rename_territory({
    node_id = "CAPITAL",
    guild_key = "GUILD_A",
    actor_role = "LEADER",
    display_name = "New Name",
    now = 3
})
equal(renamed.ok, false, "rename write failure returned")
equal(service.nodes.CAPITAL.display_name, "Old Name", "rename rolled back")
equal(service.nodes.CAPITAL.updated_at, 1, "rename timestamp rolled back")

fail_nodes_once = true
local resized = service:set_territory_radius({
    node_id = "CAPITAL",
    guild_key = "GUILD_A",
    actor_role = "LEADER",
    radius_meters = 200,
    now = 4
})
equal(resized.ok, false, "radius write failure returned")
equal(service.nodes.CAPITAL.territory_radius_meters, 150, "radius rolled back")

service.nodes.CAPITAL.flag_reference = ""
service.nodes.CAPITAL.flag_state = States.FLAG.MISSING
fail_nodes_once = true
local rebound = service:rebind_missing_flag({
    guild_key = "GUILD_A",
    actor_role = "LEADER",
    flag = {
        flag_reference = "NEW_FLAG",
        guild_key = "GUILD_A",
        x = 5, y = 0, z = 0
    },
    now = 5
})
equal(rebound.ok, false, "rebind write failure returned")
equal(service.nodes.CAPITAL.flag_reference, "", "flag reference rolled back")
equal(service.nodes.CAPITAL.flag_state, States.FLAG.MISSING, "flag state rolled back")
equal(service.nodes.CAPITAL.x, 0, "flag position rolled back")

print("conquest_persistence_spec: ok")
