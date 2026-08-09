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
local cursor_calls = {}
local controller_cursor = false
local controller = { name = "controller" }
local move_ignored = false
local look_ignored = false
local gameplay_lock_calls = {}
controller.IsMoveInputIgnored = function() return move_ignored end
controller.IsLookInputIgnored = function() return look_ignored end
controller.SetIgnoreMoveInput = function(_, ignored)
    move_ignored = ignored
    table.insert(gameplay_lock_calls, { kind = "move", ignored = ignored })
end
controller.SetIgnoreLookInput = function(_, ignored)
    look_ignored = ignored
    table.insert(gameplay_lock_calls, { kind = "look", ignored = ignored })
end
setmetatable(controller, {
    __index = function(_, key)
        if key == "bShowMouseCursor" then return controller_cursor end
    end,
    __newindex = function(target, key, value)
        if key == "bShowMouseCursor" then
            table.insert(cursor_calls, value)
            controller_cursor = value
            return
        end
        rawset(target, key, value)
    end
})
local panel_class = { name = "WBP_PalTRPanel_C" }
local create_calls = {}
local input_mode_calls = {}
local viewport_calls = {}
local remove_calls = 0
local close_order = {}
local widget = {
    AddToViewport = function(_, z_order)
        table.insert(viewport_calls, z_order)
    end,
    RemoveFromParent = function()
        table.insert(close_order, "remove")
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
    end,
    SetInputMode_GameAndUIEx = function(
        _, player_controller, focused_widget, mouse_lock_mode,
        hide_cursor_during_capture, flush_input
    )
        table.insert(input_mode_calls, {
            mode = "game_and_ui",
            player_controller = player_controller,
            focused_widget = focused_widget,
            mouse_lock_mode = mouse_lock_mode,
            hide_cursor_during_capture = hide_cursor_during_capture,
            flush_input = flush_input
        })
    end,
    SetInputMode_GameOnly = function(_, player_controller, flush_input)
        table.insert(close_order, "game_input")
        table.insert(input_mode_calls, {
            mode = "game_only",
            player_controller = player_controller,
            flush_input = flush_input
        })
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
local bound_models = {}
local view_binder = {
    bind = function(_, bound_widget, model)
        equal(bound_widget, widget, "binder receives widget")
        table.insert(bound_models, model)
        return true
    end
}
local find_calls = {}
local port = UMGWidgetPort.new({
    context_provider = context_provider,
    asset_loader = asset_loader,
    view_binder = view_binder,
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
equal(bound_models[1], first_model, "initial model bound before viewport")
equal(port.last_model, first_model, "open model retained")
equal(cursor_calls[1], true, "mouse cursor shown on open")
equal(controller.bShowMouseCursor, true, "mouse cursor is visible")
equal(input_mode_calls[1].mode, "game_and_ui", "game-and-UI input enabled")
equal(input_mode_calls[1].player_controller, controller,
    "UI-only input receives controller")
equal(input_mode_calls[1].focused_widget, nil,
    "panel leaves keyboard focus with game keybinds")
equal(input_mode_calls[1].mouse_lock_mode,
    UMGWidgetPort.MOUSE_LOCK_DO_NOT_LOCK, "mouse remains unlocked")
equal(input_mode_calls[1].flush_input, true, "opening input is flushed")
equal(input_mode_calls[1].hide_cursor_during_capture, false,
    "cursor remains visible during capture")
equal(move_ignored, true, "movement input locked while panel is open")
equal(look_ignored, true, "look input locked while panel is open")

equal(port:open(first_model), true, "open widget reused")
equal(#create_calls, 1, "open does not duplicate widget")

local refreshed, refresh_error = port:refresh_input()
equal(refreshed, true, "open widget input refreshed")
equal(refresh_error, nil, "successful input refresh has no error")
equal(cursor_calls[2], true, "input refresh keeps cursor visible")
equal(input_mode_calls[2].mode, "game_and_ui",
    "input refresh restores game-and-UI mode")
equal(input_mode_calls[2].focused_widget, nil,
    "input refresh preserves game keybind focus")

local diplomacy = { open = true, active_tab = "DIPLOMACY" }
equal(port:update(diplomacy), true, "open widget accepts update")
equal(bound_models[2], diplomacy, "updated model bound")
equal(port.last_model, diplomacy, "updated model retained")
equal(port:close(), true, "widget closed")
equal(remove_calls, 1, "widget removed once")
equal(cursor_calls[3], false, "previous mouse cursor restored on close")
equal(controller.bShowMouseCursor, false, "mouse cursor is restored")
equal(move_ignored, false, "movement input unlocked on close")
equal(look_ignored, false, "look input unlocked on close")
equal(#gameplay_lock_calls, 4, "only owned gameplay locks are toggled")
equal(input_mode_calls[3].mode, "game_only", "game input restored")
equal(input_mode_calls[3].player_controller, controller,
    "game input receives controller")
equal(input_mode_calls[3].flush_input, true, "closing input is flushed")
equal(close_order[1], "game_input", "game input restored before removal")
equal(close_order[2], "remove", "widget removed after input restore")
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
equal(
    string.find(create_error, "Create cagrisi hata verdi:", 1, true) ~= nil,
    true,
    "create error category"
)
equal(
    string.find(create_error, "create failed", 1, true) ~= nil,
    true,
    "create error detail"
)

local invalid_widget = UMGWidgetPort.new({
    context_provider = context_provider,
    asset_loader = asset_loader,
    find_object = function()
        return { Create = function() return nil end }
    end
})
local valid, valid_error = invalid_widget:open(first_model)
equal(valid, false, "invalid widget rejected")
equal(
    valid_error,
    "PalTR panel Create cagrisi gecersiz widget dondurdu: nil",
    "invalid error"
)

local rejected_bind = UMGWidgetPort.new({
    context_provider = context_provider,
    asset_loader = asset_loader,
    view_binder = {
        bind = function() return false, "bind failed" end
    },
    find_object = function() return library end
})
local bind_opened, bind_error = rejected_bind:open(first_model)
equal(bind_opened, false, "failed initial bind rejected")
equal(bind_error, "bind failed", "bind error preserved")
equal(rejected_bind.widget, nil, "failed bind does not retain widget")

local unopened = UMGWidgetPort.new({})
local updated, update_error = unopened:update(first_model)
equal(updated, false, "closed widget update rejected")
equal(update_error, "PalTR panel widgeti acik degil.", "update error")
local refresh_closed, refresh_closed_error = unopened:refresh_input()
equal(refresh_closed, false, "closed widget input refresh rejected")
equal(refresh_closed_error, "PalTR panel input baglami acik degil.",
    "closed input refresh error")

print("PALTR_UI_UMG_WIDGET_PORT_TEST_OK")
