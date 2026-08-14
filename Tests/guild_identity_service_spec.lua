package.path = table.concat({
    "Scripts/?.lua",
    "Scripts/?/init.lua",
    package.path
}, ";")

local Service = require("PalTR.services.guild_identity_service")
local TempPath = dofile("Tests/support/temp_path.lua")

local function equal(actual, expected, message)
    if actual ~= expected then
        error(message .. ": expected=" .. tostring(expected) ..
            " actual=" .. tostring(actual))
    end
end

local path = TempPath.prefix("guild_identity_service") .. ".tsv"
os.remove(path)
local config = {
    conquest = {
        operator_roles = {
            LEADER = true,
            DEPUTY_LEADER = true,
            COMMANDER = true
        }
    }
}
local service = Service.new({ guild_identity = path }, config, nil, {
    clock = { now = function() return 123 end }
})

local denied = service:set_identity({
    guild_key = "A", color_id = "azure", emblem_id = "wolf",
    actor_role = "MEMBER"
})
equal(denied.ok, false, "member denied")
equal(denied.error.code, "GUILD_IDENTITY_ROLE_REQUIRED", "role reason")

local selected = service:set_identity({
    guild_key = "A", color_id = "azure", emblem_id = "wolf",
    actor_role = "LEADER", selected_by = "Herakles"
})
equal(selected.ok, true, "identity selected")
equal(selected.value.selected_at, 123, "selection timestamp")
equal(service:has_identity("A"), true, "identity available")

local locked = service:set_identity({
    guild_key = "A", color_id = "red", emblem_id = "lion",
    actor_role = "LEADER"
})
equal(locked.error.code, "GUILD_IDENTITY_LOCKED", "selection locked")

local duplicate = service:set_identity({
    guild_key = "B", color_id = "azure", emblem_id = "eagle",
    actor_role = "COMMANDER"
})
equal(duplicate.error.code, "GUILD_COLOR_TAKEN", "color unique")

local second = service:set_identity({
    guild_key = "B", color_id = "red", emblem_id = "wolf",
    actor_role = "COMMANDER"
})
equal(second.ok, true, "emblem may repeat")

local restored = Service.new({ guild_identity = path }, config)
equal(restored:get("A").color_id, "azure", "color restored")
equal(restored:get("B").emblem_id, "wolf", "emblem restored")
equal(restored:catalog_for("A", "LEADER").locked, true, "catalog locked")
equal(restored:catalog_for("C", "LEADER").can_manage, true, "new guild manages")

os.remove(path)
print("guild_identity_service_spec: ok")
