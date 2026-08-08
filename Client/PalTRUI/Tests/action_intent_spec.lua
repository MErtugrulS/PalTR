local ActionIntent = require("action_intent")

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

local function model(can_manage)
    return {
        generated_at = 12345,
        views = {
            DIPLOMACY = {
                selected_relation = {
                    guild = { key = "guild-other" },
                    permissions = {
                        can_manage = can_manage,
                        reason = "Yalnizca klan lideri yonetebilir."
                    },
                    actions = {
                        { id = "DECLARE_WAR", label = "Savas Ilan Et" }
                    }
                }
            }
        }
    }
end

local intent, error_message = ActionIntent.build(
    model(true),
    "DECLARE_WAR"
)
equal(error_message, nil, "offered action has no error")
equal(intent.kind, "DIPLOMACY_ACTION", "intent kind")
equal(intent.guild_key, "guild-other", "intent guild")
equal(intent.action_id, "DECLARE_WAR", "intent action")
equal(intent.snapshot_generated_at, 12345, "intent snapshot time")

local missing, missing_error = ActionIntent.build(model(true), "PEACE")
equal(missing, nil, "unoffered action rejected")
equal(
    missing_error,
    "Aksiyon guncel sunucu snapshotinda sunulmuyor.",
    "unoffered action error"
)

local forbidden, forbidden_error = ActionIntent.build(
    model(false),
    "DECLARE_WAR"
)
equal(forbidden, nil, "permission denied")
equal(
    forbidden_error,
    "Yalnizca klan lideri yonetebilir.",
    "server reason preserved"
)

local missing_guild_model = model(true)
missing_guild_model.views.DIPLOMACY.selected_relation.guild.key = ""
local missing_guild, missing_guild_error = ActionIntent.build(
    missing_guild_model,
    "DECLARE_WAR"
)
equal(missing_guild, nil, "missing guild rejected")
equal(
    missing_guild_error,
    "Diplomasi klan kimligi bulunamadi.",
    "missing guild error"
)

print("PALTR_UI_ACTION_INTENT_TEST_OK")
