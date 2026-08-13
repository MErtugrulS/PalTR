package.path = table.concat({
    "Scripts/?.lua",
    "Scripts/?/init.lua",
    package.path
}, ";")

local FileIO = require("PalTR.storage.file_io")
local TempPath = dofile("Tests/support/temp_path.lua")

local function equal(actual, expected, message)
    if actual ~= expected then
        error(message .. ": expected=" .. tostring(expected) ..
            " actual=" .. tostring(actual))
    end
end

local path = TempPath.prefix("paltr_file_io") .. ".txt"
equal(FileIO.overwrite(path, { "first", "second" }).ok, true,
    "normal overwrite succeeds")
equal(FileIO.append(path, "third").ok, true, "normal append succeeds")
local file = assert(io.open(path, "r"))
equal(file:read("*a"), "first\nsecond\nthird\n", "content persisted")
file:close()

equal(FileIO.overwrite(path, { "replacement" }).ok, true,
    "existing file is replaced")
file = assert(io.open(path, "r"))
equal(file:read("*a"), "replacement\n", "replacement persisted")
file:close()
equal(FileIO.exists(path .. ".next"), false, "next file cleaned")
equal(FileIO.exists(path .. ".backup"), false, "backup file cleaned")
os.remove(path)

local recovery_path = path .. ".recovery"
local backup = assert(io.open(recovery_path .. ".backup", "w"))
backup:write("safe\n")
backup:close()
local recovered = FileIO.read_lines(recovery_path)
equal(recovered.ok, true, "backup recovery succeeds")
equal(recovered.value[1], "safe", "backup content recovered")
equal(FileIO.exists(recovery_path), true, "backup promoted to target")
os.remove(recovery_path)

local original_open = io.open

local function with_open(fake_open, callback)
    io.open = fake_open
    local ok, error_message = pcall(callback)
    io.open = original_open
    if not ok then error(error_message) end
end

with_open(function()
    return {
        write = function() return nil, "disk full" end,
        close = function() return true end
    }
end, function()
    local result = FileIO.overwrite("ignored", { "data" })
    equal(result.ok, false, "overwrite reports write failure")
    equal(result.error.code, "WRITE_FAILED", "overwrite failure code")
    equal(result.error.message, "disk full", "overwrite failure detail")
end)

with_open(function()
    return {
        write = function(self) return self end,
        close = function() return nil, "flush failed" end
    }
end, function()
    local result = FileIO.append("ignored", "data")
    equal(result.ok, false, "append reports close failure")
    equal(result.error.code, "APPEND_FAILED", "append failure code")
    equal(result.error.message, "flush failed", "append failure detail")
end)

print("file_io_spec: ok")
