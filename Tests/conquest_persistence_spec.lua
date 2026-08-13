package.path = table.concat({
    "Scripts/?.lua",
    "Scripts/?/init.lua",
    package.path
}, ";")

local Conquest = require("PalTR.services.conquest_service")
local DiplomacyStates = require("PalTR.domain.states")
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
local fail_campaigns_once = false
local fail_occupations_once = false
local fail_loot_items_once = false
local last_nodes = nil
local last_edges = nil
local last_loot_manifests = nil
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
    save_campaigns = function()
        if fail_campaigns_once then
            fail_campaigns_once = false
            return Result.err("WRITE_FAILED", "disk full")
        end
        return Result.ok(true)
    end,
    save_occupations = function()
        if fail_occupations_once then
            fail_occupations_once = false
            return Result.err("WRITE_FAILED", "disk full")
        end
        return Result.ok(true)
    end,
    save_loot_manifests = function(_, records)
        last_loot_manifests = copy(records)
        return Result.ok(true)
    end,
    save_loot_items = function()
        if fail_loot_items_once then
            fail_loot_items_once = false
            return Result.err("WRITE_FAILED", "disk full")
        end
        return Result.ok(true)
    end
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
            siege_min_distance_from_target_meters = 250,
            siege_max_distance_from_target_meters = 600,
            siege_min_distance_from_other_enemy_node_meters = 100,
            raid_window_start = "00:00",
            raid_window_end = "00:00",
            raid_utc_offset_minutes = 0,
            counter_attack_flag_radius_meters = 30,
            counter_attack_hold_seconds = 10,
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

service.nodes.B_CAPITAL = {
    key = "B_CAPITAL",
    node_id = "B_CAPITAL",
    guild_key = "GUILD_B",
    node_type = States.NODE_TYPE.CAPITAL,
    flag_reference = "B_CAPITAL_FLAG",
    flag_state = States.FLAG.BOUND,
    x = 1000, y = 0, z = 0,
    state = States.NODE.PROTECTED,
    original_owner = "GUILD_B",
    current_controller = "GUILD_B",
    created_at = 1,
    updated_at = 1
}
service.diplomacy.relations["GUILD_A::GUILD_B"] = {
    key = "GUILD_A::GUILD_B",
    guild_a = "GUILD_A",
    guild_b = "GUILD_B",
    state = DiplomacyStates.WAR,
    active_at = 10
}

fail_campaigns_once = true
local campaign_result = service:start_campaign(
    "GUILD_A",
    "GUILD_B",
    "LEADER",
    10
)
local campaign_id = "GUILD_A::GUILD_B@10::GUILD_A"
equal(campaign_result.ok, false, "campaign write failure returned")
equal(service.campaigns[campaign_id], nil, "failed campaign removed from memory")

service.nodes.B_OUTPOST = {
    key = "B_OUTPOST",
    node_id = "B_OUTPOST",
    guild_key = "GUILD_B",
    node_type = States.NODE_TYPE.OUTPOST,
    flag_reference = "B_OUTPOST_FLAG",
    flag_state = States.FLAG.BOUND,
    x = 0, y = 0, z = 0,
    state = States.NODE.PROTECTED,
    original_owner = "GUILD_B",
    current_controller = "GUILD_B",
    created_at = 1,
    updated_at = 1
}
service.campaigns[campaign_id] = {
    key = campaign_id,
    campaign_id = campaign_id,
    war_id = "GUILD_A::GUILD_B@10",
    attacker_guild = "GUILD_A",
    defender_guild = "GUILD_B",
    state = States.CAMPAIGN.ACTIVE,
    active_target_node_id = "",
    siege_camp_reference = "",
    siege_x = 0,
    siege_y = 0,
    siege_z = 0,
    updated_at = 1
}

fail_campaigns_once = true
local siege_result = service:establish_siege(
    campaign_id,
    "LEADER",
    "B_OUTPOST",
    { reference = "SIEGE_CAMP", x = 300, y = 0, z = 0 },
    20
)
equal(siege_result.ok, false, "target campaign write failure returned")
equal(service.nodes.B_OUTPOST.state, States.NODE.PROTECTED, "target state rolled back")
equal(service.nodes.B_OUTPOST.updated_at, 1, "target timestamp rolled back")
equal(service.campaigns[campaign_id].active_target_node_id, "", "target id rolled back")
equal(service.campaigns[campaign_id].siege_camp_reference, "", "siege camp rolled back")
equal(service.campaigns[campaign_id].updated_at, 1, "campaign timestamp rolled back")
equal(last_nodes.B_OUTPOST.state, States.NODE.PROTECTED, "target node file compensated")

service.nodes.B_OUTPOST.state = States.NODE.TARGETABLE
service.nodes.B_OUTPOST.updated_at = 1
service.campaigns[campaign_id].active_target_node_id = "B_OUTPOST"
service.campaigns[campaign_id].siege_camp_reference = "SIEGE_CAMP"
service.campaigns[campaign_id].siege_x = 300
fail_nodes_once = true
local damage_result = service:record_target_damage(
    campaign_id,
    "B_OUTPOST",
    "GUILD_A",
    21
)
equal(damage_result.ok, false, "target damage write failure returned")
equal(service.nodes.B_OUTPOST.state, States.NODE.TARGETABLE, "damage state rolled back")
equal(service.nodes.B_OUTPOST.updated_at, 1, "damage timestamp rolled back")

service.campaigns.COUNTER = {
    key = "COUNTER",
    campaign_id = "COUNTER",
    war_id = "COUNTER_WAR",
    attacker_guild = "GUILD_B",
    defender_guild = "GUILD_A",
    state = States.CAMPAIGN.ACTIVE,
    active_target_node_id = "",
    siege_camp_reference = "COUNTER_CAMP",
    updated_at = 1
}
service.occupations.B_OUTPOST = {
    key = "B_OUTPOST",
    node_id = "B_OUTPOST",
    original_owner = "GUILD_A",
    occupying_guild = "GUILD_B",
    war_id = "COUNTER_WAR",
    state = States.OCCUPATION.OCCUPIED,
    remaining_seconds = 1000,
    last_resumed_at = 1,
    frontline_state = "HELD",
    updated_at = 1
}
fail_occupations_once = true
local counter_result = service:start_counter_attack(
    "B_OUTPOST",
    "GUILD_A",
    "LEADER",
    { flag_reference = "COUNTER_FLAG", guild_key = "GUILD_A", x = 0, y = 0, z = 0 },
    22
)
equal(counter_result.ok, false, "counter attack write failure returned")
equal(service.occupations.B_OUTPOST.state, States.OCCUPATION.OCCUPIED,
    "counter attack state rolled back")
equal(service.occupations.B_OUTPOST.counter_flag_reference, nil,
    "counter flag rolled back")

service.loot_manifests.LOOT = {
    key = "LOOT",
    manifest_id = "LOOT",
    war_id = "GUILD_A::GUILD_B@10",
    owner_guild = "GUILD_A",
    state = States.LOOT.CREATED,
    extracted_at = 0
}
fail_loot_items_once = true
local transit_result = service:mark_loot_in_transit("LOOT", "GUILD_A")
equal(transit_result.ok, false, "loot transit write failure returned")
equal(service.loot_manifests.LOOT.state, States.LOOT.CREATED,
    "loot transit state rolled back")
equal(last_loot_manifests.LOOT.state, States.LOOT.CREATED,
    "loot transit file compensated")

fail_loot_items_once = true
local extract_result = service:extract_loot("LOOT", "GUILD_A", 23)
equal(extract_result.ok, false, "loot extraction write failure returned")
equal(service.loot_manifests.LOOT.state, States.LOOT.CREATED,
    "loot extraction state rolled back")
equal(service.loot_manifests.LOOT.extracted_at, 0,
    "loot extraction timestamp rolled back")
equal(last_loot_manifests.LOOT.state, States.LOOT.CREATED,
    "loot extraction file compensated")

print("conquest_persistence_spec: ok")
