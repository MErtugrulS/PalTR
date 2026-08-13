local Result = {}

function Result.ok(value)
    return { ok = true, value = value }
end

function Result.err(code, message)
    return {
        ok = false,
        error = {
            code = tostring(code or "UNKNOWN"),
            message = tostring(message or "")
        }
    }
end

function Result.describe(result)
    local failure = result and result.error or result
    if type(failure) ~= "table" then return tostring(failure or "") end

    local code = tostring(failure.code or "")
    local message = tostring(failure.message or "")
    if code == "" then return message end
    if message == "" then return code end
    return code .. ": " .. message
end

return Result
