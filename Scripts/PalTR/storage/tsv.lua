local Text = require("PalTR.core.text")
local TSV = {}

function TSV.encode(values)
    local result = {}
    for index, value in ipairs(values or {}) do
        result[index] = Text.clean(value)
    end
    return table.concat(result, "\t")
end

function TSV.decode(line)
    local values = {}
    for value in (tostring(line or "") .. "\t"):gmatch("(.-)\t") do
        table.insert(values, value)
    end
    return values
end

return TSV
