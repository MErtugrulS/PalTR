local Clock = require("PalTR.core.clock")
local FileIO = require("PalTR.storage.file_io")
local Tables = require("PalTR.core.table_utils")
local TSV = require("PalTR.storage.tsv")

local Protection = {}
Protection.__index = Protection

local function non_negative(value)
    return math.max(0, tonumber(value) or 0)
end

function Protection.evaluate(
    now,
    online_count,
    last_online_at,
    last_hostile_at,
    config
)
    now = non_negative(now)
    online_count = non_negative(online_count)
    last_online_at = non_negative(last_online_at)
    last_hostile_at = non_negative(last_hostile_at)
    config = config or {}

    if online_count > 0 then
        return {
            protected = false,
            protected_at = 0,
            reason = "ONLINE"
        }
    end

    local offline_ready_at = last_online_at
        + non_negative(config.offline_grace_minutes) * 60
    local combat_ready_at = last_hostile_at
        + non_negative(config.combat_lock_minutes) * 60
    local protected_at = math.max(
        offline_ready_at,
        combat_ready_at
    )

    if now >= protected_at then
        return {
            protected = true,
            protected_at = protected_at,
            reason = "OFFLINE_PROTECTED"
        }
    end

    return {
        protected = false,
        protected_at = protected_at,
        reason = now < offline_ready_at
            and "OFFLINE_GRACE"
            or "COMBAT_LOCK"
    }
end

function Protection.new(paths, config, registry, logger)
    return setmetatable({
        paths = paths,
        config = config.protection or {},
        registry = registry,
        logger = logger,
        last_snapshot = ""
    }, Protection)
end

function Protection:_load_activity()
    local activity = {}
    local result = FileIO.read_lines(
        self.paths.protection_activity
    )

    if not result.ok then
        return activity
    end

    for index, line in ipairs(result.value or {}) do
        if index > 1 and line ~= "" then
            local columns = TSV.decode(line)
            local guild_key = tostring(columns[1] or "")
            local timestamp = non_negative(columns[2])

            if guild_key ~= "" then
                activity[guild_key] = math.max(
                    activity[guild_key] or 0,
                    timestamp
                )
            end
        end
    end

    return activity
end

function Protection:_online_counts()
    local counts = {}

    for _, player in pairs(
        self.registry.runtime_players or {}
    ) do
        local guild_key = tostring(
            player.guild_key or ""
        )

        if player.online and guild_key ~= "" then
            counts[guild_key] =
                (counts[guild_key] or 0) + 1
        end
    end

    return counts
end

function Protection:_last_online_times()
    local timestamps = {}

    for _, player in pairs(
        self.registry.players or {}
    ) do
        local guild_key = tostring(
            player.guild_key or ""
        )

        if guild_key ~= "" then
            timestamps[guild_key] = math.max(
                timestamps[guild_key] or 0,
                non_negative(player.last_seen)
            )
        end
    end

    return timestamps
end

function Protection:refresh(now)
    now = non_negative(now or Clock.now())

    local activity = self:_load_activity()
    local online_counts = self:_online_counts()
    local last_online_times =
        self:_last_online_times()
    local lines = {
        "guild_key\tonline_count\tlast_online_at\tlast_hostile_at\tprotected_at\tprotected\treason"
    }

    for _, guild_key in ipairs(
        Tables.sorted_keys(self.registry.guilds or {})
    ) do
        local online_count =
            online_counts[guild_key] or 0
        local last_online_at =
            last_online_times[guild_key] or 0
        local last_hostile_at =
            activity[guild_key] or 0
        local state = Protection.evaluate(
            now,
            online_count,
            last_online_at,
            last_hostile_at,
            self.config
        )

        table.insert(lines, TSV.encode({
            guild_key,
            online_count,
            last_online_at,
            last_hostile_at,
            state.protected_at,
            tostring(state.protected),
            state.reason
        }))
    end

    local snapshot = table.concat(lines, "\n")
    if snapshot == self.last_snapshot then
        return true
    end

    local result = FileIO.overwrite(
        self.paths.protection,
        lines
    )

    if not result.ok then
        self.logger:error(
            "Koruma snapshot'i yazilamadi: " ..
            tostring(
                result.error
                and result.error.message
                or ""
            )
        )
        return false
    end

    self.last_snapshot = snapshot
    return true
end

return Protection
