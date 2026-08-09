local UMGContext = require("umg_context")

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

local function named(name)
    return {
        GetFullName = function()
            return name
        end
    }
end

local controller = named("PlayerController PalPlayerController_0")
local layout = named("PalUIHUDLayoutBase HUDLayout_0")
local hud = named("PalHUDInGame PalHUDInGame_0")
hud.HUDLayout = layout
hud.PlayerOwner = controller
local service = named("PalHUDService PalHUDService_0")

local function find_all(class_name)
    if class_name == "PalHUDInGame" then return { hud } end
    if class_name == "PalHUDService" then return { service } end
    return nil
end

local context = UMGContext.discover({ find_all = find_all })
equal(context.ready, true, "complete render context ready")
equal(context.hud, hud, "hud exposed")
equal(context.service, service, "service exposed")
equal(context.layout, layout, "layout exposed")
equal(context.player_controller, controller, "player controller exposed")
equal(
    context.names.player_controller,
    "PlayerController PalPlayerController_0",
    "player controller name exposed"
)

hud.PlayerOwner = nil
local incomplete = UMGContext.discover({ find_all = find_all })
equal(incomplete.ready, false, "missing player controller not ready")
equal(incomplete.player_controller, nil, "missing player controller preserved")

print("PALTR_UI_UMG_CONTEXT_TEST_OK")
