local PanelState = require("panel_state")

local PresentationController = {}
PresentationController.__index = PresentationController

local null_renderer = {
    render = function() end
}

local function renderer_or_null(renderer)
    if type(renderer) == "table"
        and type(renderer.render) == "function" then
        return renderer
    end
    return null_renderer
end

function PresentationController.new(renderer)
    local controller = setmetatable({
        panel = PanelState.new(),
        renderer = renderer_or_null(renderer)
    }, PresentationController)
    controller:_render()
    return controller
end

function PresentationController:model()
    return self.panel.view_model
end

function PresentationController:_render()
    self.renderer:render(self:model())
end

function PresentationController:toggle()
    self.panel:toggle()
    self:_render()
    return self:model()
end

function PresentationController:set_tab(tab_id)
    local accepted = self.panel:set_tab(tab_id)
    self:_render()
    return accepted, self:model()
end

function PresentationController:select_guild(guild_key)
    self.panel:select_guild(guild_key)
    self:_render()
    return self:model()
end

function PresentationController:apply_snapshot(snapshot)
    local accepted = self.panel:apply_snapshot(snapshot)
    self:_render()
    return accepted, self:model()
end

return PresentationController
