local RelationNavigator = require("relation_navigator")

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

local model = {
    active_tab = "DIPLOMACY",
    selected_guild = "guild-b",
    views = {
        DIPLOMACY = {
            relations = {
                { guild = { key = "guild-a" } },
                { guild = { key = "guild-b" } },
                { guild = { key = "guild-c" } }
            }
        },
        ALLIANCE = {
            relations = {
                { guild = { key = "guild-a" } },
                { guild = { key = "guild-c" } }
            }
        }
    }
}
local selected = {}
local controller = {
    model = function() return model end,
    select_guild = function(_, guild_key)
        table.insert(selected, guild_key)
        model.selected_guild = guild_key
        return true, model, true
    end
}

local next_ok, next_model, next_error =
    RelationNavigator.select(controller, 1)
equal(next_ok, true, "next relation selected")
equal(next_error, nil, "next relation has no error")
equal(selected[1], "guild-c", "next guild dispatched")
equal(next_model.selected_guild, "guild-c", "next guild returned")

local wrapped_ok = RelationNavigator.select(controller, 1)
equal(wrapped_ok, true, "next relation wraps")
equal(selected[2], "guild-a", "next wrap target")

local previous_ok = RelationNavigator.select(controller, -1)
equal(previous_ok, true, "previous relation selected")
equal(selected[3], "guild-c", "previous wrap target")

model.active_tab = "ALLIANCE"
model.selected_guild = "guild-c"
local alliance_ok = RelationNavigator.select(controller, -1)
equal(alliance_ok, true, "alliance relation selected")
equal(selected[4], "guild-a", "alliance list used")

model.active_tab = "CLAN"
local unsupported, _, unsupported_error =
    RelationNavigator.select(controller, 1)
equal(unsupported, false, "non-relation tab rejected")
equal(unsupported_error, "Aktif sekmede iliski listesi yok.",
    "non-relation tab error")

model.active_tab = "DIPLOMACY"
model.views.DIPLOMACY.relations = {}
local empty, _, empty_error = RelationNavigator.select(controller, 1)
equal(empty, false, "empty relation list rejected")
equal(empty_error, "Secilebilir iliski kaydi bulunamadi.",
    "empty relation error")

local unavailable, _, unavailable_error = RelationNavigator.select(nil, 1)
equal(unavailable, false, "missing controller rejected")
equal(unavailable_error, "UI sunum controller'i hazir degil.",
    "missing controller error")

print("PALTR_UI_RELATION_NAVIGATOR_TEST_OK")
