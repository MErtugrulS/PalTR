local PairKey = require("PalTR.domain.pair_key")
local States = require("PalTR.domain.states")

local Policy = {}
Policy.__index = Policy

local function decision(block, reason, state)
    return {
        block = block == true,
        reason = reason or "",
        state = state or ""
    }
end

function Policy.new(config, diplomacy)
    return setmetatable({
        config = config,
        diplomacy = diplomacy
    }, Policy)
end

function Policy:evaluate_player_damage(
    attacker,
    defender
)
    local runtime = self.config.runtime or {}

    if runtime.enable_damage_enforcement ~= true then
        return decision(
            false,
            "ENFORCEMENT_DISABLED",
            ""
        )
    end

    if attacker == nil or defender == nil then
        return decision(
            true,
            "PLAYER_MAPPING_MISSING",
            ""
        )
    end

    local attacker_guild =
        attacker.guild_key or ""

    local defender_guild =
        defender.guild_key or ""

    if attacker_guild == ""
        or defender_guild == "" then

        return decision(
            true,
            "GUILD_MAPPING_MISSING",
            ""
        )
    end

    if attacker_guild == defender_guild then
        return decision(
            false,
            "SAME_GUILD_PVP",
            "SAME_GUILD"
        )
    end

    local pair = PairKey.create(
        attacker_guild,
        defender_guild
    )

    if not pair.ok then
        return decision(
            true,
            "INVALID_GUILD_PAIR",
            ""
        )
    end

    local relations =
        self.diplomacy.relations or {}

    local relation =
        relations[pair.value.key]

    local state =
        relation and relation.state
        or States.NEUTRAL

    if state == States.NEUTRAL then
        return decision(
            false,
            "NEUTRAL_PVP",
            state
        )
    end

    if state == States.ALLIANCE_PENDING then
        return decision(
            false,
            "ALLIANCE_PROPOSAL_NEUTRAL_PVP",
            state
        )
    end

    if state == States.ALLIANCE then
        return decision(
            true,
            "ACTIVE_ALLIANCE",
            state
        )
    end

    if state == States.WAR_PENDING then
        return decision(
            true,
            "WAR_PREPARATION",
            state
        )
    end

    if state == States.WAR then
        return decision(
            false,
            "ACTIVE_WAR",
            state
        )
    end

    if state == States.CEASEFIRE_PENDING then
        return decision(
            false,
            "CEASEFIRE_PROPOSAL_ACTIVE_WAR",
            state
        )
    end

    if state == States.CEASEFIRE then
        return decision(
            true,
            "ACTIVE_CEASEFIRE",
            state
        )
    end

    if state == States.PEACE_PENDING then
        local previous =
            relation and relation.previous_state
            or ""

        if previous == States.CEASEFIRE then
            return decision(
                true,
                "PEACE_PROPOSAL_DURING_CEASEFIRE",
                state
            )
        end

        return decision(
            false,
            "PEACE_PROPOSAL_DURING_WAR",
            state
        )
    end

    return decision(
        true,
        "UNKNOWN_RELATION_STATE",
        state
    )
end

return Policy
