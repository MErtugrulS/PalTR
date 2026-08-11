package.path = table.concat({
    "Scripts/?.lua",
    "Scripts/?/init.lua",
    package.path
}, ";")

local Loot = require("PalTR.services.conquest_loot_service")
local States = require("PalTR.domain.conquest_states")

local function equal(actual, expected, message)
    if actual ~= expected then
        error(message .. ": expected=" .. tostring(expected) ..
            " actual=" .. tostring(actual))
    end
end

local config = {
    loot_table = {
        {
            item_id = "PalSphere_Ancient_2",
            item_selector = "CAPTURE_SPHERE_LEVEL:Ancient_2",
            enabled = true,
            weight = 1,
            min_quantity = 1,
            max_quantity = 1,
            tier = "ANCIENT_2",
            category = "PAL_SPHERE"
        }
    }
}

local created = Loot.create(
    { node_id = "OUTPOST_A" },
    { war_id = "WAR_1", attacker_guild = "GUILD_A" },
    config,
    100,
    function() return 0 end
)

equal(created.ok, true, "loot created")
equal(created.value.physical_item_resolved, true, "static item id resolved")
equal(created.value.manifest.state, States.LOOT.CREATED, "manifest state")

local item
for _, value in pairs(created.value.items) do item = value end
equal(item.item_selector, "CAPTURE_SPHERE_LEVEL:Ancient_2", "highest sphere selector")
equal(item.item_id, "PalSphere_Ancient_2", "verified static item id")
equal(item.quantity, 1, "single sphere reward")

local ranged_config = {
    loot_table = {
        {
            item_id = "PalSphere_Ancient_2",
            enabled = true,
            weight = 1,
            min_quantity = 1,
            max_quantity = 2
        }
    }
}
local upper_bound = Loot.create(
    { node_id = "OUTPOST_B" },
    { war_id = "WAR_2", attacker_guild = "GUILD_A" },
    ranged_config,
    101,
    function() return 1 end
)
local upper_item
for _, value in pairs(upper_bound.value.items) do upper_item = value end
equal(upper_item.quantity, 2, "loot quantity clamps random upper bound")

equal(Loot.mark_in_transit(created.value.manifest).ok, true, "loot in transit")
equal(
    Loot.extract(created.value.manifest, "GUILD_B", 200).ok,
    false,
    "wrong guild cannot extract"
)
equal(
    Loot.extract(created.value.manifest, "GUILD_A", 200).ok,
    true,
    "owner extracts"
)
equal(created.value.manifest.state, States.LOOT.EXTRACTED, "loot extracted state")

print("conquest_loot_service_spec: ok")
