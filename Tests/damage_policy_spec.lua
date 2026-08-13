package.path = table.concat({
    "Scripts/?.lua",
    "Scripts/?/init.lua",
    package.path
}, ";")

local Policy = require("PalTR.services.damage_policy")
local States = require("PalTR.domain.states")

local function equal(actual, expected, message)
    if actual ~= expected then
        error(message .. ": expected=" .. tostring(expected)
            .. " actual=" .. tostring(actual))
    end
end

local config = {
    runtime = { enable_damage_enforcement = true }
}
local diplomacy = { relations = {} }
local policy = Policy.new(config, diplomacy)
local attacker = { guild_key = "GUILD_A" }
local defender = { guild_key = "GUILD_B" }

local function evaluate(state, previous_state)
    diplomacy.relations["GUILD_A::GUILD_B"] = state and {
        state = state,
        previous_state = previous_state
    } or nil
    return policy:evaluate_player_damage(attacker, defender)
end

local function assert_decision(state, previous_state, block, reason)
    local result = evaluate(state, previous_state)
    equal(result.block, block, reason .. " block")
    equal(result.reason, reason, reason .. " reason")
    equal(result.state, state or States.NEUTRAL, reason .. " state")
end

config.runtime.enable_damage_enforcement = false
local disabled = policy:evaluate_player_damage(attacker, defender)
equal(disabled.block, false, "disabled enforcement allows damage")
equal(disabled.reason, "ENFORCEMENT_DISABLED", "disabled reason")
config.runtime.enable_damage_enforcement = true

local missing_player = policy:evaluate_player_damage(nil, defender)
equal(missing_player.block, true, "missing player fails closed")
equal(missing_player.reason, "PLAYER_MAPPING_MISSING", "missing player reason")

local missing_guild = policy:evaluate_player_damage({}, defender)
equal(missing_guild.block, true, "missing guild fails closed")
equal(missing_guild.reason, "GUILD_MAPPING_MISSING", "missing guild reason")

local same_guild = policy:evaluate_player_damage(
    attacker,
    { guild_key = "GUILD_A" }
)
equal(same_guild.block, false, "same guild keeps game damage rules")
equal(same_guild.reason, "SAME_GUILD_PVP", "same guild reason")

assert_decision(nil, nil, false, "NEUTRAL_PVP")
assert_decision(
    States.ALLIANCE_PENDING,
    States.NEUTRAL,
    false,
    "ALLIANCE_PROPOSAL_NEUTRAL_PVP"
)
assert_decision(States.ALLIANCE, States.NEUTRAL, true, "ACTIVE_ALLIANCE")
assert_decision(States.WAR_PENDING, States.NEUTRAL, true, "WAR_PREPARATION")
assert_decision(States.WAR, States.NEUTRAL, false, "ACTIVE_WAR")
assert_decision(
    States.CEASEFIRE_PENDING,
    States.WAR,
    false,
    "CEASEFIRE_PROPOSAL_ACTIVE_WAR"
)
assert_decision(States.CEASEFIRE, States.WAR, true, "ACTIVE_CEASEFIRE")
assert_decision(
    States.PEACE_PENDING,
    States.WAR,
    false,
    "PEACE_PROPOSAL_DURING_WAR"
)
assert_decision(
    States.PEACE_PENDING,
    States.CEASEFIRE,
    true,
    "PEACE_PROPOSAL_DURING_CEASEFIRE"
)
assert_decision("INVALID_STATE", "", true, "UNKNOWN_RELATION_STATE")

print("damage_policy_spec: ok")
