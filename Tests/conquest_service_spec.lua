package.path = table.concat({
    "Scripts/?.lua",
    "Scripts/?/init.lua",
    package.path
}, ";")

local Conquest = require("PalTR.services.conquest_service")
local Result = require("PalTR.core.result")
local DiplomacyStates = require("PalTR.domain.states")
local States = require("PalTR.domain.conquest_states")
local TempPath = dofile("Tests/support/temp_path.lua")

local function equal(actual, expected, message)
    if actual ~= expected then
        error(message .. ": expected=" .. tostring(expected) ..
            " actual=" .. tostring(actual))
    end
end

local function make_paths(prefix)
    return {
        conquest_nodes = prefix .. "_nodes.tsv",
        conquest_edges = prefix .. "_edges.tsv",
        conquest_campaigns = prefix .. "_campaigns.tsv",
        conquest_occupations = prefix .. "_occupations.tsv",
        conquest_loot = prefix .. "_loot.tsv",
        conquest_loot_items = prefix .. "_loot_items.tsv",
        conquest_events = prefix .. "_events.tsv",
        conquest_damage_policy = prefix .. "_damage_policy.tsv",
        conquest_zone_policy = prefix .. "_zone_policy.tsv",
        conquest_runtime_events = prefix .. "_runtime_events.tsv"
    }
end

local function cleanup(paths)
    for _, path in pairs(paths) do
        os.remove(path)
        os.remove(path .. ".processing")
    end
end

local function make_config(maximum)
    return {
        diplomacy = {
            ceasefire_rearm_seconds = 30
        },
        conquest = {
            max_outposts_per_clan = maximum or 10,
            world_units_per_meter = 100,
            flag_rebind_radius_meters = 30,
            raid_timezone = "Europe/Istanbul",
            raid_utc_offset_minutes = 180,
            raid_window_start = "00:00",
            raid_window_end = "00:00",
            occupation_hold_seconds = 10,
            counter_attack_hold_seconds = 1,
            counter_attack_flag_radius_meters = 30,
            outpost_link_max_distance_meters = 1500,
            conquest_zone_radius_meters = 150,
            siege_min_distance_from_target_meters = 250,
            siege_max_distance_from_target_meters = 600,
            siege_min_distance_from_other_enemy_node_meters = 300,
            peace_occupation_resolution = "OCCUPIER_WINS",
            capital_defeat_resolution = "TRANSFER_ALL_NODES",
            operator_roles = {
                LEADER = true,
                DEPUTY_LEADER = true,
                COMMANDER = true
            },
            loot_table = {
                {
                    item_id = "PalSphere_Ancient_2",
                    item_selector = "CAPTURE_SPHERE_LEVEL:Ancient_2",
                    enabled = true,
                    weight = 1,
                    min_quantity = 1,
                    max_quantity = 1,
                    tier = "ANCIENT_2",
                    category = "PAL_SPHERE"
                }
            }
        }
    }
end

local function make_diplomacy(config, first, second)
    local key = first < second
        and first .. "::" .. second
        or second .. "::" .. first
    local relation = {
        key = key,
        guild_a = first < second and first or second,
        guild_b = first < second and second or first,
        state = DiplomacyStates.WAR,
        previous_state = DiplomacyStates.NEUTRAL,
        active_at = 10,
        expires_at = 0
    }
    local diplomacy = {
        config = config,
        relations = { [key] = relation }
    }

    function diplomacy:resolve_capital_defeat(winner, loser)
        self.resolved_winner = winner
        self.resolved_loser = loser
        relation.previous_state = relation.state
        relation.state = DiplomacyStates.NEUTRAL
        relation.active_at = 0
        return Result.ok(relation)
    end

    return diplomacy, relation
end

local function register(service, request)
    request.actor_role = request.actor_role or "LEADER"
    local result = service:register_node(request)
    if not result.ok then
        error("register failed: " .. result.error.code)
    end
    return result.value
end

local paths = make_paths(TempPath.prefix("paltr_conquest_service"))
local config = make_config(2)
local diplomacy, relation = make_diplomacy(config, "GUILD_A", "GUILD_B")
local service = Conquest.new(
    paths,
    config,
    diplomacy,
    nil,
    { random = function() return 0 end }
)

register(service, {
    node_id = "A_CAPITAL",
    flag_reference = "A_FLAG_CAPITAL",
    guild_key = "GUILD_A",
    node_type = States.NODE_TYPE.CAPITAL,
    x = -2000, y = 0, z = 0, now = 1
})
register(service, {
    node_id = "B_CAPITAL",
    flag_reference = "B_FLAG_CAPITAL",
    guild_key = "GUILD_B",
    node_type = States.NODE_TYPE.CAPITAL,
    x = 1200, y = 0, z = 0, now = 1
})
register(service, {
    node_id = "B_OUTPOST_1",
    flag_reference = "B_FLAG_1",
    guild_key = "GUILD_B",
    node_type = States.NODE_TYPE.OUTPOST,
    parent_node_id = "B_CAPITAL",
    x = 0, y = 0, z = 0, now = 2
})
register(service, {
    node_id = "B_OUTPOST_2",
    flag_reference = "B_FLAG_2",
    guild_key = "GUILD_B",
    node_type = States.NODE_TYPE.OUTPOST,
    parent_node_id = "B_CAPITAL",
    x = 2400, y = 0, z = 0, now = 2
})

local limit = service:register_node({
    node_id = "B_OUTPOST_3",
    guild_key = "GUILD_B",
    node_type = States.NODE_TYPE.OUTPOST,
    parent_node_id = "B_CAPITAL",
    actor_role = "LEADER",
    x = 1200, y = 1000, z = 0, now = 3
})
equal(limit.ok, false, "N outpost limit blocks")
equal(limit.error.code, "OUTPOST_LIMIT_REACHED", "N limit reason")

local own_dispose_file = assert(io.open(paths.conquest_runtime_events, "w"))
own_dispose_file:write(
    "timestamp\tmarker\tflag_reference\n" ..
    "4\tFLAG_DISPOSED\tA_FLAG_CAPITAL\n"
)
own_dispose_file:close()
equal(service:process_runtime_events(4).ok, true, "registered non-target dispose processed")
equal(service.nodes.A_CAPITAL.flag_state, States.FLAG.MISSING, "disposed capital marked missing")
equal(service:status_for_guild("GUILD_A", 4).missing_flag_count, 1, "missing capital reported")
equal(
    service:rebind_missing_flag({
        guild_key = "GUILD_A",
        actor_role = "LEADER",
        flag = {
            flag_reference = "A_FLAG_CAPITAL_REBUILT",
            guild_key = "GUILD_A",
            x = -2000, y = 0, z = 0
        },
        now = 5
    }).ok,
    true,
    "protected missing capital accepts replacement flag"
)
equal(service.nodes.A_CAPITAL.flag_state, States.FLAG.BOUND, "replacement capital bound")
equal(service:status_for_guild("GUILD_A", 5).missing_flag_count, 0, "missing capital cleared")

local unauthorized = service:start_campaign(
    "GUILD_A", "GUILD_B", "MEMBER", 10
)
equal(unauthorized.ok, false, "member cannot start campaign")

local started = service:start_campaign(
    "GUILD_A", "GUILD_B", "COMMANDER", 10
)
equal(started.ok, true, "campaign starts")
local campaign = started.value

local siege = service:establish_siege(
    campaign.campaign_id,
    "DEPUTY_LEADER",
    "B_OUTPOST_1",
    { reference = "SIEGE_A", x = 400, y = 0, z = 0 },
    20
)
equal(siege.ok, true, "siege and first target established")
equal(service:write_damage_policy(21).ok, true, "damage policy written")
local policy_file = assert(io.open(paths.conquest_damage_policy, "r"))
local policy_text = policy_file:read("*a")
policy_file:close()
local zone_policy_file = assert(io.open(paths.conquest_zone_policy, "r"))
local zone_policy_text = zone_policy_file:read("*a")
zone_policy_file:close()
equal(
    policy_text:find("B_FLAG_1\tB_OUTPOST_1\tGUILD_B\tGUILD_A", 1, true)
        ~= nil,
    true,
    "active flag attacker exported"
)
equal(
    policy_text:find("B_FLAG_2\tB_OUTPOST_2\tGUILD_B\t\n", 1, true)
        ~= nil,
    true,
    "inactive flag has no allowed attacker"
)
equal(
    zone_policy_text:find(
        "B_OUTPOST_1\tGUILD_B\tGUILD_A\t0\t0\t0\t15000",
        1,
        true
    ) ~= nil,
    true,
    "active conquest zone exported in world units"
)
equal(
    zone_policy_text:find("B_OUTPOST_2", 1, true) == nil,
    true,
    "inactive conquest zone is not exported"
)
equal(
    service:can_damage_conquest_zone(
        campaign.campaign_id,
        "GUILD_A",
        { x = 100, y = 0, z = 0 },
        21
    ).allow,
    true,
    "F active target zone gets scoped offline exception"
)
equal(
    service:can_damage_conquest_zone(
        campaign.campaign_id,
        "GUILD_A",
        { x = 151, y = 0, z = 0 },
        21
    ).reason,
    "OUTSIDE_ACTIVE_CONQUEST_ZONE",
    "F other regions remain protected"
)

equal(
    service:can_damage_flag(
        campaign.campaign_id,
        "B_OUTPOST_2",
        "GUILD_A",
        21
    ).reason,
    "NOT_ACTIVE_CONQUEST_TARGET",
    "E other enemy flag blocked"
)
equal(
    service:record_target_damage(
        campaign.campaign_id,
        "B_OUTPOST_1",
        "GUILD_A",
        21
    ).ok,
    true,
    "D target damage allowed"
)

local runtime_file = assert(io.open(paths.conquest_runtime_events, "w"))
runtime_file:write(
    "timestamp\tmarker\tflag_reference\n" ..
    "22\tFLAG_DISPOSED\tB_FLAG_1\n"
)
runtime_file:close()
local runtime_result = service:process_runtime_events(22)
equal(runtime_result.ok, true, "G runtime dispose event processed")
equal(runtime_result.value, 1, "G one outpost occupied")
equal(service.nodes.B_OUTPOST_1.state, States.NODE.OCCUPIED, "G node occupied")
equal(service.nodes.B_OUTPOST_1.flag_state, States.FLAG.MISSING, "G fallen flag missing")
equal(service.nodes.B_OUTPOST_1.legacy_flag_reference, "", "G disposed flag cleanup reference cleared")
local occupied_status = service:status_for_guild("GUILD_B", 24)
equal(occupied_status.capital_count, 1, "G status reports capital")
equal(occupied_status.outpost_count, 1, "G status reports controlled outposts")
equal(occupied_status.campaigns[1].direction, "DEFENSE", "G status direction")
equal(occupied_status.occupations[1].remaining_seconds, 8, "G live timer reported")
local expansion_parent = service:nearest_controlled_node(
    "GUILD_A",
    service.nodes.B_OUTPOST_1
)
equal(
    expansion_parent.node_id,
    "A_CAPITAL",
    "G occupied enemy node cannot anchor permanent expansion"
)
local replay_result = service:process_runtime_events(23)
equal(replay_result.ok, true, "G cleared queue reloads")
equal(replay_result.value, 0, "G dispose event is not replayed")

local recovery_file = assert(io.open(
    paths.conquest_runtime_events .. ".processing",
    "w"
))
recovery_file:write(
    "timestamp\tmarker\tflag_reference\n" ..
    "23\tFLAG_DISPOSED\tUNKNOWN_FLAG\n"
)
recovery_file:close()
local pending_file = assert(io.open(paths.conquest_runtime_events, "w"))
pending_file:write(
    "timestamp\tmarker\tflag_reference\n" ..
    "24\tFLAG_DISPOSED\tLATER_FLAG\n"
)
pending_file:close()

local recovery_result = service:process_runtime_events(23)
equal(recovery_result.ok, true, "G interrupted queue recovers")
equal(recovery_result.value, 0, "G unknown recovered event is ignored")
local pending_lines = assert(io.open(paths.conquest_runtime_events, "r"))
local pending_content = pending_lines:read("*a")
pending_lines:close()
equal(
    pending_content:find("LATER_FLAG", 1, true) ~= nil,
    true,
    "G active queue remains untouched during recovery"
)
local pending_result = service:process_runtime_events(24)
equal(pending_result.ok, true, "G active queue follows recovered queue")
equal(pending_result.value, 0, "G later unknown event is ignored")

local first_manifest = service.loot_manifests[
    service.occupations.B_OUTPOST_1.loot_manifest_id
]
equal(first_manifest.state, States.LOOT.CREATED, "G loot created")

equal(
    service:start_counter_attack(
        "B_OUTPOST_1",
        "GUILD_B",
        "LEADER",
        {
            flag_reference = "WRONG_OWNER_FLAG",
            guild_key = "GUILD_A",
            x = 0, y = 0, z = 0
        },
        23
    ).error.code,
    "COUNTER_FLAG_OWNER_MISMATCH",
    "H foreign flag cannot start counter attack"
)
equal(
    service:start_counter_attack(
        "B_OUTPOST_1",
        "GUILD_B",
        "LEADER",
        {
            flag_reference = "DISTANT_COUNTER_FLAG",
            guild_key = "GUILD_B",
            x = 100, y = 0, z = 0
        },
        23
    ).error.code,
    "COUNTER_FLAG_NOT_NEAR",
    "H distant flag cannot start counter attack"
)

equal(
    service:start_counter_attack(
        "B_OUTPOST_1",
        "GUILD_B",
        "COMMANDER",
        {
            flag_reference = "B_COUNTER_FLAG_1",
            guild_key = "GUILD_B",
            x = 0, y = 0, z = 0
        },
        23
    ).ok,
    true,
    "H counter attack starts"
)
equal(
    service:restore_occupation(
        "B_OUTPOST_1", "GUILD_B", "LEADER", 33
    ).error.code,
    "OCCUPATION_EXPIRED",
    "H expired counter attack cannot restore"
)
equal(service:write_damage_policy(23).ok, true, "H counter flag policy written")
local counter_policy_file = assert(io.open(paths.conquest_damage_policy, "r"))
local counter_policy = counter_policy_file:read("*a")
counter_policy_file:close()
equal(
    counter_policy:find(
        "B_COUNTER_FLAG_1\tB_OUTPOST_1\tGUILD_B\tGUILD_A",
        1,
        true
    ) ~= nil,
    true,
    "H occupier may destroy counter flag"
)
local counter_event_file = assert(io.open(paths.conquest_runtime_events, "w"))
counter_event_file:write(
    "timestamp\tmarker\tflag_reference\n" ..
    "24\tFLAG_DISPOSED\tB_COUNTER_FLAG_1\n"
)
counter_event_file:close()
equal(service:process_runtime_events(24).value, 1, "H destroyed counter flag handled")
equal(service.occupations.B_OUTPOST_1.state, States.OCCUPATION.OCCUPIED, "H failed counter returns to occupation")
equal(
    service:start_counter_attack(
        "B_OUTPOST_1",
        "GUILD_B",
        "LEADER",
        {
            flag_reference = "B_FLAG_1_REBUILT",
            guild_key = "GUILD_B",
            x = 0, y = 0, z = 0
        },
        24
    ).ok,
    true,
    "H counter attack can be retried"
)
equal(
    service:restore_occupation(
        "B_OUTPOST_1", "GUILD_B", "LEADER", 24
    ).error.code,
    "COUNTER_ATTACK_HOLD_ACTIVE",
    "H counter flag cannot restore before hold completes"
)
relation.state = DiplomacyStates.CEASEFIRE
equal(
    service:restore_occupation(
        "B_OUTPOST_1", "GUILD_B", "LEADER", 25
    ).error.code,
    "WAR_NOT_ACTIVE",
    "H ceasefire blocks restore before scheduler tick"
)
relation.state = DiplomacyStates.WAR
equal(
    service:tick(25).ok,
    true,
    "H scheduler restores completed counter attack"
)
equal(service.nodes.B_OUTPOST_1.current_controller, "GUILD_B", "H owner restored")
equal(first_manifest.state, States.LOOT.RECOVERED, "H loot recovered")
equal(service.nodes.B_OUTPOST_1.flag_state, States.FLAG.BOUND, "H flag rebound")
equal(service.nodes.B_OUTPOST_1.flag_reference, "B_FLAG_1_REBUILT", "H counter flag becomes restored flag")

equal(
    service:select_target(
        campaign.campaign_id,
        "LEADER",
        "B_OUTPOST_1",
        25
    ).ok,
    true,
    "restored first target can be selected"
)
equal(
    service:flag_fallen(
        campaign.campaign_id,
        "B_OUTPOST_1",
        "GUILD_A",
        26
    ).ok,
    true,
    "outpost occupied again"
)

service.config.counter_attack_hold_seconds = 10
equal(
    service:start_counter_attack(
        "B_OUTPOST_1",
        "GUILD_B",
        "LEADER",
        {
            flag_reference = "B_COUNTER_FLAG_PAUSED",
            guild_key = "GUILD_B",
            x = 0, y = 0, z = 0
        },
        27
    ).ok,
    true,
    "J counter attack starts before ceasefire"
)

relation.state = DiplomacyStates.CEASEFIRE
relation.previous_state = DiplomacyStates.WAR
equal(service:tick(31).ok, true, "J ceasefire tick")
equal(campaign.state, States.CAMPAIGN.CEASEFIRE_PAUSED, "J campaign paused")
equal(service.occupations.B_OUTPOST_1.remaining_seconds, 5, "J timer frozen")
equal(service.occupations.B_OUTPOST_1.counter_remaining_seconds, 6, "J counter timer frozen")

local second_manifest = service.loot_manifests[
    service.occupations.B_OUTPOST_1.loot_manifest_id
]
equal(
    service:extract_loot(second_manifest.manifest_id, "GUILD_A", 32).ok,
    false,
    "loot extraction pauses in ceasefire"
)

relation.state = DiplomacyStates.WAR
relation.previous_state = DiplomacyStates.CEASEFIRE
equal(service:tick(100).ok, true, "K ceasefire breaks")
equal(campaign.state, States.CAMPAIGN.REARMING, "K rearming starts")
equal(service:tick(129).ok, true, "K rearm still active")
equal(campaign.state, States.CAMPAIGN.REARMING, "K rearm blocks early")
equal(service:tick(130).ok, true, "K rearm completes")
equal(campaign.state, States.CAMPAIGN.ACTIVE, "K campaign resumes")
equal(service:tick(135).ok, true, "I occupation finalizes")
equal(service.nodes.B_OUTPOST_1.state, States.NODE.CONQUERED, "I node conquered")
equal(service.occupations.B_OUTPOST_1.counter_flag_reference, "", "I expired occupation clears counter flag")
equal(service.nodes.B_OUTPOST_1.flag_state, States.FLAG.MISSING, "I conquered flag awaits replacement")

equal(
    service:extract_loot(second_manifest.manifest_id, "GUILD_A", 136).ok,
    true,
    "loot extracts after resume"
)

equal(
    service:rebind_missing_flag({
        guild_key = "GUILD_A",
        actor_role = "COMMANDER",
        flag = {
            flag_reference = "A_CAPTURE_FLAG_1",
            guild_key = "GUILD_A",
            x = 0, y = 0, z = 0
        },
        now = 139
    }).ok,
    true,
    "captor plants replacement flag before frontline advances"
)
equal(
    service:select_next_target(
        campaign.campaign_id,
        "COMMANDER",
        140
    ).ok,
    true,
    "nearest frontline target selected"
)
equal(campaign.active_target_node_id, "B_CAPITAL", "capital unlocked through edge")
equal(
    service:flag_fallen(
        campaign.campaign_id,
        "B_CAPITAL",
        "GUILD_A",
        141
    ).ok,
    true,
    "capital defeated"
)
equal(campaign.state, States.CAMPAIGN.CAPITAL_DEFEATED, "capital result state")
equal(service.nodes.B_OUTPOST_2.current_controller, "GUILD_A", "remaining node transferred")
equal(service.nodes.B_CAPITAL.node_type, States.NODE_TYPE.OUTPOST, "captured capital demoted")
equal(service.nodes.B_OUTPOST_2.flag_state, States.FLAG.MISSING, "transferred outpost needs new flag")
equal(service.nodes.B_CAPITAL.flag_state, States.FLAG.MISSING, "captured capital needs new flag")
equal(service.nodes.B_OUTPOST_2.legacy_flag_reference, "B_FLAG_2", "old transferred flag retained for cleanup")
equal(service:write_damage_policy(142).ok, true, "captured cleanup policy written")
local cleanup_policy_file = assert(io.open(paths.conquest_damage_policy, "r"))
local cleanup_policy = cleanup_policy_file:read("*a")
cleanup_policy_file:close()
equal(
    cleanup_policy:find("B_FLAG_2\tB_OUTPOST_2\tGUILD_B\tGUILD_A", 1, true)
        ~= nil,
    true,
    "winner may remove transferred owner's old physical flag"
)
equal(
    service:rebind_missing_flag({
        guild_key = "GUILD_A",
        actor_role = "DEPUTY_LEADER",
        flag = {
            flag_reference = "A_CAPTURE_FLAG_2",
            guild_key = "GUILD_A",
            x = service.nodes.B_OUTPOST_2.x,
            y = service.nodes.B_OUTPOST_2.y,
            z = service.nodes.B_OUTPOST_2.z
        },
        now = 143
    }).ok,
    true,
    "winner rebinds transferred outpost"
)
equal(service:write_damage_policy(144).ok, true, "rebound policy written")
cleanup_policy_file = assert(io.open(paths.conquest_damage_policy, "r"))
cleanup_policy = cleanup_policy_file:read("*a")
cleanup_policy_file:close()
equal(
    cleanup_policy:find("A_CAPTURE_FLAG_2\tB_OUTPOST_2\tGUILD_A", 1, true)
        ~= nil,
    true,
    "replacement flag receives normal controller policy"
)
equal(
    cleanup_policy:find("B_FLAG_2\tB_OUTPOST_2\tGUILD_B\tGUILD_A", 1, true)
        ~= nil,
    true,
    "replacement does not discard old flag cleanup policy"
)
equal(diplomacy.resolved_winner, "GUILD_A", "diplomacy receives winner")

equal(
    service:register_node({
        node_id = "B_NEW_CAPITAL",
        guild_key = "GUILD_B",
        node_type = States.NODE_TYPE.CAPITAL,
        actor_role = "LEADER",
        x = 5000, y = 0, z = 0, now = 150
    }).ok,
    true,
    "defeated guild restarts with new capital"
)

local restored = Conquest.new(paths, config, diplomacy, nil)
equal(restored.nodes.B_OUTPOST_2.current_controller, "GUILD_A", "M node restored")
equal(restored.nodes.B_OUTPOST_2.flag_state, States.FLAG.BOUND, "M rebound flag restored")
equal(restored.nodes.B_OUTPOST_2.legacy_flag_reference, "B_FLAG_2", "M cleanup flag restored")
equal(
    restored.campaigns[campaign.campaign_id].state,
    States.CAMPAIGN.CAPITAL_DEFEATED,
    "M campaign restored"
)
equal(
    restored.loot_manifests[second_manifest.manifest_id].state,
    States.LOOT.EXTRACTED,
    "M loot restored"
)

cleanup(paths)

-- Peace resolves an unfinished occupation in occupier's favor.
local peace_paths = make_paths(TempPath.prefix("paltr_conquest_peace"))
local peace_config = make_config(10)
local peace_diplomacy, peace_relation = make_diplomacy(
    peace_config, "GUILD_C", "GUILD_D"
)
local peace_service = Conquest.new(
    peace_paths,
    peace_config,
    peace_diplomacy,
    nil,
    { random = function() return 0 end }
)

register(peace_service, {
    node_id = "D_CAPITAL", guild_key = "GUILD_D",
    node_type = States.NODE_TYPE.CAPITAL,
    x = 1200, y = 0, z = 0, now = 1
})
register(peace_service, {
    node_id = "D_OUTPOST", guild_key = "GUILD_D",
    node_type = States.NODE_TYPE.OUTPOST,
    parent_node_id = "D_CAPITAL",
    x = 0, y = 0, z = 0, now = 2
})
local peace_campaign = peace_service:start_campaign(
    "GUILD_C", "GUILD_D", "LEADER", 10
).value
peace_service:establish_siege(
    peace_campaign.campaign_id,
    "LEADER",
    "D_OUTPOST",
    { reference = "SIEGE_C", x = 400, y = 0, z = 0 },
    20
)
peace_service:flag_fallen(
    peace_campaign.campaign_id,
    "D_OUTPOST",
    "GUILD_C",
    21
)
peace_relation.state = DiplomacyStates.NEUTRAL
equal(peace_service:tick(22).ok, true, "L peace resolves")
equal(peace_campaign.state, States.CAMPAIGN.PEACE_RESOLVED, "L campaign closes")
equal(peace_service.nodes.D_OUTPOST.state, States.NODE.CONQUERED, "L occupier wins")
equal(peace_campaign.siege_camp_reference, "", "L siege camp clears")

cleanup(peace_paths)
print("conquest_service_spec: ok")
