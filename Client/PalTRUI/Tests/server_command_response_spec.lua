local dependency_names = {
    "PalTR.domain.command_parser",
    "PalTR.domain.states",
    "PalTR.storage.file_io",
    "PalTR.storage.tsv",
    "PalTR.core.clock",
    "PalTR.core.ui_wire",
    "PalTR.runtime.ue",
    "PalTR.runtime.announcer",
    "PalTR.runtime.private_messenger"
}
local saved = {}
for _, name in ipairs(dependency_names) do
    saved[name] = package.loaded[name]
end

package.loaded["PalTR.domain.command_parser"] = {}
package.loaded["PalTR.domain.states"] = {}
package.loaded["PalTR.storage.file_io"] = {
    append = function() return true end
}
package.loaded["PalTR.storage.tsv"] = {
    encode = function() return "response" end
}
package.loaded["PalTR.core.clock"] = {
    now = function() return "now" end
}
package.loaded["PalTR.core.ui_wire"] = {}
package.loaded["PalTR.runtime.ue"] = {}
package.loaded["PalTR.runtime.announcer"] = {
    send = function() return true end
}
package.loaded["PalTR.runtime.private_messenger"] = {}
package.loaded["PalTR.services.command_service"] = nil

local CommandService = require("PalTR.services.command_service")

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

local observed = {}
local errors = {}
local service = CommandService.new(
    { responses = "responses.tsv" },
    {},
    {},
    { build = function() return true end },
    {
        info = function() end,
        error = function(_, message) table.insert(errors, message) end
    },
    function(player)
        table.insert(observed, player)
        return true
    end
)
local player = { name = "Ada", guild_key = "guild-own" }
service:_respond({}, player, "!savas guild-other", true, "ok")
equal(#observed, 1, "command response forces one snapshot")
equal(observed[1], player, "response player forwarded")
equal(#errors, 0, "successful observer has no error")

local failing = CommandService.new(
    { responses = "responses.tsv" },
    {},
    {},
    { build = function() return true end },
    {
        info = function() end,
        error = function(_, message) table.insert(errors, message) end
    },
    function() error("publisher failed") end
)
failing:_respond({}, player, "!ittifak guild-other", false, "failed")
equal(#errors, 1, "observer failure logged")
equal(errors[1]:find("publisher failed", 1, true) ~= nil, true,
    "observer error preserved")

for _, name in ipairs(dependency_names) do
    package.loaded[name] = saved[name]
end
package.loaded["PalTR.services.command_service"] = nil

print("PALTR_UI_SERVER_COMMAND_RESPONSE_TEST_OK")
