local Result = require("PalTR.core.result")

local FileIO = {}

function FileIO.read_lines(path)
    local file = io.open(path, "r")
    if not file then return Result.ok({}) end
    local lines = {}
    for line in file:lines() do table.insert(lines, line) end
    file:close()
    return Result.ok(lines)
end

function FileIO.overwrite(path, lines)
    local file = io.open(path, "w")
    if not file then return Result.err("WRITE_FAILED", path) end
    for _, line in ipairs(lines or {}) do
        file:write(tostring(line), "\n")
    end
    file:close()
    return Result.ok(true)
end

function FileIO.append(path, line)
    local file = io.open(path, "a")
    if not file then return Result.err("APPEND_FAILED", path) end
    file:write(tostring(line), "\n")
    file:close()
    return Result.ok(true)
end

function FileIO.exists(path)
    local file = io.open(path, "r")
    if not file then return false end
    file:close()
    return true
end

function FileIO.move(source, target)
    local moved, message = os.rename(source, target)
    if not moved then
        return Result.err("MOVE_FAILED", message or (source .. " -> " .. target))
    end
    return Result.ok(true)
end

function FileIO.remove(path)
    local removed, message = os.remove(path)
    if not removed then
        return Result.err("REMOVE_FAILED", message or path)
    end
    return Result.ok(true)
end

return FileIO
