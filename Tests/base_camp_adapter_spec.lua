package.path = table.concat({
    "Scripts/?.lua",
    "Scripts/?/init.lua",
    package.path
}, ";")

local Adapter = require("PalTR.runtime.base_camp_adapter")

local function equal(actual, expected, message)
    if actual ~= expected then
        error(message .. ": expected=" .. tostring(expected) ..
            " actual=" .. tostring(actual))
    end
end

local function model(id, group, owner, x, name)
    return {
        valid = true,
        id = id,
        group = group,
        owner = owner,
        transform = { Translation = { X = x, Y = 0, Z = 0 } },
        name = name
    }
end

local models = {
    model("BASE_A", "GROUP_A", "PALBOX_A", 1000, "Alpha"),
    model("BASE_B", "GROUP_B", "PALBOX_B", 200, "Beta")
}

local fake_ue = {}
function fake_ue.unwrap(value) return value end
function fake_ue.valid(value) return value and value.valid == true end
function fake_ue.read(value, field) return value and value[field] end
function fake_ue.guid(value) return tostring(value or "") end
function fake_ue.text(value) return tostring(value or "") end
function fake_ue.full_name(value) return "Model " .. tostring(value.id) end
function fake_ue.find_all(class_name)
    equal(class_name, "PalBaseCampModel", "scan class")
    return models
end
function fake_ue.call(object, method)
    if method == "IsAvailable" then return true, object.valid end
    if method == "GetId" then return true, object.id end
    if method == "GetGroupIdBelongTo" then return true, object.group end
    if method == "GetOwnerMapObjectInstanceId" then return true, object.owner end
    if method == "GetTransform" then return true, object.transform end
    if method == "GetBaseCampName" then return true, object.name end
    if method == "K2_GetActorLocation" then return true, object.location end
    return false, nil
end

local registry = { guilds = { GROUP_A = { key = "A" }, GROUP_B = { key = "B" } } }
function registry:find_guild_by_id(id) return self.guilds[id] end

local config = {
    world_units_per_meter = 100,
    registration_interaction_radius_meters = 20
}

local adapter = Adapter.new(fake_ue)
local scanned = adapter:scan(registry, config)
equal(scanned.ok, true, "scan succeeds")
equal(#scanned.value, 2, "two camps")
equal(scanned.value[1].x, 10, "centimeters converted to meters")
equal(scanned.value[1].flag_reference, "PALBOX_A", "owner reference")

local player = {
    guild_key = "A",
    pawn = { valid = true, location = { X = 1100, Y = 0, Z = 0 } }
}

local nearest = adapter:nearest_owned(player, registry, config)
equal(nearest.ok, true, "own nearest camp found")
equal(nearest.value.node_id, "BASE_A", "enemy nearer camp ignored")
equal(nearest.value.distance_meters, 1, "distance uses meters")

player.pawn.location.X = 5000
local too_far = adapter:nearest_owned(player, registry, config)
equal(too_far.ok, false, "interaction radius enforced")
equal(too_far.error.code, "OWN_BASE_CAMP_NOT_NEAR", "distance error")

config.world_units_per_meter = 0
local invalid_scale = adapter:scan(registry, config)
equal(invalid_scale.ok, false, "invalid scale rejected")

print("base_camp_adapter_spec: ok")
