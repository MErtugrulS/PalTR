local PresentationController = require("presentation_controller")
local RendererHost = require("renderer_host")
local UMGWidgetPort = require("umg_widget_port")
local UMGProbe = require("umg_probe")
local ChatReceiveProbe = require("chat_receive_probe")
local UIInteractionRouter = require("ui_interaction_router")

local presentation = PresentationController.new(
    RendererHost.new(UMGWidgetPort.new())
)
local interactions = UIInteractionRouter.new(presentation)

local tab_cycle = {
    { id = "CLAN", control = "ClanTabButton" },
    { id = "DIPLOMACY", control = "DiplomacyTabButton" },
    { id = "ALLIANCE", control = "AllianceTabButton" },
    { id = "CHAT", control = "ChatTabButton" }
}

print("[PalTRUI] yuklendi\n")

local function toggle_panel()
    local model, rendered, render_error = presentation:toggle()
    if rendered ~= true then
        print(string.format(
            "[PalTRUI] PALTR_UI_F6_ERROR | open=%s | tab=%s | error=%s\n",
            tostring(model.open),
            tostring(model.active_tab),
            tostring(render_error or "bilinmeyen renderer hatasi")
        ))
        return
    end
    print(string.format(
        "[PalTRUI] PALTR_UI_F6_OK | open=%s | tab=%s\n",
        tostring(model.open),
        tostring(model.active_tab)
    ))
end

RegisterKeyBind(Key.F6, function()
    if type(ExecuteInGameThread) == "function" then
        ExecuteInGameThread(toggle_panel)
    else
        toggle_panel()
    end
end)


RegisterKeyBind(Key.F7, function()
    local function run_probe()
        UMGProbe.scan()
    end
    if type(ExecuteInGameThread) == "function" then
        ExecuteInGameThread(run_probe)
    else
        run_probe()
    end
end)

RegisterKeyBind(Key.F8, function()
    ChatReceiveProbe.register()
end)

local function cycle_tab()
    local active_tab = tostring(presentation:model().active_tab or "")
    local next_index = 1
    for index, tab in ipairs(tab_cycle) do
        if tab.id == active_tab then
            next_index = index % #tab_cycle + 1
            break
        end
    end

    local handled, model, _, interaction_error =
        interactions:handle(tab_cycle[next_index].control)
    if handled ~= true then
        print(string.format(
            "[PalTRUI] PALTR_UI_F9_ERROR | tab=%s | error=%s\n",
            tostring(model and model.active_tab or active_tab),
            tostring(interaction_error or "bilinmeyen etkilesim hatasi")
        ))
        return
    end
    print(string.format(
        "[PalTRUI] PALTR_UI_F9_OK | tab=%s\n",
        tostring(model.active_tab)
    ))
end

RegisterKeyBind(Key.F9, function()
    if type(ExecuteInGameThread) == "function" then
        ExecuteInGameThread(cycle_tab)
    else
        cycle_tab()
    end
end)
