local UE = require("PalTR.runtime.ue")

local PrivateMessenger = {}

local PAL_UTILITY_CDO =
    "/Script/Pal.Default__PalUtility"

local function write_log(logger, level, message)
    local written = false

    if logger ~= nil then
        written = pcall(function()
            local log_function = logger[level]

            if type(log_function) ~= "function" then
                error("Logger fonksiyonu bulunamadi")
            end

            log_function(logger, message)
        end)
    end

    if not written then
        print(
            "[PalTR PrivateMessenger] " ..
            tostring(message)
        )
    end
end

local function read_property(object, property_name)
    if object == nil then
        return nil
    end

    local direct_ok, direct_value = pcall(function()
        return object[property_name]
    end)

    if direct_ok and direct_value ~= nil then
        return direct_value
    end

    local getter_ok, getter_value = pcall(function()
        return object:GetPropertyValue(property_name)
    end)

    if getter_ok and getter_value ~= nil then
        return getter_value
    end

    return nil
end

local function find_player_state(controller, player)
    local controller_state = UE.unwrap(
        read_property(controller, "PlayerState")
    )
    if controller_state ~= nil then
        return controller_state, "controller.PlayerState"
    end

    local getter_ok, getter_value = pcall(function()
        return controller:GetPlayerState()
    end)
    if getter_ok then
        local getter_state = UE.unwrap(getter_value)
        if getter_state ~= nil then
            return getter_state, "controller:GetPlayerState"
        end
    end

    if player ~= nil then
        local snake_state = UE.unwrap(
            read_property(player, "player_state")
        )
        if snake_state ~= nil then
            return snake_state, "player.player_state"
        end

        local camel_state = UE.unwrap(
            read_property(player, "playerState")
        )
        if camel_state ~= nil then
            return camel_state, "player.playerState"
        end
    end

    error("PlayerState bulunamadi")
end

local function find_player_uid(controller, player)
    local player_state, state_source =
        find_player_state(controller, player)

    local names = {
        "PlayerUId",
        "PlayerUID",
        "PlayerUid"
    }

    for _, property_name in ipairs(names) do
        local value =
            read_property(player_state, property_name)

        if value ~= nil then
            return value,
                state_source .. "." .. property_name
        end
    end

    error(
        "PlayerState bulundu fakat PlayerUId okunamadi | " ..
        tostring(state_source)
    )
end

function PrivateMessenger.send_many(
    world_context,
    player,
    messages,
    logger
)
    local context = UE.unwrap(world_context)

    if context == nil then
        write_log(
            logger,
            "warn",
            "OZEL_CHAT_HATA | controller/context yok"
        )

        return false
    end

    if type(messages) ~= "table" or #messages == 0 then
        write_log(
            logger,
            "warn",
            "OZEL_CHAT_HATA | mesaj listesi bos"
        )

        return false
    end

    local pending_messages = {}
    for index = 1, #messages do
        local text = tostring(messages[index] or "")
        if text == "" then
            write_log(
                logger,
                "warn",
                "OZEL_CHAT_HATA | mesaj bos | index=" ..
                tostring(index)
            )
            return false
        end
        pending_messages[index] = text
    end

    local function send_on_game_thread()
        local ok, error_message = pcall(function()
            local utility =
                StaticFindObject(PAL_UTILITY_CDO)

            if utility == nil then
                error("PalUtility CDO bulunamadi")
            end

            local receiver_uid, uid_source =
                find_player_uid(context, player)

            write_log(
                logger,
                "info",
                "OZEL_CHAT_UID_HAZIR | source=" ..
                tostring(uid_source) ..
                " | player_uid_text=" ..
                tostring(
                    player and player.uid or ""
                ) ..
                " | raw_type=" ..
                type(receiver_uid)
            )

            for index = 1, #pending_messages do
                utility:SendSystemToPlayerChat(
                    context,
                    pending_messages[index],
                    {
                        receiver_uid
                    }
                )
            end
        end)

        if ok then
            write_log(
                logger,
                "info",
                "OZEL_CHAT_TOPLU_OK | adet=" ..
                tostring(#pending_messages)
            )
        else
            write_log(
                logger,
                "warn",
                "OZEL_CHAT_HATA | " ..
                tostring(error_message)
            )
        end

        return ok
    end

    local already_on_game_thread = false
    if type(IsInGameThread) == "function" then
        local checked, result = pcall(IsInGameThread)
        already_on_game_thread = checked and result == true
    end

    if already_on_game_thread then
        return send_on_game_thread()
    end

    if type(ExecuteInGameThread) == "function" then
        local queued, queue_error = pcall(function()
            ExecuteInGameThread(send_on_game_thread)
        end)
        if not queued then
            write_log(
                logger,
                "warn",
                "OZEL_CHAT_HATA | oyun thread kuyrugu | " ..
                tostring(queue_error)
            )
            return false
        end

        write_log(
            logger,
            "info",
            "OZEL_CHAT_TOPLU_KUYRUGA_ALINDI | adet=" ..
            tostring(#pending_messages)
        )

        return true
    end

    return send_on_game_thread()
end


function PrivateMessenger.send(
    world_context,
    player,
    message,
    logger
)
    return PrivateMessenger.send_many(
        world_context,
        player,
        { message },
        logger
    )
end

return PrivateMessenger
