package.path = table.concat({ "Scripts/?.lua", "Scripts/?/init.lua", package.path }, ";")
local Adapter = require("PalTR.runtime.test_kit_adapter")
local function equal(a, b, m) if a ~= b then error(m) end end

local cheat = { valid = true, calls = {} }
local controller = { valid = true, cheat = cheat, calls = {} }
local define = { valid = true, calls = {} }
local ue = {}
function ue.unwrap(value) return value end
function ue.valid(value) return value and value.valid == true end
function ue.read(object, field)
    return field == "CheatManager" and object.cheat or nil
end
function ue.find_object(path)
    equal(path, "/Script/Pal.Default__PalDefine", "PalDefine path")
    return define
end
function ue.call(object, method, ...)
    table.insert(object.calls, { method = method, args = { ... } })
    if method == "StatusPointName_AddMaxInventoryWeight" then
        return true, "AddMaxInventoryWeight"
    end
    return true, nil
end

local result = Adapter.new(ue):grant(controller, {
    player_exp = 100000000,
    weight_status_level = 1000,
    pal_id = "JetDragon", pal_count = 1, pal_level = 60,
    weapon_item_id = "Weapon_RocketLauncher", weapon_count = 1,
    ammo_item_id = "Ammo_Rocket", ammo_count = 5000
})
equal(result.ok, true, "test kit granted")
equal(controller.calls[1].method, "Debug_AddPlayerExp_ToServer", "player xp call")
equal(controller.calls[2].method, "Debug_SetStatusPoint_ToServer", "weight call")
equal(controller.calls[2].args[1], "AddMaxInventoryWeight", "weight name")
equal(controller.calls[2].args[2], 1000, "weight level")
equal(cheat.calls[1].method, "SpawnMonsterForPlayer", "pal spawn call")
equal(cheat.calls[2].args[1], "Weapon_RocketLauncher", "weapon id")
equal(cheat.calls[3].args[1], "Ammo_Rocket", "ammo id")
equal(cheat.calls[3].args[2], 5000, "ammo amount")
print("test_kit_adapter_spec: ok")
