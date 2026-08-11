package.path = table.concat({
    "Scripts/?.lua",
    "Scripts/?/init.lua",
    package.path
}, ";")

local Adapter = require("PalTR.runtime.build_object_adapter")

local function equal(actual, expected, message)
    if actual ~= expected then
        error(message .. ": expected=" .. tostring(expected) ..
            " actual=" .. tostring(actual))
    end
end

local function actor(path, group, id, x)
    return {
        valid = true,
        path = path,
        group = group,
        model = { valid = true, id = id },
        location = { X = x, Y = 0, Z = 0 }
    }
end

local actors = {
    actor("BP_BuildObject_WorkBench_C A", "GROUP_B", "ENEMY", 100),
    actor("BP_BuildObject_ItemChest_C B", "GROUP_A", "CHEST", 150),
    actor("BP_BuildObject_WorkBench_C C", "GROUP_A", "CAMP", 1000)
}

local ue = {}
function ue.unwrap(value) return value end
function ue.valid(value) return value and value.valid == true end
function ue.read(value, field) return value and value[field] end
function ue.guid(value) return tostring(value or "") end
function ue.full_name(value) return value.path or "Model" end
function ue.find_all(name)
    equal(name, "PalBuildObject", "build object class")
    return actors
end
function ue.call(object, method)
    if method == "IsAvailable" then return true, object.valid end
    if method == "GetGroupIdBelongTo" then return true, object.group end
    if method == "GetModel" then return true, object.model end
    if method == "GetModelId" then return true, object.id end
    if method == "K2_GetActorLocation" then return true, object.location end
    return false, nil
end

local registry = { guilds = { GROUP_A = { key = "A" }, GROUP_B = { key = "B" } } }
function registry:find_guild_by_id(id) return self.guilds[id] end

local config = {
    world_units_per_meter = 100,
    siege_camp_interaction_radius_meters = 20,
    siege_camp_actor_class_tokens = { "BP_BuildObject_WorkBench_C" }
}
local player = {
    guild_key = "A",
    pawn = { valid = true, location = { X = 1100, Y = 0, Z = 0 } }
}

local adapter = Adapter.new(ue)
local result = adapter:nearest_owned_siege_camp(player, registry, config)
equal(result.ok, true, "own workbench found")
equal(result.value.reference, "CAMP", "enemy and wrong class ignored")
equal(result.value.distance_meters, 1, "distance converted to meters")

player.pawn.location.X = 5000
result = adapter:nearest_owned_siege_camp(player, registry, config)
equal(result.ok, false, "interaction distance enforced")
equal(result.error.code, "OWN_SIEGE_CAMP_NOT_NEAR", "distance error")

config.siege_camp_actor_class_tokens = {}
result = adapter:nearest_owned_siege_camp(player, registry, config)
equal(result.ok, false, "missing class rejected")
equal(result.error.code, "SIEGE_CAMP_CLASS_MISSING", "class config error")

print("build_object_adapter_spec: ok")
