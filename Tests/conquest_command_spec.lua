package.path = table.concat({
    "Scripts/?.lua",
    "Scripts/?/init.lua",
    package.path
}, ";")

local Parser = require("PalTR.domain.command_parser")
local CommandService = require("PalTR.services.command_service")
local Result = require("PalTR.core.result")
local States = require("PalTR.domain.conquest_states")

local function equal(actual, expected, message)
    if actual ~= expected then
        error(message .. ": expected=" .. tostring(expected) ..
            " actual=" .. tostring(actual))
    end
end

equal(Parser.parse("!baskent").value.action, "REGISTER_CAPITAL", "capital parse")
equal(Parser.parse("!karakol").value.action, "REGISTER_OUTPOST", "outpost parse")
equal(Parser.parse("!fetihdurum").value.action, "CONQUEST_STATUS", "status parse")

local registry = { guilds = {}, runtime_players = {} }
local conquest = {
    config = {
        max_outposts_per_clan = 10,
        game_role_map = { [1] = "LEADER", [2] = "DEPUTY_LEADER" },
        operator_roles = { LEADER = true, DEPUTY_LEADER = true }
    },
    nodes = {},
    registered = nil
}

function conquest:get_node(node_id) return self.nodes[node_id] end
function conquest:nearest_controlled_node()
    return { node_id = "CAPITAL_A" }, 10
end
function conquest:register_node(request)
    self.registered = request
    self.nodes[request.node_id] = request
    return Result.ok(request)
end
function conquest:nodes_for_controller(guild_key)
    local result = {}
    for _, node in pairs(self.nodes) do
        if node.guild_key == guild_key then table.insert(result, node) end
    end
    return result
end

local nearby = {
    current = {
        node_id = "BASE_A",
        flag_reference = "PALBOX_A",
        guild_key = "A",
        name = "Alpha",
        x = 10, y = 20, z = 30
    }
}
function nearby:nearest_owned() return Result.ok(self.current) end

local service = CommandService.new(
    { responses = "conquest_command_responses.tsv" },
    registry,
    {},
    {},
    {},
    conquest,
    nearby
)

local leader = { guild_key = "A", role = 1, is_master = true }
local ok, message = service:_register_nearest_base_camp(
    leader,
    States.NODE_TYPE.CAPITAL
)
equal(ok, true, "leader registers capital")
equal(conquest.registered.actor_role, "LEADER", "leader role mapped")
equal(conquest.registered.flag_reference, "PALBOX_A", "Pal Box reference used")
equal(message, "Baskent kaydedildi: Alpha", "capital response")

nearby.current = {
    node_id = "BASE_B",
    flag_reference = "PALBOX_B",
    guild_key = "A",
    name = "Bravo",
    x = 100, y = 0, z = 0
}
local deputy = { guild_key = "A", role = 2, is_master = false }
ok = service:_register_nearest_base_camp(
    deputy,
    States.NODE_TYPE.OUTPOST
)
equal(ok, true, "deputy registers outpost")
equal(conquest.registered.actor_role, "DEPUTY_LEADER", "deputy role mapped")
equal(conquest.registered.parent_node_id, "CAPITAL_A", "nearest parent used")

nearby.current.node_id = "BASE_C"
local member = { guild_key = "A", role = 3, is_master = false }
ok, message = service:_register_nearest_base_camp(
    member,
    States.NODE_TYPE.OUTPOST
)
equal(ok, false, "member cannot register")
equal(
    message,
    "Bu komut icin lider veya yardimci lider yetkisi gerekli",
    "member denied"
)

local status_ok, status = service:_conquest_status_message(leader)
equal(status_ok, true, "status available")
equal(status, "Fetih: Baskent=1 | Karakol=1/10", "status counts nodes")

os.remove("conquest_command_responses.tsv")
print("conquest_command_spec: ok")
