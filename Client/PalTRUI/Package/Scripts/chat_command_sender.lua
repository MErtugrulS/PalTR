local ChatCommandSender = {}
ChatCommandSender.__index = ChatCommandSender

local CHAT_CATEGORY_GUILD = 2

local command_by_action = {
    DECLARE_WAR = "!savas",
    CEASEFIRE = "!ateskes",
    BREAK_CEASEFIRE = "!ateskesboz",
    PEACE = "!baris",
    ALLIANCE = "!ittifak",
    ACCEPT = "!kabul",
    REJECT = "!reddet",
    CANCEL = "!iptal",
    RETURN_NEUTRAL = "!tarafsiz"
}

local function default_get_player_controller()
    local loaded, helpers = pcall(require, "UEHelpers")
    if not loaded or type(helpers) ~= "table"
        or type(helpers.GetPlayerController) ~= "function" then
        return nil
    end
    local found, controller = pcall(helpers.GetPlayerController)
    if not found then return nil end
    return controller
end

local function valid_object(object)
    if object == nil then return false end
    local checked, valid = pcall(function()
        return object:IsValid()
    end)
    return checked and valid == true
end

local function target_key(envelope)
    local key = type(envelope) == "table"
        and tostring(envelope.guild_key or "") or ""
    if key == "" or #key > 160 or key:find("[\r\n]") then
        return nil
    end
    return key
end

function ChatCommandSender.new(api)
    api = type(api) == "table" and api or {}
    return setmetatable({
        get_player_controller = api.get_player_controller
            or default_get_player_controller,
        chat_category = api.chat_category or CHAT_CATEGORY_GUILD
    }, ChatCommandSender)
end

function ChatCommandSender:send(envelope)
    local action_id = type(envelope) == "table"
        and tostring(envelope.action_id or "") or ""
    local command_name = command_by_action[action_id]
    if command_name == nil then
        return false, "UI aksiyonu icin sunucu komutu tanimli degil."
    end

    local key = target_key(envelope)
    if key == nil then
        return false, "UI aksiyonu hedef klan kimligi gecersiz."
    end

    local controller = self.get_player_controller()
    if not valid_object(controller) then
        return false, "Yerel PlayerController bulunamadi."
    end

    local command = command_name .. " " .. key
    local sent, send_error = pcall(function()
        controller:EnterChat_Receive(command, self.chat_category)
    end)
    if not sent then
        return false, "Sunucu komutu gonderilemedi: " .. tostring(send_error)
    end

    return true, {
        request_id = envelope.request_id,
        action_id = action_id,
        guild_key = key,
        command = command,
        queued = true
    }
end

return ChatCommandSender
