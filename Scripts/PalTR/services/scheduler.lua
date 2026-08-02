local Scheduler = {}
Scheduler.__index = Scheduler

function Scheduler.new(logger)
    return setmetatable({ logger = logger }, Scheduler)
end

function Scheduler:start(interval_ms, callback)
    if type(LoopAsync) ~= "function" then
        self.logger:warn("LoopAsync bulunamadi")
        return false
    end

    LoopAsync(interval_ms, function()
        local ok, error_message = pcall(callback)
        if not ok then
            self.logger:error("Zamanlayici: " .. tostring(error_message))
        end
        return false
    end)

    self.logger:info("Zamanlayici basladi")
    return true
end

return Scheduler
