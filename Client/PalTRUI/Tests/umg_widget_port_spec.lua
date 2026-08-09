local UMGWidgetPort = require("umg_widget_port")

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

local hud = { name = "hud" }
local controller = { name = "controller" }
local panel_class = { name = "WBP_PalTRPanel_C" }
local create_calls = {}
local viewport_calls = {}
local remove_calls = 0
local widget = {
    AddToViewport = function(_, z_order)
        table.insert(viewport_calls, z_order)
    end,
    RemoveFromParent = function()
        remove_calls = remove_calls + 1
    end
}
local library = {
    Create = function(_, world_context, widget_type, owning_player)
        table.insert(create_calls, {
            world_context = world_context,
            widget_type = widget_type,
            owning_player = owning_player
        })
        return widget
    end
}
local context_provider = {
    discover = function()
        return {
            ready = true,
            hud = hud,
            player_controller = controller
        }
    end
}
local asset_loader = {
    load_panel_class = function()
        return true, panel_class
    end
}
local find_calls = {}
local port = UMGWidgetPort.new({
    context_provider = context_provider,
    asset_loader = asset_loader,
    find_object = function(path)
        table.insert(find_calls, path)
        return library
    end
})

local first_model = { open = true, active_tab = "CLAN" }
local opened, open_error = port:open(first_model)
equal(opened, true, "widget opened")
equal(open_error, nil, "successful open has no error")
equal(find_calls[1], UMGWidgetPort.WIDGET_LIBRARY_PATH, "library path")
equal(#create_calls, 1, "widget created once")
equal(create_calls[1].world_context, hud, "hud is world context")
equal(create_calls[1].widget_type, panel_class, "panel class passed")
equal(create_calls[1].owning_player, controller, "owning player passed")
equal(viewport_calls[1], UMGWidgetPort.Z_ORDER, "stable viewport order")
equal(port.last_model, first_model, "open model retained")

equal(port:open(first_model), true, "open widget reused")
equal(#create_calls, 1, "open does not duplicate widget")

local diplomacy = { open = true, active_tab = "DIPLOMACY" }
equal(port:update(diplomacy), true, "open widget accepts update")
equal(port.last_model, diplomacy, "updated model retained")
equal(port:close(), true, "widget closed")
equal(remove_calls, 1, "widget removed once")
equal(port.widget, nil, "widget reference cleared")
equal(port.last_model, nil, "model reference cleared")
equal(port:close(), true, "closed widget is idempotent")

local unavailable_context = UMGWidgetPort.new({
    context_provider = { discover = function() return { ready = false } end },
    asset_loader = asset_loader,
    find_object = function() return library end
})
local context_opened, context_error = unavailable_context:open(first_model)
equal(context_opened, false, "missing context rejected")
equal(context_error, "UMG oyuncu baglami hazir degil.", "context error")

local failed_asset = UMGWidgetPort.new({
    context_provider = context_provider,
    asset_loader = {
        load_panel_class = function()
            return false, nil, "asset error"
        end
    },
    find_object = function() return library end
})
local asset_opened, asset_error = failed_asset:open(first_model)
equal(asset_opened, false, "asset failure rejected")
equal(asset_error, "asset error", "asset error preserved")

local missing_library = UMGWidgetPort.new({
    context_provider = context_provider,
    asset_loader = asset_loader,
    find_object = function() return nil end
})
local library_opened, library_error = missing_library:open(first_model)
equal(library_opened, false, "missing library rejected")
equal(
    library_error,
    "UMG WidgetBlueprintLibrary bulunamadi.",
    "library error"
)

local failed_create = UMGWidgetPort.new({
    context_provider = context_provider,
    asset_loader = asset_loader,
    find_object = function()
        return { Create = function() error("create failed") end }
    end
})
local created, create_error = failed_create:open(first_model)
equal(created, false, "create exception rejected")
equal(create_error, "PalTR panel widgeti olusturulamadi.", "create error")

local invalid_widget = UMGWidgetPort.new({
    context_provider = context_provider,
    asset_loader = asset_loader,
    find_object = function()
        return { Create = function() return nil end }
    end
})
local valid, valid_error = invalid_widget:open(first_model)
equal(valid, false, "invalid widget rejected")
equal(valid_error, "PalTR panel widgeti olusturulamadi.", "invalid error")

local unopened = UMGWidgetPort.new({})
local updated, update_error = unopened:update(first_model)
equal(updated, false, "closed widget update rejected")
equal(update_error, "PalTR panel widgeti acik degil.", "update error")

print("PALTR_UI_UMG_WIDGET_PORT_TEST_OK")
