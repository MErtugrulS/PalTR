local PanelState = require("panel_state")
local UMGProbe = require("umg_probe")
local ChatReceiveProbe = require("chat_receive_probe")

local panel = PanelState.new()

print("[PalTRUI] yuklendi\n")

local function toggle_panel()
    local opened = panel:toggle()
    print(string.format(
        "[PalTRUI] PALTR_UI_F6_OK | open=%s | tab=%s\n",
        tostring(opened),
        tostring(panel.active_tab)
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
