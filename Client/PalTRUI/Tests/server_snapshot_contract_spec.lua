local Contract = require("contract")

package.loaded["PalTR.core.clock"] = {
    now = function() return 500 end
}
local UISnapshotService = require("PalTR.services.ui_snapshot_service")

local function equal(actual, expected, label)
    if actual ~= expected then
        error(string.format(
            "%s | expected=%s actual=%s",
            label,
            tostring(expected),
            tostring(actual)
        ))
    end
end

local registry = {
    guilds = {
        own = { name = "Anka" },
        other = { name = "Rakipler" }
    },
    players = {
        p1 = {
            name = "Ada",
            guild_key = "own",
            role = 1,
            is_master = true
        }
    },
    runtime_players = {
        p1 = { online = true }
    },
    runtime_guilds = {
        other = {}
    }
}
local diplomacy = {
    relations_for = function(_, guild_key)
        equal(guild_key, "own", "server receives own guild")
        return {
            {
                guild_a = "own",
                guild_b = "other",
                state = "NEUTRAL",
                previous_state = "NEUTRAL",
                requested_by = "",
                accepted_by = "",
                active_at = 0,
                expires_at = 0,
                note = ""
            }
        }
    end
}
local actions = {
    for_relation = function()
        return {
            can_manage = true,
            reason = "",
            actions = {
                { id = "DECLARE_WAR", label = "Savas Ilan Et" }
            }
        }
    end
}

local service = UISnapshotService.new(registry, diplomacy, actions)
local snapshot = service:build({
    name = "Ada",
    guild_key = "own",
    role = 1,
    is_master = true
})

local accepted, contract_error = Contract.validate(snapshot)
equal(accepted, true, "server snapshot accepted by client")
equal(contract_error, nil, "server snapshot has no contract error")
equal(snapshot.schema_version, Contract.SCHEMA_VERSION, "schema versions match")
equal(snapshot.generated_at, 500, "server timestamp preserved")
equal(snapshot.guild.name, "Anka", "server guild preserved")
equal(snapshot.guilds[1].key, "other", "server guild catalog preserved")
equal(snapshot.guilds[1].active, true, "runtime guild marked active")
equal(snapshot.guilds[1].member_count, 0, "catalog member count")
equal(snapshot.members[1].online, true, "server member shape preserved")
equal(snapshot.relations[1].guild_key, "other", "server relation preserved")
equal(snapshot.relations[1].actions[1].id, "DECLARE_WAR",
    "server action preserved")

print("PALTR_UI_SERVER_SNAPSHOT_CONTRACT_TEST_OK")
