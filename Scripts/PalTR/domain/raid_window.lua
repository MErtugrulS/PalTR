local RaidWindow = {}

local function parse(value)
    local hour, minute = tostring(value or ""):match("^(%d%d?):(%d%d)$")
    hour = tonumber(hour)
    minute = tonumber(minute)

    if not hour or not minute
        or hour < 0 or hour > 23
        or minute < 0 or minute > 59 then
        return nil
    end

    return hour * 60 + minute
end

function RaidWindow.is_open_minutes(now_minutes, start_text, end_text)
    local start_minutes = parse(start_text)
    local end_minutes = parse(end_text)
    now_minutes = tonumber(now_minutes)

    if not start_minutes or not end_minutes or not now_minutes then
        return false, "INVALID_RAID_WINDOW"
    end

    now_minutes = now_minutes % 1440

    if start_minutes == end_minutes then
        return true, "RAID_WINDOW_OPEN_ALL_DAY"
    end

    if start_minutes < end_minutes then
        return now_minutes >= start_minutes
            and now_minutes < end_minutes,
            "RAID_WINDOW"
    end

    return now_minutes >= start_minutes
        or now_minutes < end_minutes,
        "RAID_WINDOW_CROSS_MIDNIGHT"
end

function RaidWindow.is_open(now, config)
    config = config or {}
    now = tonumber(now) or os.time()

    local offset_seconds =
        (tonumber(config.raid_utc_offset_minutes) or 0) * 60
    local local_time = os.date("!*t", now + offset_seconds)
    local minutes = local_time.hour * 60 + local_time.min

    return RaidWindow.is_open_minutes(
        minutes,
        config.raid_window_start,
        config.raid_window_end
    )
end

return RaidWindow
