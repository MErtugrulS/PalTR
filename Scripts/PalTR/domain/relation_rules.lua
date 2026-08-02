local States = require("PalTR.domain.states")
local Clock = require("PalTR.core.clock")
local Result = require("PalTR.core.result")

local Rules = {}

function Rules.declare_war(relation, requester, config)
    if relation.state == States.ALLIANCE
        or relation.state == States.ALLIANCE_PENDING then
        return Result.err("ALLIANCE_ACTIVE", "Ittifak varken savas acilamaz")
    end

    if relation.state == States.WAR
        or relation.state == States.WAR_PENDING then
        return Result.err("WAR_EXISTS", "Savas zaten aktif veya hazirlikta")
    end

    relation.previous_state = relation.state
    relation.state = States.WAR_PENDING
    relation.requested_by = requester
    relation.accepted_by = ""
    relation.active_at = Clock.after_minutes(
        config.diplomacy.war_preparation_minutes
    )
    relation.expires_at = relation.active_at +
        config.diplomacy.war_duration_hours * 3600
    relation.updated_at = Clock.now()
    return Result.ok(relation)
end

function Rules.request_ceasefire(relation, requester, config)
    if relation.state ~= States.WAR
        and relation.state ~= States.WAR_PENDING then
        return Result.err("NO_WAR", "Ateşkes icin savas olmali")
    end

    relation.previous_state = relation.state
    relation.state = States.CEASEFIRE_PENDING
    relation.requested_by = requester
    relation.accepted_by = ""
    relation.active_at = 0
    relation.expires_at = Clock.after_hours(
        config.diplomacy.proposal_expiry_hours
    )
    relation.updated_at = Clock.now()
    return Result.ok(relation)
end

function Rules.request_alliance(relation, requester, config)
    if relation.state ~= States.NEUTRAL
        and relation.state ~= States.CEASEFIRE then
        return Result.err(
            "STATE_DENIED",
            "Bu durumda ittifak teklifi yapilamaz"
        )
    end

    relation.previous_state = relation.state
    relation.state = States.ALLIANCE_PENDING
    relation.requested_by = requester
    relation.accepted_by = ""
    relation.active_at = 0
    relation.expires_at = Clock.after_hours(
        config.diplomacy.proposal_expiry_hours
    )
    relation.updated_at = Clock.now()
    return Result.ok(relation)
end

function Rules.accept(relation, accepter)
    if relation.requested_by == accepter then
        return Result.err("SELF_ACCEPT", "Kendi teklifin kabul edilemez")
    end

    if relation.state == States.CEASEFIRE_PENDING then
        relation.state = States.CEASEFIRE
    elseif relation.state == States.ALLIANCE_PENDING then
        relation.state = States.ALLIANCE
    else
        return Result.err("NO_PROPOSAL", "Kabul edilecek teklif yok")
    end

    relation.accepted_by = accepter
    relation.active_at = 0
    relation.expires_at = 0
    relation.updated_at = Clock.now()
    return Result.ok(relation)
end

function Rules.reject(relation, rejecter)
    if relation.requested_by == rejecter then
        return Result.err("SELF_REJECT", "Kendi teklifin reddedilemez")
    end

    if relation.state ~= States.CEASEFIRE_PENDING
        and relation.state ~= States.ALLIANCE_PENDING then
        return Result.err("NO_PROPOSAL", "Reddedilecek teklif yok")
    end

    relation.state = relation.previous_state or States.NEUTRAL
    relation.requested_by = ""
    relation.accepted_by = ""
    relation.active_at = 0
    relation.expires_at = 0
    relation.updated_at = Clock.now()
    return Result.ok(relation)
end

function Rules.tick(relation)
    local now = Clock.now()

    if relation.state == States.WAR_PENDING
        and relation.active_at > 0
        and now >= relation.active_at then
        relation.state = States.WAR
        relation.updated_at = now
        return "WAR_STARTED"
    end

    if relation.state == States.WAR
        and relation.expires_at > 0
        and now >= relation.expires_at then
        relation.state = States.CEASEFIRE
        relation.active_at = 0
        relation.expires_at = 0
        relation.updated_at = now
        return "WAR_ENDED"
    end

    if (relation.state == States.CEASEFIRE_PENDING
        or relation.state == States.ALLIANCE_PENDING)
        and relation.expires_at > 0
        and now >= relation.expires_at then
        relation.state = relation.previous_state or States.NEUTRAL
        relation.requested_by = ""
        relation.accepted_by = ""
        relation.active_at = 0
        relation.expires_at = 0
        relation.updated_at = now
        return "PROPOSAL_EXPIRED"
    end

    return nil
end

return Rules
