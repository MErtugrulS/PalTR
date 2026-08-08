local PanelState = require("panel_state")

local PresentationController = {}
PresentationController.__index = PresentationController

function PresentationController.new()
    return setmetatable({
        panel = PanelState.new()
    }, PresentationController)
end

function PresentationController:model()
    return self.panel.view_model
end

function PresentationController:toggle()
    self.panel:toggle()
    return self:model()
end

function PresentationController:set_tab(tab_id)
    local accepted = self.panel:set_tab(tab_id)
    return accepted, self:model()
end

function PresentationController:select_guild(guild_key)
    self.panel:select_guild(guild_key)
    return self:model()
end

function PresentationController:apply_snapshot(snapshot)
    local accepted = self.panel:apply_snapshot(snapshot)
    return accepted, self:model()
end

return PresentationController
