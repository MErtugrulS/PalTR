local UMGAssetLoader = require("umg_asset_loader")

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

local loaded_class = { name = "WBP_PalTRPanel_C" }
local invalid_class = {
    IsValid = function() return false end
}
equal(
    UMGAssetLoader.PANEL_ASSET_PATH,
    "/Game/Mods/PalTRUI/WBP_PalTRPanel.WBP_PalTRPanel",
    "stable full panel asset path"
)
local load_calls = {}
local find_calls = 0
local loader = UMGAssetLoader.new({
    load_asset = function(path)
        table.insert(load_calls, path)
    end,
    find_object = function(path)
        equal(
            path,
            UMGAssetLoader.PANEL_CLASS_PATH,
            "stable panel class path"
        )
        find_calls = find_calls + 1
        if find_calls == 1 then return invalid_class end
        return loaded_class
    end
})

local loaded, panel_class, load_error = loader:load_panel_class()
equal(loaded, true, "panel class loaded")
equal(panel_class, loaded_class, "loaded class returned")
equal(load_error, nil, "successful load has no error")
equal(#load_calls, 1, "asset loaded once")
equal(
    load_calls[1],
    UMGAssetLoader.PANEL_ASSET_PATH,
    "stable panel asset path"
)
equal(find_calls, 2, "class checked before and after load")

local fallback_find_calls = 0
local fallback_calls = {}
local registry_fallback = UMGAssetLoader.new({
    load_asset = function() end,
    load_registered_asset = function(package_name, asset_name)
        table.insert(fallback_calls, {
            package_name = package_name,
            asset_name = asset_name
        })
        return true
    end,
    find_object = function()
        fallback_find_calls = fallback_find_calls + 1
        if fallback_find_calls < 3 then return invalid_class end
        return loaded_class
    end
})
local fallback_loaded, fallback_class =
    registry_fallback:load_panel_class()
equal(fallback_loaded, true, "asset registry fallback loaded")
equal(fallback_class, loaded_class, "fallback class returned")
equal(#fallback_calls, 1, "asset registry fallback called once")
equal(
    fallback_calls[1].package_name,
    UMGAssetLoader.PANEL_PACKAGE_NAME,
    "fallback package name"
)
equal(
    fallback_calls[1].asset_name,
    UMGAssetLoader.PANEL_ASSET_NAME,
    "fallback asset name"
)

local registry_failure = UMGAssetLoader.new({
    load_asset = function() end,
    load_registered_asset = function()
        return false, "registry failed"
    end,
    find_object = function() return invalid_class end
})
local registry_loaded, _, registry_error =
    registry_failure:load_panel_class()
equal(registry_loaded, false, "asset registry failure rejected")
equal(registry_error, "registry failed", "asset registry error preserved")

local unresolved_invalid = UMGAssetLoader.new({
    load_asset = function() end,
    find_object = function() return invalid_class end
})
local invalid_resolved, _, invalid_resolve_error =
    unresolved_invalid:load_panel_class()
equal(invalid_resolved, false, "invalid class rejected after load")
equal(
    invalid_resolve_error,
    "Yuklenen panel sinifi bulunamadi.",
    "invalid class resolve error"
)

local already_loaded_calls = 0
local already_loaded = UMGAssetLoader.new({
    load_asset = function()
        already_loaded_calls = already_loaded_calls + 1
    end,
    find_object = function()
        return loaded_class
    end
})
local reused, reused_class = already_loaded:load_panel_class()
equal(reused, true, "loaded class reused")
equal(reused_class, loaded_class, "existing class returned")
equal(already_loaded_calls, 0, "existing class is not loaded again")

local without_find = UMGAssetLoader.new({})
local found, _, find_error = without_find:load_panel_class()
equal(found, false, "missing finder rejected")
equal(find_error, "UE4SS StaticFindObject API bulunamadi.", "finder error")

local without_load = UMGAssetLoader.new({
    find_object = function() return nil end
})
local asset_loaded, _, asset_error = without_load:load_panel_class()
equal(asset_loaded, false, "missing loader rejected")
equal(asset_error, "UE4SS LoadAsset API bulunamadi.", "loader error")

local failed_load = UMGAssetLoader.new({
    load_asset = function() error("load failed") end,
    find_object = function() return nil end
})
local failed, _, failed_error = failed_load:load_panel_class()
equal(failed, false, "load exception rejected")
equal(
    failed_error,
    "Panel asseti yuklenirken UE4SS hatasi olustu.",
    "load exception hidden behind boundary"
)

local unresolved = UMGAssetLoader.new({
    load_asset = function() end,
    find_object = function() return nil end
})
local resolved, _, resolve_error = unresolved:load_panel_class()
equal(resolved, false, "unresolved class rejected")
equal(resolve_error, "Yuklenen panel sinifi bulunamadi.", "resolve error")

print("PALTR_UI_UMG_ASSET_LOADER_TEST_OK")
