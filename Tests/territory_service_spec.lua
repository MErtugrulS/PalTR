package.path = table.concat({
    "Scripts/?.lua",
    "Scripts/?/init.lua",
    package.path
}, ";")

local Territory = require("PalTR.services.territory_service")
local TempPath = dofile("Tests/support/temp_path.lua")

local function equal(actual, expected, message)
    if actual ~= expected then
        error(message .. ": expected=" .. tostring(expected) ..
            " actual=" .. tostring(actual))
    end
end

local path = TempPath.prefix("paltr_territory") .. ".tsv"
local boundary_path = TempPath.prefix("paltr_territory_boundaries") .. ".tsv"
local player = {
    key = "PLAYER", online = true, controller = {}, pawn = {},
    location = { x = 0, y = 0, z = 0 }
}
local registry = {
    guilds = {
        A = { name = "NWO" },
        B = { name = "Exceed" }
    },
    runtime_players = { PLAYER = player }
}
local conquest = { nodes = {
    CAPITAL = {
        node_id = "CAPITAL", node_type = "CAPITAL",
        current_controller = "A", x = 0, y = 0, z = 0,
        state = "PROTECTED", flag_state = "BOUND", created_at = 1
    },
    OUTPOST = {
        node_id = "OUTPOST", node_type = "OUTPOST",
        current_controller = "B", x = 500, y = 0, z = 0,
        state = "CONQUERED", flag_state = "MISSING", created_at = 2,
        display_name = "Exceed Kuzey Karakolu",
        territory_radius_meters = 125
    }
} }
local messages = {}
local service = Territory.new(
    {
        territory_snapshot = path,
        territory_boundaries = boundary_path
    },
    { conquest = {
        territory_default_capital_radius_meters = 250,
        territory_default_outpost_radius_meters = 150,
        territory_exit_hysteresis_meters = 20,
        territory_border_irregularity = 0.06,
        territory_boundary_sample_meters = 8,
        territory_boundary_max_cells = 50000
    } },
    registry,
    conquest,
    nil,
    {
        position_reader = function(value) return value.location end,
        announce = function(_, message) table.insert(messages, message) end
    }
)

equal(service:refresh().ok, true, "first refresh succeeds")
equal(messages[1], "NWO Baskenti bolgesine girdiniz.", "capital entry announced")
equal(#messages, 1, "entry announced once")
equal(service:refresh().ok, true, "unchanged refresh succeeds")
equal(#messages, 1, "lingering does not repeat")

player.location = { x = 500, y = 0, z = 0 }
service:refresh()
equal(messages[2], "Exceed Kuzey Karakolu bolgesine girdiniz.",
    "manual outpost name announced")

local snapshot_file = assert(io.open(path, "r"))
local snapshot = snapshot_file:read("*a")
snapshot_file:close()
equal(snapshot:find("Exceed Kuzey Karakolu", 1, true) ~= nil, true,
    "snapshot includes display name")
equal(snapshot:find("\t125\t", 1, true) ~= nil, true,
    "snapshot includes per-node radius")
equal(snapshot:find("\tMISSING", 1, true) ~= nil, true,
    "missing flag territory remains visible")

local boundary_file = assert(io.open(boundary_path, "r"))
local boundaries = boundary_file:read("*a")
boundary_file:close()
equal(boundaries:find("A::001", 1, true) ~= nil, true,
    "boundary snapshot includes stable component id")
equal(boundaries:find(";", 1, true) ~= nil, true,
    "boundary snapshot includes polygon points")

equal(os.remove(path), true, "snapshot removed for recreation test")
equal(service:refresh().ok, true, "missing unchanged snapshot recreated")
local recreated = io.open(path, "r")
equal(recreated ~= nil, true, "recreated snapshot exists")
if recreated then recreated:close() end

player.online = false
service:refresh()
equal(service.player_nodes.PLAYER, nil, "offline player state cleared")
os.remove(path)
os.remove(boundary_path)

print("territory_service_spec: ok")
