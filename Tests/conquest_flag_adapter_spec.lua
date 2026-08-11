package.path = table.concat({ "Scripts/?.lua", "Scripts/?/init.lua", package.path }, ";")
local Adapter = require("PalTR.runtime.conquest_flag_adapter")
local function equal(a, b, m) if a ~= b then error(m) end end
local actor = {
    valid = true, path = "VerifiedFlagClass_C Instance", group = "GROUP_A",
    model = { valid = true, id = "FLAG_A" },
    location = { X = 1000, Y = 0, Z = 0 }
}
local ue = {}
function ue.unwrap(v) return v end
function ue.valid(v) return v and v.valid == true end
function ue.read(v, f) return v and v[f] end
function ue.guid(v) return tostring(v or "") end
function ue.full_name(v) return v.path or "Model" end
function ue.find_all(n) return n == "PalBuildObject" and { actor } or {} end
function ue.call(o, m)
    if m == "IsAvailable" then return true, o.valid end
    if m == "GetGroupIdBelongTo" then return true, o.group end
    if m == "GetModel" then return true, o.model end
    if m == "GetModelId" then return true, o.id end
    if m == "K2_GetActorLocation" then return true, o.location end
    return false, nil
end
local registry = {}
function registry:find_guild_by_id(id) return id == "GROUP_A" and { key = "A" } or nil end
local player = { guild_key = "A", pawn = { valid = true, location = { X = 1100, Y = 0, Z = 0 } } }
local config = {
    world_units_per_meter = 100, flag_interaction_radius_meters = 20,
    conquest_flag_actor_class_tokens = {}
}
local adapter = Adapter.new(ue)
local blocked = adapter:nearest_owned_flag(player, registry, config)
equal(blocked.error.code, "CONQUEST_FLAG_CLASS_UNVERIFIED", "unverified class blocks")
config.flag_candidate_actor_class_tokens = { "VerifiedFlagClass_C" }
local candidate = adapter:nearest_owned_candidate(player, registry, config)
equal(candidate.ok, true, "candidate discovery is read only")
equal(config.conquest_flag_actor_class_tokens[1], nil, "official config unchanged")
config.conquest_flag_actor_class_tokens = { "VerifiedFlagClass_C" }
local found = adapter:nearest_owned_flag(player, registry, config)
equal(found.ok, true, "configured flag found")
equal(found.value.flag_reference, "FLAG_A", "model id used")
equal(found.value.distance_meters, 1, "meters used")

actor.path = "OtherClass_C Instance"
local missing_class = adapter:nearest_owned_candidate(player, registry, config)
equal(missing_class.ok, false, "missing candidate class fails")
equal(
    missing_class.error.message,
    "Ayarli Klan Bayragi sinifinda world aktoru bulunamadi",
    "missing class detail"
)

actor.path = "VerifiedFlagClass_C Instance"
actor.group = "UNKNOWN_GROUP"
local missing_owner = adapter:nearest_owned_candidate(player, registry, config)
equal(missing_owner.ok, false, "unresolved owner fails")
equal(
    missing_owner.error.message,
    "Yapi bulundu fakat klan sahipligi cozumlenemedi",
    "owner detail"
)
print("conquest_flag_adapter_spec: ok")
