package.path = table.concat({
    "Scripts/?.lua",
    "Scripts/?/init.lua",
    package.path
}, ";")

local Registry = require("PalTR.services.registry_service")
local FileIO = require("PalTR.storage.file_io")
local TempPath = dofile("Tests/support/temp_path.lua")

local function equal(actual, expected, message)
    if actual ~= expected then
        error(message .. ": expected=" .. tostring(expected) ..
            " actual=" .. tostring(actual))
    end
end

local prefix = TempPath.prefix("paltr_registry_service")
local paths = {
    guilds = prefix .. "_guilds.tsv",
    players = prefix .. "_players.tsv",
    online = prefix .. "_online.tsv"
}
local errors = {}
local registry = Registry.new(paths, {
    info = function() end,
    error = function(_, message) table.insert(errors, message) end
})
registry.guilds.GUILD_B = {
    key = "GUILD_B", name = "B", id = "B", object_path = "",
    first_seen = 1, last_seen = 1
}
registry.runtime_players.Z = {
    online = true, name = "Zulu", guild_key = "GUILD_B",
    first_seen = 1, last_seen = 2
}
registry.runtime_players.A = {
    online = true, name = "Alpha", guild_key = "GUILD_B",
    first_seen = 1, last_seen = 2
}

equal(registry:save().ok, true, "registry snapshot saves")
local online = assert(io.open(paths.online, "r"))
local contents = online:read("*a")
online:close()
equal(
    contents:find("A\tAlpha", 1, true) < contents:find("Z\tZulu", 1, true),
    true,
    "online snapshot is deterministic"
)

local original_overwrite = FileIO.overwrite
FileIO.overwrite = function(path, lines)
    if path == paths.guilds then
        return {
            ok = false,
            error = { code = "WRITE_FAILED", message = "read only" }
        }
    end
    return original_overwrite(path, lines)
end
local failed = registry:save()
FileIO.overwrite = original_overwrite
equal(failed.ok, false, "registry write failure is returned")
equal(failed.error.code, "WRITE_FAILED", "registry failure code preserved")
equal(#errors > 0, true, "registry write failure is logged")

for _, path in pairs(paths) do os.remove(path) end
print("registry_service_spec: ok")
