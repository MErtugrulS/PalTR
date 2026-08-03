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
    local candidates = {}

    if player ~= nil then
        table.insert(
            candidates,
            {
                name = "player.player_state",
                value = player.player_state
            }
        )

        table.insert(
            candidates,
            {
                name = "player.playerState",
                value = player.playerState
            }
        )
    end

    local controller_state =
        read_property(controller, "PlayerState")

    table.insert(
        candidates,
        {
            name = "controller.PlayerState",
            value = controller_state
        }
    )

    local getter_ok, getter_value = pcall(function()
        return controller:GetPlayerState()
    end)

    if getter_ok then
        table.insert(
            candidates,
            {
                name = "controller:GetPlayerState",
                value = getter_value
            }
        )
    end

    for _, candidate in ipairs(candidates) do
        local state = UE.unwrap(candidate.value)

        if state ~= nil then
            return state, candidate.name
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

function PrivateMessenger.send(
    world_context,
    player,
    message,
    logger
)
    local context = UE.unwrap(world_context)
    local text = tostring(message or "")

    if context == nil then
        write_log(
            logger,
            "warn",
            "OZEL_CHAT_HATA | controller/context yok"
        )

        return false
    end

    if text == "" then
        write_log(
            logger,
            "warn",
            "OZEL_CHAT_HATA | mesaj bos"
        )

        return false
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

            utility:SendSystemToPlayerChat(
                context,
                text,
                {
                    receiver_uid
                }
            )
        end)

        if ok then
            write_log(
                logger,
                "info",
                "OZEL_CHAT_OK | " .. text
            )
        else
            write_log(
                logger,
                "warn",
                "OZEL_CHAT_HATA | " ..
                tostring(error_message)
            )
        end
    end

    local function queue_on_game_thread()
        if type(ExecuteInGameThread) == "function" then
            ExecuteInGameThread(send_on_game_thread)
        else
            send_on_game_thread()
        end
    end

    if type(ExecuteWithDelay) == "function" then
        ExecuteWithDelay(150, queue_on_game_thread)
    else
        queue_on_game_thread()
    end

    write_log(
        logger,
        "info",
        "OZEL_CHAT_KUYRUGA_ALINDI"
    )

    return true
end

return PrivateMessenger