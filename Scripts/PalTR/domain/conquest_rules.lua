local States = require("PalTR.domain.states")
local ConquestStates = require("PalTR.domain.conquest_states")

local Rules = {}

local function decision(allow, reason, offline_exception)
    return {
        allow = allow == true,
        block = allow ~= true,
        reason = reason or "",
        offline_exception = offline_exception == true
    }
end

local function number(value)
    return tonumber(value) or 0
end

function Rules.can_operate(role, config)
    local roles = config and config.operator_roles or {}
    return roles[tostring(role or "")] == true
end

function Rules.distance(first, second)
    local dx = number(first and first.x) - number(second and second.x)
    local dy = number(first and first.y) - number(second and second.y)
    local dz = number(first and first.z) - number(second and second.z)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

function Rules.validate_link(parent, child, config)
    if not parent or not child then
        return decision(false, "NODE_NOT_FOUND")
    end

    local maximum = number(
        config and config.outpost_link_max_distance_meters
    )

    if maximum <= 0 then
        return decision(false, "INVALID_LINK_DISTANCE_CONFIG")
    end

    if Rules.distance(parent, child) > maximum then
        return decision(false, "OUTPOST_LINK_TOO_FAR")
    end

    return decision(true, "OUTPOST_LINK_VALID")
end


function Rules.validate_siege_location(target, nodes, camp, defender, config)
    if not target or not camp then
        return decision(false, "SIEGE_LOCATION_MISSING")
    end

    local target_distance = Rules.distance(target, camp)
    local minimum = number(
        config and config.siege_min_distance_from_target_meters
    )
    local maximum = number(
        config and config.siege_max_distance_from_target_meters
    )

    if target_distance < minimum then
        return decision(false, "SIEGE_TOO_CLOSE_TO_TARGET")
    end

    if maximum <= 0 or target_distance > maximum then
        return decision(false, "SIEGE_TOO_FAR_FROM_TARGET")
    end

    local other_minimum = number(
        config and config.siege_min_distance_from_other_enemy_node_meters
    )

    for _, node in pairs(nodes or {}) do
        if node.node_id ~= target.node_id
            and node.current_controller == defender
            and Rules.distance(node, camp) < other_minimum then
            return decision(false, "SIEGE_TOO_CLOSE_TO_OTHER_ENEMY_NODE")
        end
    end

    return decision(true, "SIEGE_LOCATION_VALID")
end

function Rules.validate_conquest_zone(target, location, config)
    if not target or not location then
        return decision(false, "CONQUEST_ZONE_LOCATION_MISSING")
    end

    local radius = number(config and config.conquest_zone_radius_meters)
    if radius <= 0 then
        return decision(false, "INVALID_CONQUEST_ZONE_CONFIG")
    end

    if Rules.distance(target, location) > radius then
        return decision(false, "OUTSIDE_ACTIVE_CONQUEST_ZONE")
    end

    return decision(true, "ACTIVE_CONQUEST_ZONE", true)
end

function Rules.is_effective_war(relation)
    if not relation then
        return false
    end

    if relation.state == States.WAR
        or relation.state == States.CEASEFIRE_PENDING then
        return true
    end

    return relation.state == States.PEACE_PENDING
        and relation.previous_state == States.WAR
end

function Rules.can_damage_flag(input)
    input = input or {}
    local campaign = input.campaign
    local target = input.target

    if not Rules.is_effective_war(input.relation) then
        return decision(false, "NO_ACTIVE_WAR")
    end

    if not campaign then
        return decision(false, "NO_ACTIVE_CAMPAIGN")
    end

    if campaign.state == ConquestStates.CAMPAIGN.CEASEFIRE_PAUSED then
        return decision(false, "CEASEFIRE_PAUSED")
    end

    if campaign.state == ConquestStates.CAMPAIGN.REARMING
        or number(campaign.rearm_until) > number(input.now) then
        return decision(false, "CEASEFIRE_REARMING")
    end

    if campaign.state ~= ConquestStates.CAMPAIGN.ACTIVE then
        return decision(false, "CAMPAIGN_NOT_ACTIVE")
    end

    if input.raid_open ~= true then
        return decision(false, "RAID_WINDOW_CLOSED")
    end

    if tostring(input.attacker_guild or "") == ""
        or input.attacker_guild ~= campaign.attacker_guild then
        return decision(false, "WRONG_ATTACKER_GUILD")
    end

    if not target
        or campaign.active_target_node_id == ""
        or target.node_id ~= campaign.active_target_node_id then
        return decision(false, "NOT_ACTIVE_CONQUEST_TARGET")
    end

    if target.current_controller ~= campaign.defender_guild then
        return decision(false, "TARGET_NOT_DEFENDER_CONTROLLED")
    end

    if input.reachable ~= true then
        return decision(false, "TARGET_NOT_FRONTLINE_REACHABLE")
    end

    local valid_state =
        target.state == ConquestStates.NODE.TARGETABLE
        or target.state == ConquestStates.NODE.UNDER_ATTACK
        or target.state == ConquestStates.NODE.CAPITAL_TARGETABLE
        or target.state == ConquestStates.NODE.CAPITAL_UNDER_ATTACK

    if not valid_state then
        return decision(false, "TARGET_STATE_BLOCKED")
    end

    return decision(true, "ACTIVE_CONQUEST_TARGET", true)
end

return Rules
