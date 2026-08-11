local TempPath = {}

function TempPath.prefix(label)
    local root = os.getenv("TEMP") or os.getenv("TMP") or "."
    local separator = package.config:sub(1, 1)
    local token = os.tmpname():match("[^\\/]+$") or tostring(os.time())
    return root .. separator .. token .. "_" .. tostring(label or "paltr")
end

return TempPath
