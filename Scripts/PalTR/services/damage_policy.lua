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
    local protection = self.config.protection or {}

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
        if protection.block_friendly_fire == true then
            return decision(
                true,
                "SAME_GUILD",
                "SAME_GUILD"
            )
        end

        return decision(
            false,
            "FRIENDLY_FIRE_ALLOWED",
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

    local relation =
        self.diplomacy.relations[
            pair.value.key
        ]

    local state =
        relation and relation.state
        or States.NEUTRAL

    if state == States.WAR then
        return decision(
            false,
            "ACTIVE_WAR",
            state
        )
    end

    if protection.block_non_war_damage == false then
        return decision(
            false,
            "NON_WAR_BLOCK_DISABLED",
            state
        )
    end

    return decision(
        true,
        "RELATION_NOT_WAR",
        state
    )
end

return Policy
