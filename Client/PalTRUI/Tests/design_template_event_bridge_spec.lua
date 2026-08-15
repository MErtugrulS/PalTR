local DesignTemplateEventBridge = require("design_template_event_bridge")

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

local registered = {}
local routed = {}
local register_count = 0
local bridge = DesignTemplateEventBridge.new({
    handle = function(_, control)
        table.insert(routed, control)
        return true, { active_tab = "DIPLOMACY" }, true
    end
}, {
    register_hook = function(path, callback)
        register_count = register_count + 1
        registered[path] = callback
    end,
    execute = function(callback)
        callback()
    end,
    callbacks = {},
    state = { registered = false, busy = false }
})

local ok, register_error = bridge:register()
equal(ok, true, "design event bridge registered")
equal(register_error, nil, "design event bridge has no error")
equal(register_count, 46, "all design and guild identity events registered")

local class_path =
    "/Game/Mods/PalTRUI/WBP_PalTRPanel_DesignTemplate." ..
    "WBP_PalTRPanel_DesignTemplate_C:"
registered[class_path .. "PalTR_DiplomacyRelation03Clicked"]()
equal(routed[#routed], "DiplomacyRelationRowButton03",
    "third relation button routed directly")

registered[class_path .. "PalTR_DiplomacyClicked"]()
equal(routed[#routed], "DiplomacyTabButton",
    "native diplomacy sidebar button remains routed")

registered[class_path .. "PalTR_DiplomacyAllianceClicked"]()
equal(routed[#routed], "AllianceRequestButton",
    "normal diplomacy action remains routed")

registered[class_path .. "PalTR_ManagementClicked"]()
equal(routed[#routed], "ManagementTabButton",
    "management page button routed")

registered[class_path .. "PalTR_GuildIdentityColor16Clicked"]()
equal(routed[#routed], "GuildIdentityColorButton16",
    "last color choice routed")

registered[class_path .. "PalTR_GuildIdentityEmblem12Clicked"]()
equal(routed[#routed], "GuildIdentityEmblemButton12",
    "last emblem choice routed")

registered[class_path .. "PalTR_GuildIdentitySaveClicked"]()
equal(routed[#routed], "GuildIdentitySaveButton",
    "atomic identity save routed")

local second_ok = bridge:register()
equal(second_ok, true, "second registration accepted")
equal(register_count, 46, "second registration is idempotent")

print("PALTR_UI_DESIGN_TEMPLATE_EVENT_BRIDGE_TEST_OK")
