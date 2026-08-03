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

    -- IsValid wrapper'i bulunamazsa controller chat hook'undan
    -- geldigi icin cagriyi pcall korumasinda deniyoruz.
    return false
end

local function create_message_key()
    local fname_ok, fname_value = pcall(function()
        return FName("PalTR_PrivateProbe")
    end)

    if fname_ok then
        return fname_value
    end

    local helpers_ok, helpers_value = pcall(function()
        return UEHelpers.FindOrAddFName(
            "PalTR_PrivateProbe"
        )
    end)

    if helpers_ok then
        return helpers_value
    end

    error(
        "FName olusturulamadi | FName=" ..
        tostring(fname_value) ..
        " | UEHelpers=" ..
        tostring(helpers_value)
    )
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
            "OZEL_MESAJ_PROBE_HATA | controller gecersiz"
        )

        return false
    end

    if text == "" then
        write_log(
            logger,
            "warn",
            "OZEL_MESAJ_PROBE_HATA | mesaj bos"
        )

        return false
    end

    local sent, error_message = pcall(function()
        local message_key = create_message_key()

        controller:SendScreenLogToClient(
            text,
            {
                R = 0.20,
                G = 0.85,
                B = 1.00,
                A = 1.00
            },
            5.0,
            message_key
        )
    end)

    if not sent then
        write_log(
            logger,
            "warn",
            "OZEL_MESAJ_PROBE_HATA | " ..
            tostring(error_message)
        )

        return false
    end

    write_log(
        logger,
        "info",
        "OZEL_MESAJ_PROBE_OK | " .. text
    )

    return true
end

return PrivateMessenger