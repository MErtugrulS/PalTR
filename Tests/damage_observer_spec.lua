package.path = table.concat({
    "Scripts/?.lua",
    "Scripts/?/init.lua",
    package.path
}, ";")

local Observer = require("PalTR.services.damage_observer")

local function equal(actual, expected, message)
    if actual ~= expected then
        error(message .. ": expected=" .. tostring(expected)
            .. " actual=" .. tostring(actual))
    end
end

local logs = {}
local logger = {
    info = function(_, message) logs[#logs + 1] = "I:" .. message end,
    error = function(_, message) logs[#logs + 1] = "E:" .. message end
}
local registry = {
    runtime_players = {
        defender = { pawn_path = "<gecersiz>", guild_key = "GUILD_B" }
    },
    find_by_controller = function()
        return { name = "Attacker", guild_key = "GUILD_A" }
    end
}

local append_count = 0
local allowed = Observer.new(
    "unused.tsv",
    registry,
    { evaluate_player_damage = function()
        return { block = false, reason = "NEUTRAL_PVP", state = "NEUTRAL" }
    end },
    logger
)
allowed._append = function() append_count = append_count + 1 end
allowed:on_enemy_player_damage_request(nil, {
    IsPlayerVsPlayerDamage = true
}, nil)
equal(append_count, 0, "damage audit defaults off")
equal(#logs, 0, "allowed damage does not spam console")

local audited = Observer.new(
    "unused.tsv",
    registry,
    { evaluate_player_damage = function()
        return { block = false, reason = "NEUTRAL_PVP", state = "NEUTRAL" }
    end },
    logger,
    { audit_enabled = true }
)
audited._append = function() append_count = append_count + 1 end
audited:on_enemy_player_damage_request(nil, {
    IsPlayerVsPlayerDamage = true
}, nil)
equal(append_count, 1, "explicit audit records damage")

local blocked = Observer.new(
    "unused.tsv",
    registry,
    { evaluate_player_damage = function()
        return { block = true, reason = "ACTIVE_ALLIANCE", state = "ALLIANCE" }
    end },
    logger
)
local info = {
    IsPlayerVsPlayerDamage = true,
    set = function() end
}
blocked:on_enemy_player_damage_request(nil, info, nil)
blocked:on_enemy_player_damage_request(nil, info, nil)
equal(info.NoDamage, true, "blocked damage still applies no-damage")
equal(#logs, 1, "repeated block log is throttled")

print("damage_observer_spec: ok")
