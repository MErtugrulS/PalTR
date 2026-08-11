package.path = table.concat({
    "Scripts/?.lua",
    "Scripts/?/init.lua",
    package.path
}, ";")

local Rules = require("PalTR.domain.conquest_rules")
local RaidWindow = require("PalTR.domain.raid_window")
local States = require("PalTR.domain.states")
local ConquestStates = require("PalTR.domain.conquest_states")

local function equal(actual, expected, message)
    if actual ~= expected then
        error(message .. ": expected=" .. tostring(expected) ..
            " actual=" .. tostring(actual))
    end
end

local config = {
    operator_roles = {
        LEADER = true,
        DEPUTY_LEADER = true,
        COMMANDER = true
    },
    outpost_link_max_distance_meters = 1500,
    siege_min_distance_from_target_meters = 250,
    siege_max_distance_from_target_meters = 600,
    siege_min_distance_from_other_enemy_node_meters = 300,
    conquest_zone_radius_meters = 150
}

equal(Rules.can_operate("LEADER", config), true, "leader authorized")
equal(Rules.can_operate("DEPUTY_LEADER", config), true, "deputy authorized")
equal(Rules.can_operate("COMMANDER", config), true, "commander authorized")
equal(Rules.can_operate("MEMBER", config), false, "member blocked")

equal(RaidWindow.is_open_minutes(21 * 60, "20:00", "00:00"), true, "raid open")
equal(RaidWindow.is_open_minutes(1 * 60, "20:00", "00:00"), false, "raid closed")
equal(RaidWindow.is_open_minutes(60, "22:00", "02:00"), true, "cross midnight open")

local target = {
    node_id = "B_OUTPOST_1",
    current_controller = "GUILD_B",
    state = ConquestStates.NODE.TARGETABLE,
    x = 0, y = 0, z = 0
}
local other = {
    node_id = "B_OUTPOST_2",
    current_controller = "GUILD_B",
    x = 1000, y = 0, z = 0
}
local campaign = {
    state = ConquestStates.CAMPAIGN.ACTIVE,
    attacker_guild = "GUILD_A",
    defender_guild = "GUILD_B",
    active_target_node_id = target.node_id,
    rearm_until = 0
}
local relation = {
    state = States.WAR,
    previous_state = States.WAR
}

local function damage(overrides)
    local input = {
        relation = relation,
        campaign = campaign,
        target = target,
        attacker_guild = "GUILD_A",
        raid_open = true,
        reachable = true,
        now = 100
    }

    for key, value in pairs(overrides or {}) do
        input[key] = value
    end

    return Rules.can_damage_flag(input)
end

equal(damage({ relation = { state = States.NEUTRAL } }).block, true, "A no war")
equal(damage({ raid_open = false }).reason, "RAID_WINDOW_CLOSED", "B raid closed")
equal(
    damage({ target = {
        node_id = "B_OUTPOST_2",
        current_controller = "GUILD_B",
        state = ConquestStates.NODE.TARGETABLE
    } }).reason,
    "NOT_ACTIVE_CONQUEST_TARGET",
    "C wrong flag"
)
equal(damage().allow, true, "D active target allowed")
equal(damage().offline_exception, true, "F offline exception scoped")

campaign.state = ConquestStates.CAMPAIGN.CEASEFIRE_PAUSED
equal(damage().reason, "CEASEFIRE_PAUSED", "ceasefire blocks")
campaign.state = ConquestStates.CAMPAIGN.REARMING
campaign.rearm_until = 200
equal(damage().reason, "CEASEFIRE_REARMING", "rearm blocks")
campaign.state = ConquestStates.CAMPAIGN.ACTIVE
campaign.rearm_until = 0

equal(
    Rules.validate_link(
        { x = 0, y = 0, z = 0 },
        { x = 1501, y = 0, z = 0 },
        config
    ).reason,
    "OUTPOST_LINK_TOO_FAR",
    "link limit"
)

equal(
    Rules.validate_siege_location(
        target,
        { target = target, other = other },
        { x = 400, y = 0, z = 0 },
        "GUILD_B",
        config
    ).allow,
    true,
    "siege location valid"
)
equal(
    Rules.validate_siege_location(
        target,
        { target = target, other = other },
        { x = 100, y = 0, z = 0 },
        "GUILD_B",
        config
    ).reason,
    "SIEGE_TOO_CLOSE_TO_TARGET",
    "siege minimum enforced"
)

equal(
    Rules.validate_conquest_zone(
        target,
        { x = 150, y = 0, z = 0 },
        config
    ).allow,
    true,
    "conquest zone boundary allowed"
)
equal(
    Rules.validate_conquest_zone(
        target,
        { x = 151, y = 0, z = 0 },
        config
    ).reason,
    "OUTSIDE_ACTIVE_CONQUEST_ZONE",
    "outside conquest zone blocked"
)

print("conquest_rules_spec: ok")
