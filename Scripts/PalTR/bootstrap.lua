local Config = require("PalTR.config.loader")
local App = require("PalTR.app")
local Logger = require("PalTR.core.logger")

local Bootstrap = {}

function Bootstrap.start()
    local logger = Logger.new("Bootstrap")
    logger:info("PalTR yukleniyor")
    local app = App.new(Config.load())
    app:start()
    logger:info("PalTR hazir")
end

return Bootstrap
