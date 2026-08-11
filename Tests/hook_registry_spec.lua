package.path = table.concat({
    "Scripts/?.lua",
    "Scripts/?/init.lua",
    package.path
}, ";")

local registered_path = nil
local registered_callback = nil

function RegisterHook(path, callback)
    registered_path = path
    registered_callback = callback
    return 11, 22
end

local errors = {}
local logger = {
    info = function() end,
    warn = function() end,
    error = function(_, message)
        table.insert(errors, message)
    end
}

local HookRegistry = require("PalTR.runtime.hook_registry")
local registry = HookRegistry.new(logger)
local callback_calls = 0

local registered = registry:register(
    "TestHook",
    "/Script/Test.Path:Function",
    function(value)
        callback_calls = callback_calls + 1
        if value == "fail" then error("callback failed") end
        return "callback-result"
    end
)

assert(registered == true, "hook should register")
assert(registered_path == "/Script/Test.Path:Function", "path forwarded")
assert(type(registered_callback) == "function", "callback forwarded")

local callback_result = registered_callback("ok")
assert(callback_calls == 1, "successful callback runs")
assert(#errors == 0, "successful callback is silent")
assert(callback_result == "callback-result", "callback result preserved")

local survived = pcall(registered_callback, "fail")
assert(survived == true, "callback error must not escape hook boundary")
assert(callback_calls == 2, "failing callback still runs")
assert(#errors == 1, "callback error logged once")
assert(errors[1]:find("TestHook", 1, true), "hook name included in error")

print("hook_registry_spec: ok")
