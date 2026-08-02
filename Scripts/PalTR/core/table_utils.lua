local TableUtils = {}

function TableUtils.sorted_keys(source)
    local keys = {}
    for key in pairs(source or {}) do table.insert(keys, key) end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    return keys
end

function TableUtils.count(source)
    local count = 0
    for _ in pairs(source or {}) do count = count + 1 end
    return count
end

return TableUtils
