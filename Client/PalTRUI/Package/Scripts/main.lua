local PresentationController = require("presentation_controller")
local RendererHost = require("renderer_host")
local UMGWidgetPort = require("umg_widget_port")
local ChatReceiveProbe = require("chat_receive_probe")
local UIInteractionRouter = require("ui_interaction_router")
local PresentationSnapshotProbe = require("presentation_snapshot_probe")
local SnapshotInbox = require("snapshot_inbox")
local UMGButtonPoller = require("umg_button_poller")

local widget_port = UMGWidgetPort.new()
local presentation = PresentationController.new(
    RendererHost.new(widget_port)
)
local interactions = UIInteractionRouter.new(presentation)
local snapshots = SnapshotInbox.new(presentation)
local interactive_controls = {
    "CloseButton",
    "ClanTabButton",
    "DiplomacyTabButton",
    "AllianceTabButton",
    "AllianceRequestButton",
    "WarRequestButton",
    "AcceptButton",
    "RejectButton",
    "CancelButton"
}
local button_poller = UMGButtonPoller.new({
    widget_provider = function() return widget_port.widget end,
    router = interactions,
    control_names = interactive_controls,
    on_result = function(control, handled, model, interaction_error)
        print(string.format(
            "[PalTRUI] PALTR_UI_CLICK_%s | control=%s | tab=%s | error=%s\n",
            handled == true and "OK" or "ERROR",
            tostring(control),
            tostring(model and model.active_tab or ""),
            tostring(interaction_error or "")
        ))
    end
})

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
    if model.open == true then
        local started, start_error = button_poller:start()
        if started ~= true then
            print(string.format(
                "[PalTRUI] PALTR_UI_BUTTON_POLLER_ERROR | %s\n",
                tostring(start_error)
            ))
        end
    else
        button_poller:stop()
    end
end

RegisterKeyBind(Key.F6, function()
    if type(ExecuteInGameThread) == "function" then
        ExecuteInGameThread(toggle_panel)
    else
        toggle_panel()
    end
end)


RegisterKeyBind(Key.F7, function()
    print("[PalTRUI][UMG] F7_PROBE_DISABLED | runtime guvenligi\n")
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

local function apply_presentation_snapshot_probe()
    local current_model = presentation:model()
    local mode = PresentationSnapshotProbe.is_active(current_model)
        and "cycle" or "apply"
    local applied, model, probe_error
    if mode == "cycle" then
        applied, model, probe_error =
            PresentationSnapshotProbe.select_next(presentation)
    else
        applied, model, probe_error =
            PresentationSnapshotProbe.apply(presentation, snapshots)
    end
    if applied ~= true then
        print(string.format(
            "[PalTRUI] PALTR_UI_F10_ERROR | error=%s\n",
            tostring(probe_error or "bilinmeyen sunum probe hatasi")
        ))
        return
    end
    print(string.format(
        "[PalTRUI] PALTR_UI_F10_OK | tab=%s | guild=%s | mode=%s | probe=true\n",
        tostring(model.active_tab),
        tostring(model.selected_guild),
        mode
    ))
end

if Key.F10 ~= nil then
    RegisterKeyBind(Key.F10, function()
        if type(ExecuteInGameThread) == "function" then
            ExecuteInGameThread(apply_presentation_snapshot_probe)
        else
            apply_presentation_snapshot_probe()
        end
    end)
end
