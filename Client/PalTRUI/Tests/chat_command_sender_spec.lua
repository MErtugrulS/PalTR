local ChatCommandSender = require("chat_command_sender")

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

local calls = {}
local controller = {
    IsValid = function() return true end,
    EnterChat_Receive = function(_, message, category)
        table.insert(calls, { message = message, category = category })
    end
}
local sender = ChatCommandSender.new({
    get_player_controller = function() return controller end
})

local sent, receipt = sender:send({
    request_id = "ui-action-1",
    action_id = "DECLARE_WAR",
    guild_key = "guild-other"
})
equal(sent, true, "verified server rpc queued")
equal(receipt.queued, true, "receipt marked queued")
equal(receipt.request_id, "ui-action-1", "request id preserved")
equal(calls[1].message, "!savas guild-other", "existing command reused")
equal(calls[1].category, 2, "guild chat category used")

local mappings = {
    CEASEFIRE = "!ateskes",
    BREAK_CEASEFIRE = "!ateskesboz",
    PEACE = "!baris",
    ALLIANCE = "!ittifak",
    ACCEPT = "!kabul",
    REJECT = "!reddet",
    CANCEL = "!iptal",
    RETURN_NEUTRAL = "!tarafsiz"
}
for action_id, command in pairs(mappings) do
    local ok = sender:send({
        request_id = "mapping",
        action_id = action_id,
        guild_key = "guild-target"
    })
    equal(ok, true, action_id .. " mapped")
    equal(calls[#calls].message, command .. " guild-target",
        action_id .. " existing command")
end

local unknown, unknown_error = sender:send({
    action_id = "UNKNOWN",
    guild_key = "guild-other"
})
equal(unknown, false, "unknown action rejected")
equal(unknown_error, "UI aksiyonu icin sunucu komutu tanimli degil.",
    "unknown action error")

local newline = sender:send({
    action_id = "DECLARE_WAR",
    guild_key = "guild\n!test"
})
equal(newline, false, "newline target rejected")

local missing = ChatCommandSender.new({
    get_player_controller = function() return nil end
}):send({
    action_id = "DECLARE_WAR",
    guild_key = "guild-other"
})
equal(missing, false, "missing controller rejected")

local failed, failed_error = ChatCommandSender.new({
    get_player_controller = function()
        return {
            IsValid = function() return true end,
            EnterChat_Receive = function() error("rpc failed") end
        }
    end
}):send({
    action_id = "DECLARE_WAR",
    guild_key = "guild-other"
})
equal(failed, false, "rpc failure returned")
equal(failed_error:find("rpc failed", 1, true) ~= nil, true,
    "rpc error preserved")

print("PALTR_UI_CHAT_COMMAND_SENDER_TEST_OK")
