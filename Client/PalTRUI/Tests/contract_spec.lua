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
    }
}

local accepted, accept_error = Contract.validate(valid)
equal(accepted, true, "server snapshot accepted")
equal(accept_error, nil, "valid snapshot has no error")
equal(Contract.accepts(valid), true, "accepts uses validation")

local malformed_relation = {
    schema_version = 1,
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
    player = {},
    guild = {},
    members = {},
    relations = { { actions = { { id = 1, label = "Hatali" } } } }
}
local action_accepted, action_error = Contract.validate(malformed_action)
equal(action_accepted, false, "malformed action rejected")
equal(action_error, "relations.actions.item", "action error path")

print("PALTR_UI_CONTRACT_TEST_OK")
