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
        if find_calls == 1 then return nil end
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
