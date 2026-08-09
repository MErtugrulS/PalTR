local ActionOutbox = require("action_outbox")

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

local sent = {}
local outbox = ActionOutbox.new({
    send = function(_, envelope)
        table.insert(sent, envelope)
        return true, envelope
    end
})
local intent = {
    kind = "DIPLOMACY_ACTION",
    guild_key = "guild-other",
    action_id = "DECLARE_WAR",
    snapshot_generated_at = 100
}

local dispatched, envelope = outbox:dispatch(intent)
equal(dispatched, true, "valid action dispatched")
equal(envelope, sent[1], "sender result returned")
equal(envelope.version, 1, "action envelope version")
equal(envelope.request_id, "ui-action-1", "first request id")
equal(envelope.guild_key, "guild-other", "guild preserved")
equal(envelope.action_id, "DECLARE_WAR", "action preserved")
equal(envelope.snapshot_generated_at, 100, "snapshot time preserved")

local second, second_envelope = outbox:dispatch(intent)
equal(second, true, "second action dispatched")
equal(second_envelope.request_id, "ui-action-2", "request id increments")

local invalid, invalid_error = outbox:dispatch({})
equal(invalid, false, "invalid intent rejected")
equal(invalid_error, "UI aksiyon intenti gecersiz: kind",
    "invalid intent field returned")
equal(#sent, 2, "invalid intent does not reach sender")

local unavailable, unavailable_error = ActionOutbox.new():dispatch(intent)
equal(unavailable, false, "missing sender rejected")
equal(unavailable_error, "Client-server UI transportu hazir degil.",
    "missing sender error")

local failed, failed_error = ActionOutbox.new({
    send = function() return false, "sender failed" end
}):dispatch(intent)
equal(failed, false, "sender failure returned")
equal(failed_error, "sender failed", "sender error preserved")

print("PALTR_UI_ACTION_OUTBOX_TEST_OK")
