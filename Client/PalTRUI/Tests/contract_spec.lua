local Contract = require("contract")

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

local valid = {
    schema_version = 1,
    generated_at = 100,
    player = { name = "Ada", guild_key = "own", role = 1, is_master = true },
    guild = { key = "own", name = "Anka" },
    members = {
        { key = "p1", name = "Ada", role = 1, is_master = true, online = true }
    },
    relations = {
        {
            guild_key = "other",
            guild_name = "Diger",
            state = "NEUTRAL",
            can_manage = true,
            actions = {
                { id = "DECLARE_WAR", label = "Savas Ilan Et" }
            }
        }
    },
    territories = {
        nodes = {
            {
                node_id = "CAPITAL", node_type = "CAPITAL",
                controller_guild = "own", x = 0, y = 0, z = 0,
                radius = 250
            }
        },
        boundaries = {
            {
                boundary_id = "own::001", controller_guild = "own",
                points = {
                    { x = 0, y = 0 }, { x = 1, y = 0 }, { x = 1, y = 1 }
                }
            }
        }
    }
}

local accepted, accept_error = Contract.validate(valid)
equal(accepted, true, "server snapshot accepted")
equal(accept_error, nil, "valid snapshot has no error")
equal(Contract.accepts(valid), true, "accepts uses validation")

local malformed_relation = {
    schema_version = 1,
    generated_at = 100,
    player = {},
    guild = {},
    members = {},
    relations = { "invalid" }
}
local relation_accepted, relation_error =
    Contract.validate(malformed_relation)
equal(relation_accepted, false, "malformed relation rejected")
equal(relation_error, "relations.item", "relation error path")

local malformed_action = {
    schema_version = 1,
    generated_at = 100,
    player = {},
    guild = {},
    members = {},
    relations = { { actions = { { id = 1, label = "Hatali" } } } }
}
local action_accepted, action_error = Contract.validate(malformed_action)
equal(action_accepted, false, "malformed action rejected")
equal(action_error, "relations.actions.item", "action error path")

local malformed_territory = {
    schema_version = 1,
    generated_at = 100,
    player = {}, guild = {}, members = {}, relations = {},
    territories = {
        nodes = {},
        boundaries = {
            {
                boundary_id = "own::001", controller_guild = "own",
                points = { { x = "bad", y = 0 }, { x = 1, y = 0 }, { x = 1, y = 1 } }
            }
        }
    }
}
local territory_accepted, territory_error =
    Contract.validate(malformed_territory)
equal(territory_accepted, false, "malformed territory rejected")
equal(territory_error, "territories.boundaries.points",
    "territory error path")

local v2 = {
    schema_version = 2,
    generated_at = 100,
    player = {}, guild = { color_id = "azure", emblem_id = "wolf" },
    guilds = {}, members = {}, relations = {},
    guild_identity = {
        palette_version = 1,
        selected_color_id = "azure",
        selected_emblem_id = "wolf",
        locked = true,
        can_manage = false,
        colors = {
            { id = "azure", hex = "#2F80ED", available = true }
        },
        emblems = { { id = "wolf", name = "Kurt" } }
    }
}
equal(Contract.validate(v2), true, "v2 guild identity accepted")
v2.guild_identity = nil
local missing_identity, missing_identity_error = Contract.validate(v2)
equal(missing_identity, false, "v2 identity required")
equal(missing_identity_error, "guild_identity", "v2 identity error")
valid.schema_version = 3
local future_accepted, future_error = Contract.validate(valid)
equal(future_accepted, false, "future schema rejected")
equal(future_error, "schema_version", "future schema error")

print("PALTR_UI_CONTRACT_TEST_OK")
