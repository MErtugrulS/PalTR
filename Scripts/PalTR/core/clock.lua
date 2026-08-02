local Clock = {}

function Clock.now()
    return os.time()
end

function Clock.after_seconds(seconds)
    return Clock.now() + math.max(0, tonumber(seconds) or 0)
end

function Clock.after_minutes(minutes)
    return Clock.after_seconds((tonumber(minutes) or 0) * 60)
end

function Clock.after_hours(hours)
    return Clock.after_seconds((tonumber(hours) or 0) * 3600)
end

return Clock
