local PresentationController = require("presentation_controller")
local RendererHost = require("renderer_host")
local UMGWidgetPort = require("umg_widget_port")
local ChatReceiveProbe = require("chat_receive_probe")
local UIInteractionRouter = require("ui_interaction_router")
local PresentationSnapshotProbe = require("presentation_snapshot_probe")
local SnapshotInbox = require("snapshot_inbox")
local SnapshotTransport = require("snapshot_transport")
local UMGButtonPoller = require("umg_button_poller")
local ActionOutbox = require("action_outbox")
local ChatCommandSender = require("chat_command_sender")
local ApplicationFocusGuard = require("application_focus_guard")

local widget_port = UMGWidgetPort.new()
local presentation = PresentationController.new(
    RendererHost.new(widget_port),
    ActionOutbox.new(ChatCommandSender.new())
)
local interactions = UIInteractionRouter.new(presentation)
local snapshots = SnapshotInbox.new(presentation)
local snapshot_transport = SnapshotTransport.new()
local interactive_controls = {
    "CloseButton",
    "ClanTabButton",
    "DiplomacyTabButton",
    "AllianceTabButton",
    "ChatTabButton",
    "DashboardDiplomacyButton",
    "DashboardOffersButton",
    "DashboardGuildsButton",
    "PreviousRelationButton",
    "NextRelationButton",
    "PreviousAllianceButton",
    "NextAllianceButton",
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
    on_resume = function(delayed_ticks)
        local refreshed, refresh_error = widget_port:refresh_input()
        print(string.format(
            "[PalTRUI] PALTR_UI_INPUT_RESUME_%s | delayed_ticks=%s | error=%s\n",
            refreshed == true and "OK" or "ERROR",
            tostring(delayed_ticks),
            tostring(refresh_error or "")
        ))
    end,
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

local focus_guard_ready, focus_guard_error = ApplicationFocusGuard.register({
    on_focus_lost = function()
        button_poller:stop()
        print("[PalTRUI] PALTR_UI_FOCUS_LOST | poller=stopped\n")
    end,
    on_focus_gained = function()
        local model = presentation:model()
        if type(model) ~= "table" or model.open ~= true then return end
        local refreshed, refresh_error = widget_port:refresh_input()
        if refreshed == true then
            button_poller:start()
        end
        print(string.format(
            "[PalTRUI] PALTR_UI_FOCUS_GAINED | refreshed=%s | error=%s\n",
            tostring(refreshed == true),
            tostring(refresh_error or "")
        ))
    end
})
if focus_guard_ready ~= true then
    print(string.format(
        "[PalTRUI] PALTR_UI_FOCUS_GUARD_ERROR | %s\n",
        tostring(focus_guard_error or "")
    ))
end

ChatReceiveProbe.register(function(frame)
    if frame.kind ~= "SNAPSHOT_CHUNK" then return end
    local complete, snapshot, transport_error =
        snapshot_transport:receive(frame)
    if transport_error ~= nil then
        print(string.format(
            "[PalTRUI] PALTR_UI_SNAPSHOT_TRANSPORT_ERROR | %s\n",
            tostring(transport_error)
        ))
        return
    end
    if complete ~= true then return end

    local accepted, model, rendered, receive_error =
        snapshots:receive(snapshot)
    print(string.format(
        "[PalTRUI] PALTR_UI_LIVE_SNAPSHOT_%s | generated_at=%s | rendered=%s | error=%s\n",
        accepted == true and "OK" or "ERROR",
        tostring(model and model.generated_at or ""),
        tostring(rendered == true),
        tostring(receive_error or "")
    ))
end)

PalTRUIKeybindCallbacks = PalTRUIKeybindCallbacks or {}
local keybind_callbacks = PalTRUIKeybindCallbacks
local function register_retained_keybind(name, key, callback)
    keybind_callbacks[name] = callback
    RegisterKeyBind(key, keybind_callbacks[name])
end

local tab_cycle = {
    { id = "CLAN", control = "ClanTabButton" },
    { id = "DIPLOMACY", control = "DiplomacyTabButton" },
    { id = "ALLIANCE", control = "AllianceTabButton" },
    { id = "GUILDS", control = "ChatTabButton" }
}

print("[PalTRUI] yuklendi\n")

local function toggle_panel()
    local current_model = presentation:model()
    local closing = type(current_model) == "table"
        and current_model.open == true
    if closing then
        button_poller:stop()
        print("[PalTRUI] PALTR_UI_CLOSE_STAGE | stage=poller_stopped\n")
    end

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
    elseif not closing then
        button_poller:stop()
    end
end

register_retained_keybind("F6", Key.F6, function()
    if type(ExecuteInGameThread) == "function" then
        ExecuteInGameThread(toggle_panel)
    else
        toggle_panel()
    end
end)

local function close_open_panel()
    local model = presentation:model()
    if type(model) ~= "table" or model.open ~= true then return end
    toggle_panel()
end

local function close_panel_keybind()
    if type(ExecuteInGameThread) == "function" then
        ExecuteInGameThread(close_open_panel)
    else
        close_open_panel()
    end
end

register_retained_keybind("TAB", Key.TAB, close_panel_keybind)


register_retained_keybind("F7", Key.F7, function()
    print("[PalTRUI][UMG] F7_PROBE_DISABLED | runtime guvenligi\n")
end)

register_retained_keybind("F8", Key.F8, function()
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

register_retained_keybind("F9", Key.F9, function()
    if type(ExecuteInGameThread) == "function" then
        ExecuteInGameThread(cycle_tab)
    else
        cycle_tab()
    end
end)

local function apply_presentation_snapshot_probe()
    local current_model = presentation:model()
    print("[PalTRUI] PALTR_UI_F10_STAGE | stage=begin\n")
    if PresentationSnapshotProbe.can_apply(current_model) ~= true then
        print("[PalTRUI] PALTR_UI_F10_BLOCKED | paneli once Tab ile kapat\n")
        return
    end
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
    register_retained_keybind("F10", Key.F10, function()
        if type(ExecuteInGameThread) == "function" then
            ExecuteInGameThread(apply_presentation_snapshot_probe)
        else
            apply_presentation_snapshot_probe()
        end
    end)
end
