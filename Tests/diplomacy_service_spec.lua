package.path = table.concat({
    "Scripts/?.lua",
    "Scripts/?/init.lua",
    package.path
}, ";")

local Diplomacy = require("PalTR.services.diplomacy_service")
local FileIO = require("PalTR.storage.file_io")
local States = require("PalTR.domain.states")
local TempPath = dofile("Tests/support/temp_path.lua")

local function equal(actual, expected, message)
    if actual ~= expected then
        error(message .. ": expected=" .. tostring(expected) ..
            " actual=" .. tostring(actual))
    end
end

local prefix = TempPath.prefix("paltr_diplomacy_service")
local paths = {
    relations = prefix .. "_relations.tsv",
    events = prefix .. "_events.tsv"
}
local config = {
    diplomacy = {
        war_preparation_minutes = 1,
        proposal_expiry_hours = 1
    }
}
local errors = {}
local logger = {
    error = function(_, message) table.insert(errors, message) end
}

local service = Diplomacy.new(paths, config, logger)
local relation = assert(service:get("GUILD_A", "GUILD_B"))
equal(relation.state, States.NEUTRAL, "new relation starts neutral")
equal(service:declare_war("GUILD_A", "GUILD_B", "Leader").ok, true,
    "persisted transition succeeds")
equal(relation.state, States.WAR_PENDING, "persisted transition retained")

relation.state = States.NEUTRAL
relation.previous_state = States.NEUTRAL
relation.requested_by = ""
relation.active_at = 0
relation.expires_at = 0
relation.note = "before failure"
assert(service:_save().ok)

local original_overwrite = FileIO.overwrite
FileIO.overwrite = function(path, lines)
    if path == paths.relations then
        return {
            ok = false,
            error = { code = "WRITE_FAILED", message = "disk full" }
        }
    end
    return original_overwrite(path, lines)
end

local failed = service:declare_war("GUILD_A", "GUILD_B", "Leader")
equal(failed.ok, false, "failed persistence rejects transition")
equal(failed.error.code, "WRITE_FAILED", "write failure propagated")
equal(relation.state, States.NEUTRAL, "failed transition rolls state back")
equal(relation.requested_by, "", "failed transition rolls requester back")
equal(relation.note, "before failure", "failed transition rolls note back")

relation.state = States.WAR_PENDING
relation.active_at = 1
relation.updated_at = 1
local events = service:tick()
equal(#events, 0, "failed tick emits no successful events")
equal(relation.state, States.WAR_PENDING, "failed tick rolls state back")

FileIO.overwrite = original_overwrite
os.remove(paths.relations)
os.remove(paths.events)

print("diplomacy_service_spec: ok")
