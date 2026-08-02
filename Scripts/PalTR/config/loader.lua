local Defaults = require("PalTR.config.defaults")
local Logger = require("PalTR.core.logger")

local Loader = {}

function Loader.load()
    local logger = Logger.new("Config")
    local ok, local_config = pcall(require, "PalTR.config.local")
    if not ok or type(local_config) ~= "table" then
        logger:info("Varsayilan ayarlar kullaniliyor")
        return Defaults
    end

    for section, values in pairs(local_config) do
        if type(values) == "table" and type(Defaults[section]) == "table" then
            for key, value in pairs(values) do
                Defaults[section][key] = value
            end
        else
            Defaults[section] = values
        end
    end

    logger:info("Yerel ayarlar uygulandi")
    return Defaults
end

return Loader
