package.path = table.concat({
    "Scripts/?.lua",
    "Scripts/?/init.lua",
    package.path
}, ";")

local Protection = require(
    "PalTR.services.protection_service"
)

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

print("protection_service_spec: ok")
