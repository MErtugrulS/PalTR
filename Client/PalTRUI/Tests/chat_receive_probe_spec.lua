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

local wire_message = { Message = "PALTRUI1|SNAPSHOT_CHUNK|1|payload" }
local wire_param = {
    get = function() return wire_message end
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

print("PALTR_UI_CHAT_RECEIVE_PROBE_TEST_OK")
