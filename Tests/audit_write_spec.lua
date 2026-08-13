package.path = table.concat({
    "Scripts/?.lua",
    "Scripts/?/init.lua",
    package.path
}, ";")

local Announcer = require("PalTR.runtime.announcer")
local App = require("PalTR.app")
local CommandService = require("PalTR.services.command_service")
local Conquest = require("PalTR.services.conquest_service")
local DamageObserver = require("PalTR.services.damage_observer")
local FileIO = require("PalTR.storage.file_io")
local Result = require("PalTR.core.result")
local Status = require("PalTR.services.status_service")

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
local original_overwrite = FileIO.overwrite
local original_send = Announcer.send
FileIO.append = function()
    return Result.err("WRITE_FAILED", "disk full")
end
FileIO.overwrite = function()
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

App._event({
    paths = { events = "unused.tsv" },
    logger = logger
}, "TEST_EVENT", "GUILD_A", "detail")
equal(
    errors[3],
    "APP_EVENT_WRITE_FAILED | WRITE_FAILED: disk full",
    "app audit failure is actionable"
)

local observer = DamageObserver.new("unused.tsv", {}, {}, logger)
observer.last_write_error_at = -60
observer:_append("Target", nil, { "detail" })
observer:_append("Target", nil, { "detail" })
equal(
    errors[4],
    "DAMAGE_AUDIT_WRITE_FAILED | WRITE_FAILED: disk full",
    "damage audit failure is actionable"
)
equal(#errors, 4, "damage audit errors are throttled")

local status = Status.new(
    { latest_status = "unused.txt" },
    { guilds = {} },
    { relations_for = function() return {} end },
    logger
)
local status_result = status:build(nil, "test")
equal(status_result.ok, false, "status write failure is returned")
equal(
    errors[5],
    "STATUS_WRITE_FAILED | WRITE_FAILED: disk full",
    "status failure is actionable"
)

FileIO.append = original_append
FileIO.overwrite = original_overwrite
Announcer.send = original_send

print("audit_write_spec: ok")
