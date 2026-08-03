local States = require("PalTR.domain.states")
local Clock = require("PalTR.core.clock")
local Result = require("PalTR.core.result")

local Rules = {}

local function restore_previous_state(relation)
    local restored = relation.previous_state or States.NEUTRAL

    relation.state = restored
    relation.previous_state = States.NEUTRAL
    relation.requested_by = ""
    relation.accepted_by = ""
    relation.expires_at = 0

    if restored ~= States.WAR_PENDING then
        relation.active_at = 0
    end

    relation.updated_at = Clock.now()
end

function Rules.declare_war(relation, requester, config)
    if relation.state ~= States.NEUTRAL then
        return Result.err(
            "WAR_REQUIRES_NEUTRAL",
            "Savas yalnizca tarafsiz bir klana acilabilir"
        )
    end

    relation.previous_state = States.NEUTRAL
    relation.state = States.WAR_PENDING
    relation.requested_by = requester
    relation.accepted_by = ""
    relation.active_at = Clock.after_minutes(
        config.diplomacy.war_preparation_minutes
    )

    -- Faz-03: Savas suresizdir.
    relation.expires_at = 0
    relation.updated_at = Clock.now()

    return Result.ok(relation)
end

function Rules.request_ceasefire(relation, requester, config)
    if relation.state ~= States.WAR
        and relation.state ~= States.WAR_PENDING then
        return Result.err(
            "NO_WAR",
            "Ateskes teklifi icin savas veya savas hazirligi olmali"
        )
    end

    relation.previous_state = relation.state
    relation.state = States.CEASEFIRE_PENDING
    relation.requested_by = requester
    relation.accepted_by = ""

    -- Savas hazirligindaki zaman korunur.
    if relation.previous_state ~= States.WAR_PENDING then
        relation.active_at = 0
    end

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
        return Result.err(
            "SELF_ACCEPT",
            "Kendi teklifin kabul edilemez"
        )
    end

    if relation.state == States.CEASEFIRE_PENDING then
        relation.previous_state = States.WAR
        relation.state = States.CEASEFIRE
    elseif relation.state == States.ALLIANCE_PENDING then
        relation.previous_state = relation.previous_state
            or States.NEUTRAL
        relation.state = States.ALLIANCE
    else
        return Result.err(
            "NO_PROPOSAL",
            "Kabul edilecek teklif yok"
        )
    end

    relation.requested_by = ""
    relation.accepted_by = accepter
    relation.active_at = 0
    relation.expires_at = 0
    relation.updated_at = Clock.now()

    return Result.ok(relation)
end

function Rules.reject(relation, rejecter)
    if relation.requested_by == rejecter then
        return Result.err(
            "SELF_REJECT",
            "Kendi teklifin reddedilemez"
        )
    end

    if relation.state ~= States.CEASEFIRE_PENDING
        and relation.state ~= States.ALLIANCE_PENDING then
        return Result.err(
            "NO_PROPOSAL",
            "Reddedilecek teklif yok"
        )
    end

    restore_previous_state(relation)

    return Result.ok(relation)
end

function Rules.cancel(relation, requester)
    if relation.state ~= States.CEASEFIRE_PENDING
        and relation.state ~= States.ALLIANCE_PENDING then
        return Result.err(
            "NO_PENDING_PROPOSAL",
            "Iptal edilecek bekleyen teklif yok"
        )
    end

    if relation.requested_by ~= requester then
        return Result.err(
            "NOT_REQUESTER",
            "Yalnizca teklifi yapan klan iptal edebilir"
        )
    end

    restore_previous_state(relation)

    return Result.ok(relation)
end

function Rules.return_neutral(relation)
    if relation.state ~= States.ALLIANCE
        and relation.state ~= States.CEASEFIRE then
        return Result.err(
            "NO_ACTIVE_PEACE",
            "Aktif ittifak veya ateskes yok"
        )
    end

    relation.previous_state = relation.state
    relation.state = States.NEUTRAL
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

        relation.previous_state = States.WAR_PENDING
        relation.state = States.WAR
        relation.requested_by = ""
        relation.accepted_by = ""
        relation.active_at = now
        relation.expires_at = 0
        relation.updated_at = now

        return "WAR_STARTED"
    end

    -- Eski 24 saatlik savas kayitlarini suresiz savasa cevirir.
    if relation.state == States.WAR
        and relation.expires_at > 0 then

        relation.expires_at = 0
        relation.updated_at = now

        return "WAR_MADE_INDEFINITE"
    end

    if (relation.state == States.CEASEFIRE_PENDING
        or relation.state == States.ALLIANCE_PENDING)
        and relation.expires_at > 0
        and now >= relation.expires_at then

        restore_previous_state(relation)

        return "PROPOSAL_EXPIRED"
    end

    return nil
end

return Rules