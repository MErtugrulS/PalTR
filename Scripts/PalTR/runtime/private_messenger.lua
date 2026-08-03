local PrivateMessenger = {}

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

local function controller_is_invalid(controller)
    if controller == nil then
        return true
    end

    local checked, valid = pcall(function()
        return controller:IsValid()
    end)

    if checked then
        return valid ~= true
    end

    return false
end

function PrivateMessenger.send(
    controller,
    message,
    logger
)
    local text = tostring(message or "")

    if controller_is_invalid(controller) then
        write_log(
            logger,
            "warn",
            "OZEL_MESAJ_DEBUG_RPC_HATA | controller gecersiz"
        )

        return false
    end

    if text == "" then
        write_log(
            logger,
            "warn",
            "OZEL_MESAJ_DEBUG_RPC_HATA | mesaj bos"
        )

        return false
    end

    local sent, error_message = pcall(function()
        controller:Debug_ReceiveCheatCommand_ToClient(
            text
        )
    end)

    if not sent then
        write_log(
            logger,
            "warn",
            "OZEL_MESAJ_DEBUG_RPC_HATA | " ..
            tostring(error_message)
        )

        return false
    end

    write_log(
        logger,
        "info",
        "OZEL_MESAJ_DEBUG_RPC_OK | " .. text
    )

    return true
end

return PrivateMessenger