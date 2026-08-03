local States = require("PalTR.domain.states")
local Clock = require("PalTR.core.clock")
local Result = require("PalTR.core.result")

local Rules = {}

local function reset_request(relation)
    relation.requested_by = ""
    relation.accepted_by = ""
end

local function restore_previous_state(relation)
    local restored = relation.previous_state or States.NEUTRAL
    local now = Clock.now()

    relation.state = restored
    reset_request(relation)

    if restored == States.WAR then
        -- active_at savasin baslangic veya yeniden baslama zamanidir.
        if relation.active_at <= 0 then
            relation.active_at = now
        end

        relation.expires_at = 0

    elseif restored == States.CEASEFIRE then
        -- Baris teklifi sırasında eski ateskes bitis zamani
        -- gecici olarak active_at alaninda saklanir.
        local ceasefire_expires_at =
            tonumber(relation.active_at) or 0

        relation.active_at = 0
        relation.expires_at = ceasefire_expires_at

    else
        relation.active_at = 0
        relation.expires_at = 0
    end

    relation.previous_state = States.NEUTRAL
    relation.updated_at = now
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

    relation.expires_at = 0
    relation.updated_at = Clock.now()

    return Result.ok(relation)
end

function Rules.request_ceasefire(relation, requester, config)
    if relation.state ~= States.WAR then
        return Result.err(
            "NO_ACTIVE_WAR",
            "Ateskes teklifi yalnizca aktif savasta yapilabilir"
        )
    end

    relation.previous_state = States.WAR
    relation.state = States.CEASEFIRE_PENDING
    relation.requested_by = requester
    relation.accepted_by = ""

    -- Savas baslangic zamani active_at alaninda korunur.
    relation.expires_at = Clock.after_hours(
        config.diplomacy.proposal_expiry_hours
    )

    relation.updated_at = Clock.now()

    return Result.ok(relation)
end

function Rules.request_peace(relation, requester, config)
    if relation.state ~= States.WAR
        and relation.state ~= States.CEASEFIRE then

        return Result.err(
            "NO_WAR_OR_CEASEFIRE",
            "Baris teklifi icin savas veya ateskes olmali"
        )
    end

    local previous = relation.state

    relation.previous_state = previous
    relation.state = States.PEACE_PENDING
    relation.requested_by = requester
    relation.accepted_by = ""

    if previous == States.CEASEFIRE then
        -- Ateskesin asil bitis zamanini gecici olarak sakla.
        relation.active_at = relation.expires_at
    end

    relation.expires_at = Clock.after_hours(
        config.diplomacy.proposal_expiry_hours
    )

    relation.updated_at = Clock.now()

    return Result.ok(relation)
end

function Rules.request_alliance(relation, requester, config)
    if relation.state ~= States.NEUTRAL then
        return Result.err(
            "ALLIANCE_REQUIRES_NEUTRAL",
            "Ittifak yalnizca tarafsiz klanlar arasinda kurulabilir"
        )
    end

    relation.previous_state = States.NEUTRAL
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

function Rules.accept(relation, accepter, config)
    if relation.requested_by == accepter then
        return Result.err(
            "SELF_ACCEPT",
            "Kendi teklifin kabul edilemez"
        )
    end

    local now = Clock.now()

    if relation.state == States.CEASEFIRE_PENDING then
        relation.previous_state = States.WAR
        relation.state = States.CEASEFIRE

        relation.active_at = now
        relation.expires_at = Clock.after_hours(
            config.diplomacy.ceasefire_duration_hours
        )

    elseif relation.state == States.PEACE_PENDING then
        relation.previous_state = relation.previous_state
            or States.WAR

        relation.state = States.NEUTRAL
        relation.active_at = 0
        relation.expires_at = 0

    elseif relation.state == States.ALLIANCE_PENDING then
        relation.previous_state = States.NEUTRAL
        relation.state = States.ALLIANCE
        relation.active_at = 0
        relation.expires_at = 0

    else
        return Result.err(
            "NO_PROPOSAL",
            "Kabul edilecek teklif yok"
        )
    end

    relation.requested_by = ""
    relation.accepted_by = accepter
    relation.updated_at = now

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
        and relation.state ~= States.PEACE_PENDING
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
        and relation.state ~= States.PEACE_PENDING
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

function Rules.break_ceasefire(relation)
    local active_ceasefire =
        relation.state == States.CEASEFIRE

    local peace_during_ceasefire =
        relation.state == States.PEACE_PENDING
        and relation.previous_state == States.CEASEFIRE

    if not active_ceasefire
        and not peace_during_ceasefire then

        return Result.err(
            "NO_ACTIVE_CEASEFIRE",
            "Bozulacak aktif ateskes yok"
        )
    end

    relation.previous_state = States.CEASEFIRE
    relation.state = States.WAR
    reset_request(relation)

    relation.active_at = Clock.now()
    relation.expires_at = 0
    relation.updated_at = Clock.now()

    return Result.ok(relation)
end

function Rules.return_neutral(relation)
    if relation.state ~= States.ALLIANCE then
        if relation.state == States.CEASEFIRE
            or relation.state == States.PEACE_PENDING
            or relation.state == States.WAR then

            return Result.err(
                "WAR_REQUIRES_PEACE",
                "Savas yalnizca karsilikli baris anlasmasiyla sona erdirilebilir"
            )
        end

        return Result.err(
            "NO_ACTIVE_ALLIANCE",
            "Bitirilecek aktif ittifak yok"
        )
    end

    relation.previous_state = States.ALLIANCE
    relation.state = States.NEUTRAL
    reset_request(relation)

    relation.active_at = 0
    relation.expires_at = 0
    relation.updated_at = Clock.now()

    return Result.ok(relation)
end

function Rules.tick(relation, config)
    local now = Clock.now()

    if relation.state == States.WAR_PENDING
        and relation.active_at > 0
        and now >= relation.active_at then

        relation.previous_state = States.WAR_PENDING
        relation.state = States.WAR
        reset_request(relation)

        relation.active_at = now
        relation.expires_at = 0
        relation.updated_at = now

        return "WAR_STARTED"
    end

    -- Eski 24 saatlik savas kayitlarini suresiz hale getir.
    if relation.state == States.WAR
        and relation.expires_at > 0 then

        relation.expires_at = 0
        relation.updated_at = now

        return "WAR_MADE_INDEFINITE"
    end

    -- Eski Faz-03 ateskes kaydinda sure yoksa
    -- 12 saatlik zamanlayici olustur.
    if relation.state == States.CEASEFIRE
        and relation.expires_at <= 0 then

        relation.active_at = now
        relation.expires_at = Clock.after_hours(
            config.diplomacy.ceasefire_duration_hours
        )

        relation.updated_at = now

        return "CEASEFIRE_TIMER_REPAIRED"
    end

    if relation.state == States.CEASEFIRE
        and relation.expires_at > 0
        and now >= relation.expires_at then

        relation.previous_state = States.CEASEFIRE
        relation.state = States.WAR
        reset_request(relation)

        relation.active_at = now
        relation.expires_at = 0
        relation.updated_at = now

        return "CEASEFIRE_ENDED"
    end

    if (relation.state == States.CEASEFIRE_PENDING
        or relation.state == States.PEACE_PENDING
        or relation.state == States.ALLIANCE_PENDING)
        and relation.expires_at > 0
        and now >= relation.expires_at then

        restore_previous_state(relation)

        return "PROPOSAL_EXPIRED"
    end

    return nil
end

return Rules