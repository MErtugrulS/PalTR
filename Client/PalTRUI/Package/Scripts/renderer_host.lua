local RendererHost = {}
RendererHost.__index = RendererHost

local function valid_port(port)
    return type(port) == "table"
        and type(port.open) == "function"
        and type(port.update) == "function"
        and type(port.close) == "function"
end

function RendererHost.new(widget_port)
    return setmetatable({
        widget_port = valid_port(widget_port) and widget_port or nil,
        opened = false
    }, RendererHost)
end

function RendererHost:available()
    return self.widget_port ~= nil
end

function RendererHost:render(model)
    if type(model) ~= "table" then
        return false, "Gorunum modeli bulunamadi."
    end

    if not self:available() then
        return false, "UMG widget portu hazir degil."
    end

    if model.open == true then
        if not self.opened then
            local opened, open_error = self.widget_port:open(model)
            if opened ~= true then return false, open_error end
            self.opened = true
        end
        return self.widget_port:update(model)
    end

    if self.opened then
        local closed, close_error = self.widget_port:close()
        if closed ~= true then return false, close_error end
        self.opened = false
    end

    return true
end

return RendererHost
