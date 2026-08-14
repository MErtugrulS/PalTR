local ChatReceiveProbe = require("chat_receive_probe")

local function equal(actual, expected, label)
    if actual ~= expected then
        error(string.format(
            "%s | expected=%s actual=%s",
            label,
            tostring(expected),
            tostring(actual)
        ))
    end
end

local wire_message = {
    Category = 1,
    Sender = "SYSTEM",
    Message = "PALTRUI1|SNAPSHOT_CHUNK|1|payload"
}
local committed_message = wire_message
local commit_count = 0
local wire_param = {
    get = function() return committed_message end,
    set = function(_, value)
        commit_count = commit_count + 1
        committed_message = value
    end
}
equal(
    ChatReceiveProbe.suppress_transport_frame(
        wire_param,
        { kind = "SNAPSHOT_CHUNK" }
    ),
    true,
    "wire frame suppressed"
)
equal(wire_message.Message, "", "wire payload hidden from Palworld chat")
equal(commit_count, 1, "runtime struct parameter explicitly committed")

local decoded_param_message = {
    Category = 1,
    Sender = "SYSTEM",
    Message = "PALTRUI1|SNAPSHOT_CHUNK|request:1:1|payload"
}
local decoded_param = {
    get = function()
        return {
            Category = decoded_param_message.Category,
            Sender = decoded_param_message.Sender,
            Message = decoded_param_message.Message
        }
    end,
    set = function(_, value)
        decoded_param_message.Message = value.Message
    end
}
local decoded_suppressed, decoded_frame =
    ChatReceiveProbe.suppress_trusted_transport(decoded_param)
equal(decoded_suppressed, true, "trusted transport hidden at filtered stage")
equal(decoded_frame.kind, "SNAPSHOT_CHUNK", "filtered frame still decoded")
equal(decoded_param_message.Message, "", "filtered payload removed")

equal(ChatReceiveProbe.is_trusted_source(1, "SYSTEM"), true,
    "verified system chat source trusted")
equal(ChatReceiveProbe.is_trusted_source("1", "SYSTEM"), true,
    "string system category trusted")
equal(ChatReceiveProbe.is_trusted_source(2, "SYSTEM"), false,
    "guild chat category rejected")
equal(ChatReceiveProbe.is_trusted_source(1, "Player"), false,
    "player sender rejected")

local normal_message = { Message = "Merhaba" }
equal(
    ChatReceiveProbe.suppress_transport_frame(
        { get = function() return normal_message end },
        nil
    ),
    false,
    "normal chat not suppressed"
)
equal(normal_message.Message, "Merhaba", "normal chat preserved")

local normal_system_message = {
    Category = 1,
    Sender = "SYSTEM",
    Message = "Karakol kaydedildi: Klan Bayragi"
}
local normal_suppressed, normal_frame, normal_reason =
    ChatReceiveProbe.suppress_trusted_transport({
        get = function() return normal_system_message end,
        set = function() error("normal system message must not be changed") end
    })
equal(normal_suppressed, false, "normal system response not hidden")
equal(normal_frame, nil, "normal system response is not a wire frame")
equal(normal_reason, "not_transport", "normal response rejection reason")
equal(normal_system_message.Message, "Karakol kaydedildi: Klan Bayragi",
    "normal PalTR command response preserved")

local spoof_message = {
    Category = 2,
    Sender = "Player",
    Message = "PALTRUI1|SNAPSHOT_CHUNK|request:1:1|payload"
}
local spoof_suppressed, spoof_frame, spoof_reason =
    ChatReceiveProbe.suppress_trusted_transport({
        get = function() return spoof_message end,
        set = function() error("untrusted wire-looking chat must not change") end
    })
equal(spoof_suppressed, false, "player wire-looking chat not hidden")
equal(spoof_frame.kind, "SNAPSHOT_CHUNK", "untrusted frame reported for audit")
equal(spoof_reason, "untrusted", "untrusted frame reason")
equal(spoof_message.Message,
    "PALTRUI1|SNAPSHOT_CHUNK|request:1:1|payload",
    "player chat preserved")

local original_register_hook = RegisterHook
local hook_order = {}
local hook_callbacks = {}
RegisterHook = function(path, callback)
    table.insert(hook_order, path)
    hook_callbacks[path] = callback
    return #hook_order * 2 - 1, #hook_order * 2
end
local received_frames = 0
equal(ChatReceiveProbe.register(function()
    received_frames = received_frames + 1
end), true, "chat transport hooks register")
equal(hook_order[1], "/Script/Pal.PalUIChat:OnFilteredChat",
    "final presentation gate registers before receiver")
equal(hook_order[2], "/Script/Pal.PalUIChat:OnReceivedChat",
    "snapshot receiver registers after privacy gate")

local filtered_message = {
    Category = 1,
    Sender = "SYSTEM",
    Message = "PALTRUI1|SNAPSHOT_CHUNK|filtered:1:1|payload"
}
hook_callbacks[hook_order[1]](nil, nil, {
    get = function() return filtered_message end,
    set = function(_, value) filtered_message = value end
})
equal(filtered_message.Message, "",
    "registered filtered hook removes private payload")
equal(received_frames, 0,
    "filtered hook does not feed snapshot assembly twice")
RegisterHook = original_register_hook

print("PALTR_UI_CHAT_RECEIVE_PROBE_TEST_OK")
