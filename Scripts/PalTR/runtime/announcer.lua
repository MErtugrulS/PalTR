local UE = require("PalTR.runtime.ue")

local Announcer = {}

local PAL_UTILITY_CDO = "/Script/Pal.Default__PalUtility"

local function log_info(logger, message)
    if logger ~= nil and logger.info ~= nil then
        logger:info(message)
    else
        print("[PalTR Announcer] " .. tostring(message))
    end
end

local function log_warn(logger, message)
    if logger ~= nil and logger.warn ~= nil then
        logger:warn(message)
    else
        print("[PalTR Announcer] UYARI | " .. tostring(message))
    end
end

function Announcer.send(world_context, message, logger)
    local context = UE.unwrap(world_context)
    local text = tostring(message or "")

    if context == nil then
        log_warn(logger, "DUYURU_HATA | controller/context yok")
        return false
    end

    if text == "" then
        log_warn(logger, "DUYURU_HATA | mesaj bos")
        return false
    end

    local function send_on_game_thread()
        local ok, error_message = pcall(function()
            local utility = StaticFindObject(PAL_UTILITY_CDO)

            if utility == nil then
                error("PalUtility CDO bulunamadi")
            end

            utility:SendSystemAnnounce(context, text)
        end)

        if ok then
            log_info(logger, "DUYURU_OK | " .. text)
        else
            log_warn(
                logger,
                "DUYURU_HATA | " .. tostring(error_message)
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

    return true
end

return Announcer
