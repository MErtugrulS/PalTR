local PresentationController = require("presentation_controller")
local RendererHost = require("renderer_host")
local UMGWidgetPort = require("umg_widget_port")
local UMGProbe = require("umg_probe")
local ChatReceiveProbe = require("chat_receive_probe")

local presentation = PresentationController.new(
    RendererHost.new(UMGWidgetPort.new())
)

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
