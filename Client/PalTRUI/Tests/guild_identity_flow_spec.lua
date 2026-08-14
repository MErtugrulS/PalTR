local Contract = require("contract")
local PresentationController = require("presentation_controller")
local ChatCommandSender = require("chat_command_sender")
local ActionOutbox = require("action_outbox")

local function equal(actual, expected, label)
    if actual ~= expected then
        error(string.format("%s | expected=%s actual=%s", label,
            tostring(expected), tostring(actual)))
    end
end

local snapshot = {
    schema_version = Contract.SCHEMA_VERSION,
    generated_at = 77,
    player = { name = "Ada", guild_key = "guild-own", role = 1,
        is_master = true },
    guild = { key = "guild-own", name = "Anka" },
    members = {},
    relations = {},
    guild_identity = {
        palette_version = 1,
        selected_color_id = "",
        selected_emblem_id = "",
        locked = false,
        can_manage = true,
        colors = {
            { id = "azure", hex = "#2475D8", available = true },
            { id = "cyan", hex = "#18BBD1", available = false }
        },
        emblems = {
            { id = "wolf", name = "Kurt" },
            { id = "eagle", name = "Kartal" }
        }
    }
}

local envelopes = {}
local controller = PresentationController.new(nil, ActionOutbox.new({
    send = function(_, envelope)
        table.insert(envelopes, envelope)
        return true, envelope
    end
}))
equal(controller:apply_snapshot(snapshot), true, "identity snapshot accepted")
equal(controller:set_tab("MANAGEMENT"), true, "management tab accepted")
local color_ok = controller:select_guild_identity("color", "azure")
equal(color_ok, true, "available color selected")
local reserved_ok, _, _, reserved_error =
    controller:select_guild_identity("color", "cyan")
equal(reserved_ok, false, "reserved color rejected")
equal(reserved_error, "Seçilen klan rengi kullanılamıyor.",
    "reserved color reason")
local emblem_ok = controller:select_guild_identity("emblem", "wolf")
equal(emblem_ok, true, "emblem selected")
local sent = controller:request_guild_identity()
equal(sent, true, "identity action dispatched")
equal(#envelopes, 1, "identity action is one envelope")
equal(envelopes[1].kind, "GUILD_IDENTITY_ACTION", "identity action kind")
equal(envelopes[1].action_id, "SET_GUILD_IDENTITY", "identity action id")
equal(envelopes[1].color_id, "azure", "identity color transported")
equal(envelopes[1].emblem_id, "wolf", "identity emblem transported")

local calls = {}
local sender = ChatCommandSender.new({
    get_player_controller = function()
        return {
            IsValid = function() return true end,
            EnterChat_Receive = function(_, command, category)
                table.insert(calls, { command = command, category = category })
            end
        }
    end
})
local command_ok = sender:send(envelopes[1])
equal(command_ok, true, "identity command queued")
equal(calls[1].command, "!klankimlik azure wolf", "atomic identity command")
equal(calls[1].category, 2, "identity uses verified guild chat transport")
local injected, injection_error = sender:send({
    action_id = "SET_GUILD_IDENTITY",
    color_id = "azure\n!savas",
    emblem_id = "wolf"
})
equal(injected, false, "identity command injection rejected")
equal(injection_error:find("geçersiz", 1, true) ~= nil, true,
    "identity validation reason")

print("PALTR_UI_GUILD_IDENTITY_FLOW_TEST_OK")
