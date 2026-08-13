local Result = require("PalTR.core.result")

local FileIO = {}

local function raw_exists(path)
    local file = io.open(path, "r")
    if not file then return false end
    file:close()
    return true
end

local function recover_missing(path)
    if raw_exists(path) then return Result.ok(true) end

    for _, candidate in ipairs({ path .. ".backup", path .. ".next" }) do
        if raw_exists(candidate) then
            local moved, message = os.rename(candidate, path)
            if not moved then
                return Result.err(
                    "RECOVERY_FAILED",
                    message or (candidate .. " -> " .. path)
                )
            end
            return Result.ok(true)
        end
    end

    return Result.ok(false)
end

local function write_line(file, line, error_code, path)
    local written, message = file:write(tostring(line), "\n")
    if written then return nil end
    return Result.err(error_code, message or path)
end

local function close_file(file, error_code, path)
    local closed, message = file:close()
    if closed then return nil end
    return Result.err(error_code, message or path)
end

function FileIO.read_lines(path)
    local recovered = recover_missing(path)
    if not recovered.ok then return recovered end

    local file, message, error_code = io.open(path, "r")
    if not file then
        if recovered.value == false and tonumber(error_code) == 2 then
            return Result.ok({})
        end
        return Result.err("READ_FAILED", message or path)
    end

    local lines = {}
    local read_ok, read_error = pcall(function()
        for line in file:lines() do table.insert(lines, line) end
    end)
    local closed, close_error = file:close()
    if not read_ok then
        return Result.err("READ_FAILED", read_error or path)
    end
    if not closed then
        return Result.err("READ_FAILED", close_error or path)
    end
    return Result.ok(lines)
end

function FileIO.overwrite(path, lines)
    local recovered = recover_missing(path)
    if not recovered.ok then
        return Result.err("WRITE_FAILED", recovered.error.message)
    end

    local next_path = path .. ".next"
    local backup_path = path .. ".backup"
    local file = io.open(next_path, "w")
    if not file then return Result.err("WRITE_FAILED", path) end
    for _, line in ipairs(lines or {}) do
        local failure = write_line(file, line, "WRITE_FAILED", next_path)
        if failure then
            file:close()
            return failure
        end
    end
    local failure = close_file(file, "WRITE_FAILED", next_path)
    if failure then return failure end

    if raw_exists(path) then
        if raw_exists(backup_path) then
            local removed, remove_error = os.remove(backup_path)
            if not removed then
                return Result.err("WRITE_FAILED", remove_error or backup_path)
            end
        end

        local backed_up, backup_error = os.rename(path, backup_path)
        if not backed_up then
            return Result.err("WRITE_FAILED", backup_error or path)
        end

        local promoted, promote_error = os.rename(next_path, path)
        if not promoted then
            local restored, restore_error = os.rename(backup_path, path)
            if not restored then
                return Result.err(
                    "WRITE_FAILED",
                    tostring(promote_error or next_path) ..
                    "; restore failed: " .. tostring(restore_error or backup_path)
                )
            end
            return Result.err("WRITE_FAILED", promote_error or next_path)
        end

        os.remove(backup_path)
    else
        local promoted, promote_error = os.rename(next_path, path)
        if not promoted then
            return Result.err("WRITE_FAILED", promote_error or next_path)
        end
    end

    return Result.ok(true)
end

function FileIO.append(path, line)
    local file = io.open(path, "a")
    if not file then return Result.err("APPEND_FAILED", path) end
    local failure = write_line(file, line, "APPEND_FAILED", path)
    if failure then
        file:close()
        return failure
    end
    failure = close_file(file, "APPEND_FAILED", path)
    if failure then return failure end
    return Result.ok(true)
end

function FileIO.exists(path)
    local recovered = recover_missing(path)
    return recovered.ok and recovered.value == true
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
