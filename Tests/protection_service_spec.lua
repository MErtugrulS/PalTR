package.path = table.concat({
    "Scripts/?.lua",
    "Scripts/?/init.lua",
    package.path
}, ";")

local Protection = require(
    "PalTR.services.protection_service"
)
local TempPath = dofile("Tests/support/temp_path.lua")

local function equal(actual, expected, message)
    if actual ~= expected then
        error(message .. ": expected=" ..
            tostring(expected) ..
            " actual=" .. tostring(actual))
    end
end

local config = {
    offline_grace_seconds = 600,
    combat_lock_seconds = 1200
}

local online = Protection.evaluate(
    2000, 1, 1900, 0, config
)
equal(online.protected, false, "online guild")
equal(online.reason, "ONLINE", "online reason")

local grace = Protection.evaluate(
    2100, 0, 2000, 0, config
)
equal(grace.protected, false, "offline grace")
equal(grace.protected_at, 2600, "grace deadline")

local combat = Protection.evaluate(
    2300, 0, 1000, 2200, config
)
equal(combat.protected, false, "combat lock")
equal(combat.protected_at, 3400, "combat deadline")

local protected = Protection.evaluate(
    3400, 0, 1000, 2200, config
)
equal(protected.protected, true, "offline protected")
equal(protected.reason, "OFFLINE_PROTECTED", "protected reason")

local prefix = TempPath.prefix("paltr_protection")
local snapshot_path = prefix .. "_snapshot.tsv"
local activity_path = prefix .. "_activity.tsv"
local service = Protection.new(
    {
        protection = snapshot_path,
        protection_activity = activity_path
    },
    { protection = config },
    {
        guilds = { GUILD_A = { key = "GUILD_A" } },
        players = {
            PLAYER_A = {
                guild_key = "GUILD_A",
                last_seen = 1000
            }
        },
        runtime_players = {}
    },
    { error = function() end }
)

equal(service:refresh(3400), true, "protection snapshot written")
equal(os.remove(snapshot_path), true, "protection snapshot removed")
equal(service:refresh(3400), true, "missing unchanged snapshot recreated")
local recreated = io.open(snapshot_path, "r")
equal(recreated ~= nil, true, "recreated protection snapshot exists")
if recreated then recreated:close() end
os.remove(snapshot_path)
os.remove(activity_path)

print("protection_service_spec: ok")
