local PresentationController = require("presentation_controller")
local RendererHost = require("renderer_host")
local UMGWidgetPort = require("umg_widget_port")
local ChatReceiveProbe = require("chat_receive_probe")
local UIInteractionRouter = require("ui_interaction_router")
local PresentationSnapshotProbe = require("presentation_snapshot_probe")
local SnapshotInbox = require("snapshot_inbox")
local SnapshotTransport = require("snapshot_transport")
local UMGButtonHookPoller = require("umg_button_hook_poller")
local ActionOutbox = require("action_outbox")
local ChatCommandSender = require("chat_command_sender")
local DesignTemplateEventBridge = require("design_template_event_bridge")

-- The map overlay is independent from the F6 panel. Its runtime hooks are
-- event-driven and the Palworld projection signature is covered by the
-- territory overlay contract test.
local ENABLE_TERRITORY_MAP_OVERLAY = true
local TerritoryMapOverlay = ENABLE_TERRITORY_MAP_OVERLAY
    and require("territory_map_overlay") or nil

local widget_port = UMGWidgetPort.new()
local chat_command_sender = ChatCommandSender.new()
local presentation = PresentationController.new(
    RendererHost.new(widget_port),
    ActionOutbox.new(chat_command_sender)
)
local interactions = UIInteractionRouter.new(presentation)
local design_events = DesignTemplateEventBridge.new(interactions)
local snapshots = SnapshotInbox.new(presentation)
local snapshot_transport = SnapshotTransport.new()
local territory_map_overlay = nil
if ENABLE_TERRITORY_MAP_OVERLAY then
    territory_map_overlay = TerritoryMapOverlay.new({
        request_snapshot = function()
            return chat_command_sender:request_snapshot()
        end
    })
end
local interactive_controls = {
    "CloseButton",
    {
        widgets = { "C_HomeButton", "C_Home" },
        control = "ClanTabButton"
    },
    {
        widgets = { "C_DiplomacyButton", "C_Diplomacy" },
        control = "DiplomacyTabButton"
    },
    { widget = "YonetimButton", control = "ManagementTabButton" },
    "AllianceTabButton",
    "ChatTabButton",
    { widget = "TemplateOpenDiplomacy", control = "DashboardDiplomacyButton" },
    "DashboardOffersButton",
    "DashboardGuildsButton",
    "DashboardPendingAcceptButton",
    "DashboardPendingRejectButton",
    "PreviousRelationButton",
    "NextRelationButton",
    "PreviousAllianceButton",
    "NextAllianceButton",
    { widget = "TemplateDiplomacyAllianceButton", control = "AllianceRequestButton" },
    { widget = "TemplateDiplomacyWarButton", control = "WarRequestButton" },
    { widget = "TemplateDiplomacyAcceptButton", control = "AcceptButton" },
    { widget = "TemplateDiplomacyRejectButton", control = "RejectButton" },
    { widget = "TemplateDiplomacyCancelButton", control = "CancelButton" }
}
for index = 1, 6 do
    table.insert(interactive_controls, {
        widget = string.format("TemplateDiplomacyRelationButton_%02d", index),
        control = string.format("DiplomacyRelationRowButton%02d", index)
    })
end
for index = 1, 16 do
    table.insert(interactive_controls,
        string.format("GuildIdentityColorButton%02d", index))
end
for index = 1, 12 do
    table.insert(interactive_controls,
        string.format("GuildIdentityEmblemButton%02d", index))
end
table.insert(interactive_controls, "GuildIdentitySaveButton")
local button_poller = UMGButtonHookPoller.new({
    widget_provider = function() return widget_port.widget end,
    router = interactions,
    control_names = interactive_controls,
    poll_interval_seconds = 0.125,
    on_resume = function(resumed_at)
        local refreshed, refresh_error = widget_port:refresh_input()
        print(string.format(
            "[PalTRUI] PALTR_UI_INPUT_RESUME_%s | resumed_at=%s | error=%s\n",
            refreshed == true and "OK" or "ERROR",
            tostring(resumed_at),
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

    if territory_map_overlay ~= nil then
        territory_map_overlay:set_snapshot(snapshot)
    end

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

if territory_map_overlay ~= nil then
    local map_registered, map_register_error =
        territory_map_overlay:register()
    print(string.format(
        "[PalTRUI] PALTR_MAP_OVERLAY_%s | error=%s\n",
        map_registered == true and "READY" or "DISABLED",
        tostring(map_register_error or "")
    ))
else
    print("[PalTRUI] PALTR_MAP_OVERLAY_DISABLED | safe_homepage_mode=true\n")
end

PalTRUIKeybindCallbacks = PalTRUIKeybindCallbacks or {}
local keybind_callbacks = PalTRUIKeybindCallbacks
PalTRUIToggleGate = PalTRUIToggleGate or {
    busy = false,
    last_toggle_at = 0,
    last_source = ""
}
local toggle_gate = PalTRUIToggleGate
toggle_gate.last_source = tostring(toggle_gate.last_source or "")
local TOGGLE_COOLDOWN_SECONDS = 2
local function register_retained_keybind(name, key, callback)
    keybind_callbacks[name] = callback
    RegisterKeyBind(key, keybind_callbacks[name])
end

local tab_cycle = {
    { id = "CLAN", control = "ClanTabButton" },
    { id = "DIPLOMACY", control = "DiplomacyTabButton" },
    { id = "ALLIANCE", control = "AllianceTabButton" },
    { id = "GUILDS", control = "ChatTabButton" },
    { id = "MANAGEMENT", control = "ManagementTabButton" }
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
        local registered, register_error = design_events:register()
        print(string.format(
            "[PalTRUI] PALTR_UI_DESIGN_EVENTS_%s | error=%s\n",
            registered == true and "READY" or "ERROR",
            tostring(register_error or "")
        ))
        if registered ~= true then
            local started, start_error = button_poller:start()
            print(string.format(
                "[PalTRUI] PALTR_UI_BUTTON_FALLBACK_%s | interval=0.125 | error=%s\n",
                started == true and "READY" or "ERROR",
                tostring(start_error or "")
            ))
        else
            button_poller:stop()
        end
    elseif not closing then
        button_poller:stop()
    end
end

local function request_panel_toggle(source, close_only)
    local model = presentation:model()
    if close_only == true
        and (type(model) ~= "table" or model.open ~= true) then
        return
    end

    local now = os.time()
    local repeated_source = toggle_gate.last_source == tostring(source)
    if toggle_gate.busy == true
        or (repeated_source
            and now - toggle_gate.last_toggle_at < TOGGLE_COOLDOWN_SECONDS) then
        print(string.format(
            "[PalTRUI] PALTR_UI_TOGGLE_IGNORED | source=%s | busy=%s | cooldown=true\n",
            tostring(source),
            tostring(toggle_gate.busy == true)
        ))
        return
    end

    toggle_gate.busy = true
    toggle_gate.last_toggle_at = now
    toggle_gate.last_source = tostring(source)
    local function guarded_toggle()
        local completed, toggle_error = pcall(toggle_panel)
        toggle_gate.busy = false
        if completed ~= true then
            print(string.format(
                "[PalTRUI] PALTR_UI_TOGGLE_ERROR | source=%s | error=%s\n",
                tostring(source),
                tostring(toggle_error or "bilinmeyen toggle hatasi")
            ))
        end
    end

    if type(ExecuteInGameThread) == "function" then
        ExecuteInGameThread(guarded_toggle)
    else
        guarded_toggle()
    end
end

register_retained_keybind("F6", Key.F6, function()
    request_panel_toggle("F6", false)
end)

local function close_panel_keybind()
    request_panel_toggle("TAB", true)
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
