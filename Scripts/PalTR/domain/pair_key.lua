local Result = require("PalTR.core.result")
local Text = require("PalTR.core.text")

local PairKey = {}

function PairKey.create(first, second)
    local a = Text.clean(first)
    local b = Text.clean(second)

    if a == "" or b == "" then
        return Result.err("EMPTY_GUILD", "Klan anahtari bos")
    end
    if a == b then
        return Result.err("SAME_GUILD", "Ayni klan hedeflenemez")
    end

    if a < b then
        return Result.ok({ key = a .. "::" .. b, a = a, b = b })
    end
    return Result.ok({ key = b .. "::" .. a, a = b, b = a })
end

return PairKey
