local Version = require("PalTR.core.version")
local Text = require("PalTR.core.text")

local Logger = {}
Logger.__index = Logger

function Logger.new(scope)
    return setmetatable({ scope = Text.clean(scope or "App") }, Logger)
end

function Logger:_write(level, message)
    print(string.format(
        "[%s v%s] [%s] [%s] %s",
        Version.package,
        Version.version,
        level,
        self.scope,
        Text.clean(message)
    ))
end

function Logger:info(message) self:_write("BILGI", message) end
function Logger:warn(message) self:_write("UYARI", message) end
function Logger:error(message) self:_write("HATA", message) end

return Logger
