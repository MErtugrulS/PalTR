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

return Result
