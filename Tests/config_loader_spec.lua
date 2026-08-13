package.path = table.concat({
    "Scripts/?.lua",
    "Scripts/?/init.lua",
    package.path
}, ";")

local Defaults = require("PalTR.config.defaults")
local Loader = require("PalTR.config.loader")

local function equal(actual, expected, message)
    if actual ~= expected then
        error(message .. ": expected=" .. tostring(expected)
            .. " actual=" .. tostring(actual))
    end
end

local module_name = "PalTR.config.local"
local original_loaded = package.loaded[module_name]
local original_preload = package.preload[module_name]

package.loaded[module_name] = nil
package.preload[module_name] = function()
    return {
        data_root = "C:/Test",
        runtime = { scheduler_interval_ms = 123 },
        conquest = {
            operator_roles = { LEADER = false, COMMANDER = true }
        }
    }
end

local first = Loader.load()
equal(first.data_root, "C:/Test", "local scalar applied")
equal(first.runtime.scheduler_interval_ms, 123, "local section applied")
equal(first.runtime.guild_scan_seconds, 60, "unspecified default retained")
equal(first.conquest.operator_roles.LEADER, false, "nested value applied")

first.runtime.guild_scan_seconds = 999
first.conquest.operator_roles.COMMANDER = false

package.loaded[module_name] = nil
package.preload[module_name] = function()
    error("local config absent")
end

local second = Loader.load()
equal(second.data_root, Defaults.data_root, "default scalar restored")
equal(second.runtime.scheduler_interval_ms, 5000, "default runtime restored")
equal(second.runtime.guild_scan_seconds, 60, "returned config is isolated")
equal(
    second.conquest.operator_roles.COMMANDER,
    true,
    "nested defaults are isolated"
)
equal(Defaults.runtime.guild_scan_seconds, 60, "defaults stay immutable")
equal(
    Defaults.conquest.operator_roles.COMMANDER,
    true,
    "nested defaults stay immutable"
)

package.loaded[module_name] = original_loaded
package.preload[module_name] = original_preload

print("config_loader_spec: ok")
