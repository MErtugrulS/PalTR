local UMGAssetLoader = require("umg_asset_loader")
local UMGContext = require("umg_context")
local UMGViewBinder = require("umg_view_binder")

local UMGWidgetPort = {}
UMGWidgetPort.__index = UMGWidgetPort

UMGWidgetPort.WIDGET_LIBRARY_PATH =
    "/Script/UMG.Default__WidgetBlueprintLibrary"
UMGWidgetPort.Z_ORDER = 50
UMGWidgetPort.MOUSE_LOCK_DO_NOT_LOCK = 0

local function valid_object(object)
    if object == nil then return false end
    local checked, valid = pcall(function()
        return object:IsValid()
    end)
    if checked then return valid == true end
    return true
end

local function default_find_object(path)
    if type(StaticFindObject) ~= "function" then return nil end
    return StaticFindObject(path)
end

local function read_mouse_cursor_state(player_controller)
    local read, visible = pcall(function()
        return player_controller.bShowMouseCursor
    end)
    if read and type(visible) == "boolean" then return visible end
    return nil
end

local function set_mouse_cursor(player_controller, visible)
    if not valid_object(player_controller) then
        return false, "PalTR oyuncu controller'i gecersiz."
    end

    local changed, change_error = pcall(function()
        player_controller.bShowMouseCursor = visible
    end)
    if not changed then
        return false,
            "PalTR mouse imleci degistirilemedi: "
                .. tostring(change_error)
    end
    return true
end

local function report_cursor_warning(message)
    if type(print) == "function" then
        print("PALTR_UI_CURSOR_WARN | " .. tostring(message))
    end
end

local function set_ui_input_mode(widget_library, player_controller, widget)
    local changed, change_error = pcall(function()
        widget_library:SetInputMode_GameAndUIEx(
            player_controller,
            widget,
            UMGWidgetPort.MOUSE_LOCK_DO_NOT_LOCK,
            false,
            true
        )
    end)
    if not changed then
        return false,
            "PalTR UI input modu ayarlanamadi: " .. tostring(change_error)
    end
    return true
end

local function gameplay_input_ignored(player_controller, method_name)
    local read, ignored = pcall(function()
        return player_controller[method_name](player_controller)
    end)
    if read and type(ignored) == "boolean" then return ignored end
    return nil
end

local function set_gameplay_input_ignored(
    player_controller,
    method_name,
    ignored
)
    local changed, change_error = pcall(function()
        player_controller[method_name](player_controller, ignored)
    end)
    if not changed then
        return false, "PalTR gameplay input kilidi degistirilemedi: "
            .. tostring(change_error)
    end
    return true
end

local function restore_game_input_mode(widget_library, player_controller)
    local changed, change_error = pcall(function()
        widget_library:SetInputMode_GameOnly(player_controller, true)
    end)
    if not changed then
        return false,
            "PalTR oyun input modu geri yuklenemedi: "
                .. tostring(change_error)
    end
    return true
end

local function report_input_warning(message)
    if type(print) == "function" then
        print("PALTR_UI_INPUT_WARN | " .. tostring(message))
    end
end

local function report_close_stage(stage)
    if type(print) == "function" then
        print("[PalTRUI] PALTR_UI_CLOSE_STAGE | stage="
            .. tostring(stage) .. "\n")
    end
end

function UMGWidgetPort.new(dependencies)
    dependencies = type(dependencies) == "table" and dependencies or {}
    return setmetatable({
        asset_loader = dependencies.asset_loader or UMGAssetLoader.new(),
        context_provider = dependencies.context_provider or UMGContext,
        view_binder = dependencies.view_binder or UMGViewBinder.new(),
        find_object = dependencies.find_object or default_find_object,
        widget = nil,
        last_model = nil,
        widget_library = nil,
        player_controller = nil,
        previous_mouse_cursor = nil,
        locked_move_input = false,
        locked_look_input = false
    }, UMGWidgetPort)
end

function UMGWidgetPort:open(model)
    if valid_object(self.widget) then return true end

    local context = self.context_provider.discover()
    if type(context) ~= "table" or context.ready ~= true then
        return false, "UMG oyuncu baglami hazir degil."
    end

    local loaded, panel_class, load_error =
        self.asset_loader:load_panel_class()
    if loaded ~= true then return false, load_error end

    local found, widget_library = pcall(
        self.find_object,
        UMGWidgetPort.WIDGET_LIBRARY_PATH
    )
    if not found or not valid_object(widget_library) then
        return false, "UMG WidgetBlueprintLibrary bulunamadi."
    end

    local created, widget = pcall(function()
        return widget_library:Create(
            context.hud,
            panel_class,
            context.player_controller
        )
    end)
    if not created then
        return false,
            "PalTR panel Create cagrisi hata verdi: " .. tostring(widget)
    end
    if not valid_object(widget) then
        return false,
            "PalTR panel Create cagrisi gecersiz widget dondurdu: "
                .. tostring(widget)
    end

    local bound, bind_error = self.view_binder:bind(widget, model)
    if bound ~= true then return false, bind_error end

    local previous_mouse_cursor =
        read_mouse_cursor_state(context.player_controller)
    local cursor_ready, cursor_error =
        set_mouse_cursor(context.player_controller, true)
    if cursor_ready ~= true then report_cursor_warning(cursor_error) end

    local added = pcall(function()
        widget:AddToViewport(UMGWidgetPort.Z_ORDER)
    end)
    if not added then
        if previous_mouse_cursor ~= nil then
            set_mouse_cursor(
                context.player_controller,
                previous_mouse_cursor
            )
        end
        return false, "PalTR paneli viewport'a eklenemedi."
    end

    local input_ready, input_error = set_ui_input_mode(
        widget_library,
        context.player_controller,
        widget
    )
    if input_ready ~= true then report_input_warning(input_error) end

    local locked_move_input = false
    if gameplay_input_ignored(context.player_controller, "IsMoveInputIgnored") ~= true then
        local locked, lock_error = set_gameplay_input_ignored(
            context.player_controller,
            "SetIgnoreMoveInput",
            true
        )
        locked_move_input = locked == true
        if locked ~= true then report_input_warning(lock_error) end
    end
    local locked_look_input = false
    if gameplay_input_ignored(context.player_controller, "IsLookInputIgnored") ~= true then
        local locked, lock_error = set_gameplay_input_ignored(
            context.player_controller,
            "SetIgnoreLookInput",
            true
        )
        locked_look_input = locked == true
        if locked ~= true then report_input_warning(lock_error) end
    end

    self.widget = widget
    self.last_model = model
    self.widget_library = widget_library
    self.player_controller = context.player_controller
    self.previous_mouse_cursor = previous_mouse_cursor
    self.locked_move_input = locked_move_input
    self.locked_look_input = locked_look_input
    return true
end

function UMGWidgetPort:update(model)
    if not valid_object(self.widget) then
        return false, "PalTR panel widgeti acik degil."
    end
    local bound, bind_error = self.view_binder:bind(self.widget, model)
    if bound ~= true then return false, bind_error end
    self.last_model = model
    return true
end

function UMGWidgetPort:refresh_input()
    if not valid_object(self.widget)
        or not valid_object(self.widget_library)
        or not valid_object(self.player_controller) then
        return false, "PalTR panel input baglami acik degil."
    end

    local cursor_ready, cursor_error =
        set_mouse_cursor(self.player_controller, true)
    if cursor_ready ~= true then return false, cursor_error end

    return set_ui_input_mode(
        self.widget_library,
        self.player_controller,
        self.widget
    )
end

function UMGWidgetPort:close()
    if not valid_object(self.widget) then
        self.widget = nil
        self.last_model = nil
        self.widget_library = nil
        self.player_controller = nil
        self.previous_mouse_cursor = nil
        self.locked_move_input = false
        self.locked_look_input = false
        return true
    end

    report_close_stage("input_restore_begin")
    local input_restored, input_error = restore_game_input_mode(
        self.widget_library,
        self.player_controller
    )
    if input_restored ~= true then report_input_warning(input_error) end
    report_close_stage("input_restore_end")

    if self.locked_move_input then
        local unlocked, unlock_error = set_gameplay_input_ignored(
            self.player_controller,
            "SetIgnoreMoveInput",
            false
        )
        if unlocked ~= true then report_input_warning(unlock_error) end
    end
    if self.locked_look_input then
        local unlocked, unlock_error = set_gameplay_input_ignored(
            self.player_controller,
            "SetIgnoreLookInput",
            false
        )
        if unlocked ~= true then report_input_warning(unlock_error) end
    end

    local cursor_restored = true
    local cursor_error = nil
    if self.previous_mouse_cursor ~= nil then
        cursor_restored, cursor_error = set_mouse_cursor(
            self.player_controller,
            self.previous_mouse_cursor
        )
    end
    report_close_stage("cursor_restore_end")

    report_close_stage("remove_begin")
    local removed = pcall(function()
        self.widget:RemoveFromParent()
    end)
    if not removed then
        return false, "PalTR paneli viewport'tan kaldirilamadi."
    end
    report_close_stage("remove_end")

    self.widget = nil
    self.last_model = nil
    self.widget_library = nil
    self.player_controller = nil
    self.previous_mouse_cursor = nil
    self.locked_move_input = false
    self.locked_look_input = false
    if cursor_restored ~= true then report_cursor_warning(cursor_error) end
    return true
end

return UMGWidgetPort
