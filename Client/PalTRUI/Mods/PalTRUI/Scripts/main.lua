local PanelState = require("panel_state")

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
