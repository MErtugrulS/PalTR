package.path = table.concat({
    "Scripts/?.lua",
    "Scripts/?/init.lua",
    package.path
}, ";")

local Repositories = require("PalTR.storage.repositories")
local FileIO = require("PalTR.storage.file_io")
local Result = require("PalTR.core.result")
local TempPath = dofile("Tests/support/temp_path.lua")

local function equal(actual, expected, message)
    if actual ~= expected then
        error(message .. ": expected=" .. tostring(expected) ..
            " actual=" .. tostring(actual))
    end
end

local path = TempPath.prefix("paltr_repositories") .. ".tsv"
equal(Repositories.save_guilds(path, {
    A = {
        key = "A", name = "Alpha", id = "ID_A", object_path = "PathA",
        first_seen = 1, last_seen = 2
    }
}).ok, true, "guild registry saves")
equal(Repositories.load_guilds(path).A.name, "Alpha", "guild registry loads")

local invalid = assert(io.open(path, "w"))
invalid:write("wrong_header\n")
invalid:close()
local ok, error_message = pcall(function()
    Repositories.load_guilds(path)
end)
equal(ok, false, "invalid registry header stops loading")
equal(
    tostring(error_message):find("Gecersiz registry basligi", 1, true)
        ~= nil,
    true,
    "invalid registry header reports useful error"
)

local empty = assert(io.open(path, "w"))
empty:close()
ok, error_message = pcall(function()
    Repositories.load_guilds(path)
end)
equal(ok, false, "existing empty registry stops loading")
equal(
    tostring(error_message):find("Bos registry dosyasi", 1, true) ~= nil,
    true,
    "empty registry reports useful error"
)

local original_read_lines = FileIO.read_lines
FileIO.read_lines = function()
    return Result.err("READ_FAILED", "access denied")
end
ok, error_message = pcall(function()
    Repositories.load_guilds(path)
end)
FileIO.read_lines = original_read_lines
equal(ok, false, "registry read failure stops loading")
equal(
    tostring(error_message):find("READ_FAILED: access denied", 1, true)
        ~= nil,
    true,
    "registry read failure reports useful error"
)

os.remove(path)
print("repositories_spec: ok")
