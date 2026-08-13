package.path = table.concat({
    "Scripts/?.lua",
    "Scripts/?/init.lua",
    package.path
}, ";")

local Rules = require("PalTR.domain.relation_rules")
local States = require("PalTR.domain.states")

local function equal(actual, expected, message)
    if actual ~= expected then
        error(message .. ": expected=" .. tostring(expected) ..
            " actual=" .. tostring(actual))
    end
end

local config = {
    diplomacy = {
        proposal_expiry_hours = 24
    }
}

local ceasefire_pending = {
    state = States.CEASEFIRE_PENDING,
    previous_state = States.WAR,
    requested_by = "GUILD_A",
    accepted_by = "",
    active_at = 100,
    expires_at = 200,
    updated_at = 100
}

local accepted = Rules.accept(
    ceasefire_pending,
    "GUILD_B",
    config
)
equal(accepted.ok, true, "ceasefire accepted")
equal(ceasefire_pending.state, States.CEASEFIRE, "ceasefire state")
equal(ceasefire_pending.expires_at, 0, "ceasefire is indefinite")

local legacy = {
    state = States.CEASEFIRE,
    previous_state = States.WAR,
    requested_by = "",
    accepted_by = "",
    active_at = 100,
    expires_at = 9999999999,
    updated_at = 100
}

equal(
    Rules.tick(legacy, config),
    "CEASEFIRE_MADE_INDEFINITE",
    "legacy ceasefire migration"
)
equal(legacy.state, States.CEASEFIRE, "legacy ceasefire remains active")
equal(legacy.expires_at, 0, "legacy timer cleared")

local peace = {
    state = States.CEASEFIRE,
    previous_state = States.WAR,
    requested_by = "",
    accepted_by = "",
    active_at = 1234,
    expires_at = 0,
    updated_at = 1234
}

equal(
    Rules.request_peace(peace, "GUILD_A", config).ok,
    true,
    "peace requested during ceasefire"
)
Rules.reject(peace, "GUILD_B")
equal(peace.state, States.CEASEFIRE, "ceasefire restored")
equal(peace.active_at, 1234, "ceasefire start preserved")
equal(peace.expires_at, 0, "restored ceasefire remains indefinite")

local defeated = {
    state = States.WAR,
    previous_state = States.NEUTRAL,
    requested_by = "GUILD_A",
    accepted_by = "",
    active_at = 100,
    expires_at = 0,
    updated_at = 100
}

equal(
    Rules.resolve_capital_defeat(defeated).ok,
    true,
    "capital defeat resolves war"
)
equal(defeated.state, States.NEUTRAL, "capital defeat returns neutral")
equal(defeated.active_at, 0, "capital defeat clears war clock")

local malformed_pending = {
    state = States.ALLIANCE_PENDING,
    previous_state = "",
    requested_by = "GUILD_A",
    accepted_by = "",
    active_at = 0,
    expires_at = 1,
    updated_at = 1
}
equal(
    Rules.tick(malformed_pending, config),
    "PROPOSAL_EXPIRED",
    "malformed legacy proposal expires"
)
equal(
    malformed_pending.state,
    States.NEUTRAL,
    "empty previous state fails safe to neutral"
)

print("relation_rules_spec: ok")
