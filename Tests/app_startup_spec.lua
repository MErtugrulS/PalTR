package.path = table.concat({
    "Scripts/?.lua",
    "Scripts/?/init.lua",
    package.path
}, ";")

local App = require("PalTR.app")
local FileIO = require("PalTR.storage.file_io")

local function equal(actual, expected, message)
    if actual ~= expected then
        error(message .. ": expected=" .. tostring(expected) ..
            " actual=" .. tostring(actual))
    end
end

local app = App.new({
    data_root = os.getenv("TEMP") or ".",
    runtime = {
        scheduler_interval_ms = 5000,
        guild_scan_seconds = 60,
        player_validity_poll = true
    },
    diplomacy = {},
    protection = {},
    conquest = {}
})

local original_open = io.open
local original_overwrite = FileIO.overwrite
io.open = function() return nil end
FileIO.overwrite = function()
    return {
        ok = false,
        error = { code = "WRITE_FAILED", message = "read only" }
    }
end
local headers = app:_headers()
FileIO.overwrite = original_overwrite
io.open = original_open
equal(headers.ok, false, "mandatory header write failure is returned")
equal(headers.error.code, "WRITE_FAILED", "header failure code preserved")

local registrations = 0
app.hooks = {
    register = function()
        registrations = registrations + 1
        return registrations ~= 3
    end
}
equal(app:_register_hooks(), false, "one failed required hook fails startup set")
equal(registrations, 4, "all required hooks are still attempted")

app.hooks.register = function() return true end
equal(app:_register_hooks(), true, "all required hooks pass startup set")

print("app_startup_spec: ok")
