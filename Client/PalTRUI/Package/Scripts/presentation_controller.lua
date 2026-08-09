local PanelState = require("panel_state")
local ActionIntent = require("action_intent")
local ActionOutbox = require("action_outbox")
local RelationNavigator = require("relation_navigator")

local PresentationController = {}
PresentationController.__index = PresentationController

local null_renderer = {
    render = function() return true end
}

local null_action_sink = ActionOutbox.new()

local function renderer_or_null(renderer)
    if type(renderer) == "table"
        and type(renderer.render) == "function" then
        return renderer
    end
    return null_renderer
end

local function action_sink_or_null(action_sink)
    if type(action_sink) == "table"
        and type(action_sink.dispatch) == "function" then
        return action_sink, true
    end
    return null_action_sink, false
end

function PresentationController.new(renderer, action_sink)
    local resolved_action_sink, action_transport_ready =
        action_sink_or_null(action_sink)
    local controller = setmetatable({
        panel = PanelState.new({
            action_transport_ready = action_transport_ready
        }),
        renderer = renderer_or_null(renderer),
        action_sink = resolved_action_sink
    }, PresentationController)
    controller:_render()
    return controller
end

function PresentationController:model()
    return self.panel.view_model
end

function PresentationController:_render()
    local rendered, render_error = self.renderer:render(self:model())
    if rendered == false then return false, render_error end
    return true
end

function PresentationController:toggle()
    self.panel:toggle()
    local rendered, render_error = self:_render()
    return self:model(), rendered, render_error
end

function PresentationController:set_tab(tab_id)
    local accepted = self.panel:set_tab(tab_id)
    local rendered, render_error = self:_render()
    return accepted, self:model(), rendered, render_error
end

function PresentationController:open_relation(tab_id, guild_key)
    local tab_accepted = self.panel:set_tab(tab_id)
    if tab_accepted ~= true then
        return false, self:model(), false, self:model().error
    end
    local guild_accepted = self.panel:select_guild(guild_key)
    local rendered, render_error = self:_render()
    return guild_accepted, self:model(), rendered, render_error
end

function PresentationController:select_guild(guild_key)
    local accepted = self.panel:select_guild(guild_key)
    local rendered, render_error = self:_render()
    return accepted, self:model(), rendered, render_error
end

function PresentationController:navigate_relation(step)
    return RelationNavigator.select(self, step)
end

function PresentationController:apply_snapshot(snapshot)
    local accepted = self.panel:apply_snapshot(snapshot)
    local rendered, render_error = self:_render()
    return accepted, self:model(), rendered, render_error
end

function PresentationController:set_chat_available(available)
    self.panel:set_chat_available(available)
    self:_render()
    return self:model()
end

function PresentationController:replace_chat(messages)
    local accepted = self.panel:replace_chat(messages)
    if accepted then self:_render() end
    return accepted, self:model()
end

function PresentationController:append_chat(message)
    local accepted = self.panel:append_chat(message)
    if accepted then self:_render() end
    return accepted, self:model()
end

function PresentationController:clear_chat()
    self.panel:clear_chat()
    self:_render()
    return self:model()
end

function PresentationController:request_action(action_id)
    local intent, error_message = ActionIntent.build(
        self:model(),
        action_id
    )
    if intent == nil then
        return false, error_message
    end
    return self.action_sink:dispatch(intent)
end

return PresentationController
