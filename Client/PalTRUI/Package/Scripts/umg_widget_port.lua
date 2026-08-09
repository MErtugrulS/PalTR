local UMGAssetLoader = require("umg_asset_loader")
local UMGContext = require("umg_context")
local UMGViewBinder = require("umg_view_binder")

local UMGWidgetPort = {}
UMGWidgetPort.__index = UMGWidgetPort

UMGWidgetPort.WIDGET_LIBRARY_PATH =
    "/Script/UMG.Default__WidgetBlueprintLibrary"
UMGWidgetPort.Z_ORDER = 50

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

function UMGWidgetPort.new(dependencies)
    dependencies = type(dependencies) == "table" and dependencies or {}
    return setmetatable({
        asset_loader = dependencies.asset_loader or UMGAssetLoader.new(),
        context_provider = dependencies.context_provider or UMGContext,
        view_binder = dependencies.view_binder or UMGViewBinder.new(),
        find_object = dependencies.find_object or default_find_object,
        widget = nil,
        last_model = nil,
        player_controller = nil,
        previous_mouse_cursor = nil
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

    self.widget = widget
    self.last_model = model
    self.player_controller = context.player_controller
    self.previous_mouse_cursor = previous_mouse_cursor
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

function UMGWidgetPort:close()
    if not valid_object(self.widget) then
        self.widget = nil
        self.last_model = nil
        self.player_controller = nil
        self.previous_mouse_cursor = nil
        return true
    end

    local removed = pcall(function()
        self.widget:RemoveFromParent()
    end)
    if not removed then
        return false, "PalTR paneli viewport'tan kaldirilamadi."
    end

    local cursor_restored = true
    local cursor_error = nil
    if self.previous_mouse_cursor ~= nil then
        cursor_restored, cursor_error = set_mouse_cursor(
            self.player_controller,
            self.previous_mouse_cursor
        )
    end

    self.widget = nil
    self.last_model = nil
    self.player_controller = nil
    self.previous_mouse_cursor = nil
    if cursor_restored ~= true then report_cursor_warning(cursor_error) end
    return true
end

return UMGWidgetPort
