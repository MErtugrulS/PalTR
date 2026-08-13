package.path = table.concat({
    "Scripts/?.lua",
    "Scripts/?/init.lua",
    package.path
}, ";")

local Announcer = require("PalTR.runtime.announcer")
local CommandService = require("PalTR.services.command_service")
local Conquest = require("PalTR.services.conquest_service")
local FileIO = require("PalTR.storage.file_io")
local Result = require("PalTR.core.result")

local function equal(actual, expected, message)
    if actual ~= expected then
        error(message .. ": expected=" .. tostring(expected)
            .. " actual=" .. tostring(actual))
    end
end

local errors = {}
local logger = {
    info = function() end,
    error = function(_, message)
        errors[#errors + 1] = message
    end
}

local original_append = FileIO.append
local original_send = Announcer.send
FileIO.append = function()
    return Result.err("WRITE_FAILED", "disk full")
end
Announcer.send = function() return true end

Conquest._event({
    paths = { conquest_events = "unused.tsv" },
    logger = logger,
    _now = function() return 1 end
}, "FAZ05_TEST", "detail")
equal(
    errors[1],
    "FAZ05_EVENT_WRITE_FAILED | WRITE_FAILED: disk full",
    "conquest audit failure is actionable"
)

CommandService._respond({
    paths = { responses = "unused.tsv" },
    status = { build = function() end },
    logger = logger
}, {}, { name = "Tester", guild_key = "GUILD_A" }, "!test", true, "ok")
equal(
    errors[2],
    "KOMUT_RESPONSE_WRITE_FAILED | WRITE_FAILED: disk full",
    "command audit failure is actionable"
)

FileIO.append = original_append
Announcer.send = original_send

print("audit_write_spec: ok")
