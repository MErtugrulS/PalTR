local UMGAssetLoader = {}
UMGAssetLoader.__index = UMGAssetLoader

UMGAssetLoader.PANEL_ASSET_PATH =
    "/Game/Mods/PalTRUI/WBP_PalTRPanel"
UMGAssetLoader.PANEL_CLASS_PATH =
    "/Game/Mods/PalTRUI/WBP_PalTRPanel.WBP_PalTRPanel_C"

local function valid_object(object)
    if object == nil then return false end
    local checked, valid = pcall(function()
        return object:IsValid()
    end)
    if checked then return valid == true end
    return true
end

local function default_api()
    return {
        load_asset = type(LoadAsset) == "function" and LoadAsset or nil,
        find_object = type(StaticFindObject) == "function"
            and StaticFindObject or nil
    }
end

function UMGAssetLoader.new(api)
    return setmetatable({
        api = type(api) == "table" and api or default_api()
    }, UMGAssetLoader)
end

function UMGAssetLoader:_find_panel_class()
    if type(self.api.find_object) ~= "function" then
        return nil, "UE4SS StaticFindObject API bulunamadi."
    end

    local found, panel_class = pcall(
        self.api.find_object,
        UMGAssetLoader.PANEL_CLASS_PATH
    )
    if not found then
        return nil, "Panel sinifi aranirken UE4SS hatasi olustu."
    end
    if not valid_object(panel_class) then return nil end
    return panel_class
end

function UMGAssetLoader:load_panel_class()
    local panel_class, find_error = self:_find_panel_class()
    if find_error ~= nil then return false, nil, find_error end
    if panel_class ~= nil then return true, panel_class end

    if type(self.api.load_asset) ~= "function" then
        return false, nil, "UE4SS LoadAsset API bulunamadi."
    end

    local loaded = pcall(
        self.api.load_asset,
        UMGAssetLoader.PANEL_ASSET_PATH
    )
    if not loaded then
        return false, nil, "Panel asseti yuklenirken UE4SS hatasi olustu."
    end

    panel_class, find_error = self:_find_panel_class()
    if find_error ~= nil then return false, nil, find_error end
    if panel_class == nil then
        return false, nil, "Yuklenen panel sinifi bulunamadi."
    end
    return true, panel_class
end

return UMGAssetLoader
