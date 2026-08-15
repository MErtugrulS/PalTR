local UMGAssetLoader = {}
UMGAssetLoader.__index = UMGAssetLoader

UMGAssetLoader.PANEL_CANDIDATES = {
    {
        asset_path = "/Game/Mods/PalTRUI/WBP_PalTRPanel_DesignTemplate.WBP_PalTRPanel_DesignTemplate",
        class_path = "/Game/Mods/PalTRUI/WBP_PalTRPanel_DesignTemplate.WBP_PalTRPanel_DesignTemplate_C",
        package_name = "/Game/Mods/PalTRUI/WBP_PalTRPanel_DesignTemplate",
        asset_name = "WBP_PalTRPanel_DesignTemplate_C"
    },
    {
        asset_path = "/Game/Mods/PalTRUI/WBP_PalTRPanel.WBP_PalTRPanel",
        class_path = "/Game/Mods/PalTRUI/WBP_PalTRPanel.WBP_PalTRPanel_C",
        package_name = "/Game/Mods/PalTRUI/WBP_PalTRPanel",
        asset_name = "WBP_PalTRPanel_C"
    }
}
UMGAssetLoader.PANEL_ASSET_PATH =
    UMGAssetLoader.PANEL_CANDIDATES[1].asset_path
UMGAssetLoader.PANEL_CLASS_PATH =
    UMGAssetLoader.PANEL_CANDIDATES[1].class_path
UMGAssetLoader.PANEL_PACKAGE_NAME =
    UMGAssetLoader.PANEL_CANDIDATES[1].package_name
UMGAssetLoader.PANEL_ASSET_NAME =
    UMGAssetLoader.PANEL_CANDIDATES[1].asset_name
UMGAssetLoader.ASSET_REGISTRY_HELPERS_PATH =
    "/Script/AssetRegistry.Default__AssetRegistryHelpers"

local function valid_object(object)
    if object == nil then return false end
    local checked, valid = pcall(function()
        return object:IsValid()
    end)
    if checked then return valid == true end
    return true
end

local function default_load_registered_asset(package_name, asset_name)
    if type(StaticFindObject) ~= "function" then
        return false, "UE4SS StaticFindObject API bulunamadi."
    end

    local loaded, result = pcall(function()
        local UEHelpers = require("UEHelpers")
        local registry_helpers = StaticFindObject(
            UMGAssetLoader.ASSET_REGISTRY_HELPERS_PATH
        )
        if not valid_object(registry_helpers) then
            error("AssetRegistryHelpers bulunamadi.")
        end

        local asset = registry_helpers:GetAsset({
            PackageName = UEHelpers.FindOrAddFName(package_name),
            AssetName = UEHelpers.FindOrAddFName(asset_name)
        })
        return valid_object(asset)
    end)
    if not loaded then
        return false,
            "Panel Asset Registry ile yuklenemedi: " .. tostring(result)
    end
    if result ~= true then
        return false, "Panel Asset Registry kaydi gecersiz."
    end
    return true
end

local function default_api()
    return {
        load_asset = type(LoadAsset) == "function" and LoadAsset or nil,
        load_registered_asset = default_load_registered_asset,
        find_object = type(StaticFindObject) == "function"
            and StaticFindObject or nil
    }
end

function UMGAssetLoader.new(api)
    return setmetatable({
        api = type(api) == "table" and api or default_api()
    }, UMGAssetLoader)
end

function UMGAssetLoader:_find_panel_class(candidate)
    if type(self.api.find_object) ~= "function" then
        return nil, "UE4SS StaticFindObject API bulunamadi."
    end

    local found, panel_class = pcall(
        self.api.find_object,
        candidate.class_path
    )
    if not found then
        return nil, "Panel sinifi aranirken UE4SS hatasi olustu."
    end
    if not valid_object(panel_class) then return nil end
    return panel_class
end

function UMGAssetLoader:load_panel_class()
    if type(self.api.find_object) ~= "function" then
        return false, nil, "UE4SS StaticFindObject API bulunamadi."
    end

    if type(self.api.load_asset) ~= "function"
        and type(self.api.load_registered_asset) ~= "function" then
        return false, nil, "UE4SS LoadAsset API bulunamadi."
    end

    local last_error = "Yuklenen panel sinifi bulunamadi."
    for _, candidate in ipairs(UMGAssetLoader.PANEL_CANDIDATES) do
        local panel_class, find_error = self:_find_panel_class(candidate)
        if find_error ~= nil then return false, nil, find_error end
        if panel_class ~= nil then return true, panel_class end

        if type(self.api.load_asset) == "function" then
            local loaded = pcall(self.api.load_asset, candidate.asset_path)
            if loaded then
                panel_class, find_error = self:_find_panel_class(candidate)
                if find_error ~= nil then return false, nil, find_error end
                if panel_class ~= nil then return true, panel_class end
            else
                last_error =
                    "Panel asseti yuklenirken UE4SS hatasi olustu."
            end
        end

        if type(self.api.load_registered_asset) == "function" then
            local registered, registry_error =
                self.api.load_registered_asset(
                    candidate.package_name,
                    candidate.asset_name
                )
            if registered == true then
                panel_class, find_error = self:_find_panel_class(candidate)
                if find_error ~= nil then return false, nil, find_error end
                if panel_class ~= nil then return true, panel_class end
            elseif registry_error ~= nil then
                last_error = registry_error
            end
        end
    end

    return false, nil, last_error
end

return UMGAssetLoader
