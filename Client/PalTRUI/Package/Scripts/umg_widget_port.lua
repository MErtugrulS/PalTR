local UMGAssetLoader = require("umg_asset_loader")
local UMGContext = require("umg_context")

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

function UMGWidgetPort.new(dependencies)
    dependencies = type(dependencies) == "table" and dependencies or {}
    return setmetatable({
        asset_loader = dependencies.asset_loader or UMGAssetLoader.new(),
        context_provider = dependencies.context_provider or UMGContext,
        find_object = dependencies.find_object or default_find_object,
        widget = nil,
        last_model = nil
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
    if not created or not valid_object(widget) then
        return false, "PalTR panel widgeti olusturulamadi."
    end

    local added = pcall(function()
        widget:AddToViewport(UMGWidgetPort.Z_ORDER)
    end)
    if not added then
        return false, "PalTR paneli viewport'a eklenemedi."
    end

    self.widget = widget
    self.last_model = model
    return true
end

function UMGWidgetPort:update(model)
    if not valid_object(self.widget) then
        return false, "PalTR panel widgeti acik degil."
    end
    self.last_model = model
    return true
end

function UMGWidgetPort:close()
    if not valid_object(self.widget) then
        self.widget = nil
        self.last_model = nil
        return true
    end

    local removed = pcall(function()
        self.widget:RemoveFromParent()
    end)
    if not removed then
        return false, "PalTR paneli viewport'tan kaldirilamadi."
    end

    self.widget = nil
    self.last_model = nil
    return true
end

return UMGWidgetPort
