local Defaults = require("PalTR.config.defaults")
local Logger = require("PalTR.core.logger")

local Loader = {}

local function copy(value, seen)
    if type(value) ~= "table" then return value end

    seen = seen or {}
    if seen[value] then return seen[value] end

    local result = {}
    seen[value] = result
    for key, item in pairs(value) do
        result[copy(key, seen)] = copy(item, seen)
    end
    return result
end

function Loader.load()
    local logger = Logger.new("Config")
    local config = copy(Defaults)
    local ok, local_config = pcall(require, "PalTR.config.local")
    if not ok or type(local_config) ~= "table" then
        logger:info("Varsayilan ayarlar kullaniliyor")
        return config
    end

    for section, values in pairs(local_config) do
        if type(values) == "table" and type(config[section]) == "table" then
            for key, value in pairs(values) do
                config[section][key] = copy(value)
            end
        else
            config[section] = copy(values)
        end
    end

    logger:info("Yerel ayarlar uygulandi")
    return config
end

return Loader
