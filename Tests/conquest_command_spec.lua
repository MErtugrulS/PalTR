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
equal(Parser.parse("!fetih B").value.action, "START_CONQUEST", "conquest parse")
equal(
    Parser.parse("!kusatmakampi B").value.action,
    "ESTABLISH_SIEGE",
    "siege parse"
)
equal(
    Parser.parse("!fetihedef B").value.action,
    "SELECT_CONQUEST_TARGET",
    "next target parse"
)
equal(Parser.parse("!bayrakaday").value.action, "FLAG_CANDIDATE", "candidate parse")
equal(
    Parser.parse("!fetihbayragi").value.action,
    "REBIND_CONQUERED_FLAG",
    "captured flag parse"
)

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
function conquest:rebind_conquered_flag(request)
    self.rebound = request
    return Result.ok({ node_id = "CAPTURED_B" })
end
function conquest:nodes_for_controller(guild_key)
    local result = {}
    for _, node in pairs(self.nodes) do
        if node.guild_key == guild_key then table.insert(result, node) end
    end
    return result
end
function conquest:status_for_guild(guild_key)
    local capital_count = 0
    local outpost_count = 0
    for _, node in pairs(self.nodes) do
        if node.guild_key == guild_key then
            if node.node_type == States.NODE_TYPE.CAPITAL then
                capital_count = capital_count + 1
            elseif node.node_type == States.NODE_TYPE.OUTPOST then
                outpost_count = outpost_count + 1
            end
        end
    end
    return {
        capital_count = capital_count,
        outpost_count = outpost_count,
        missing_flag_count = 0,
        campaigns = {},
        occupations = {}
    }
end
function conquest:start_campaign(attacker, defender, role)
    self.started = { attacker = attacker, defender = defender, role = role }
    return Result.ok({ campaign_id = "WAR::A" })
end
function conquest:active_campaign()
    return { campaign_id = "WAR::A" }
end
function conquest:nearest_initial_target()
    return { node_id = "OUTPOST_B" }, 300
end
function conquest:establish_siege(campaign_id, role, target_id, camp)
    self.siege = {
        campaign_id = campaign_id,
        role = role,
        target_id = target_id,
        camp = camp
    }
    return Result.ok({ node_id = target_id })
end
function conquest:select_next_target(campaign_id, role)
    self.next_target = { campaign_id = campaign_id, role = role }
    return Result.ok({ node_id = "OUTPOST_B_2" })
end

local nearby = {
    current = {
        node_id = "BASE_A",
        flag_reference = "FLAG_A",
        guild_key = "A",
        name = "Alpha",
        x = 10, y = 20, z = 30
    }
}
function nearby:nearest_owned_flag() return Result.ok(self.current) end
function nearby:nearest_owned_candidate()
    return Result.ok({ actor_reference = "VerifiedFlagClass_C Instance" })
end

local build_objects = {}
function build_objects:nearest_owned_siege_camp()
    return Result.ok({
        reference = "WORKBENCH_A",
        guild_key = "A",
        x = 300, y = 0, z = 0
    })
end

local service = CommandService.new(
    { responses = "conquest_command_responses.tsv" },
    registry,
    {},
    {},
    {},
    conquest,
    nearby,
    build_objects
)

local leader = { guild_key = "A", role = 1, is_master = true }
local ok, message = service:_register_nearest_conquest_flag(
    leader,
    States.NODE_TYPE.CAPITAL
)
equal(ok, true, "leader registers capital")
equal(conquest.registered.actor_role, "LEADER", "leader role mapped")
equal(conquest.registered.flag_reference, "FLAG_A", "clan flag reference used")
equal(message, "Baskent kaydedildi: Alpha", "capital response")

nearby.current = {
    node_id = "BASE_B",
    flag_reference = "FLAG_B",
    guild_key = "A",
    name = "Bravo",
    x = 100, y = 0, z = 0
}
local deputy = { guild_key = "A", role = 2, is_master = false }
ok = service:_register_nearest_conquest_flag(
    deputy,
    States.NODE_TYPE.OUTPOST
)
equal(ok, true, "deputy registers outpost")
equal(conquest.registered.actor_role, "DEPUTY_LEADER", "deputy role mapped")
equal(conquest.registered.parent_node_id, "CAPITAL_A", "nearest parent used")

nearby.current.node_id = "BASE_C"
local member = { guild_key = "A", role = 3, is_master = false }
ok, message = service:_register_nearest_conquest_flag(
    member,
    States.NODE_TYPE.OUTPOST
)
equal(ok, false, "member cannot register")
equal(
    message,
    "Bu komut icin yetkili klan rolu gerekli",
    "member denied"
)

local status_ok, status = service:_conquest_status_message(leader)
equal(status_ok, true, "status available")
equal(status, "Fetih: Baskent=1 | Karakol=1/10", "status counts nodes")
local candidate_ok, candidate_message = service:_flag_candidate_message(leader)
equal(candidate_ok, true, "candidate command available")
equal(
    candidate_message,
    "Bayrak adayi (kayit yapilmadi): VerifiedFlagClass_C Instance",
    "candidate command is explicit"
)

ok, message = service:_start_conquest_campaign(leader, "B")
equal(ok, true, "leader starts conquest")
equal(conquest.started.defender, "B", "defender forwarded")
equal(conquest.started.role, "LEADER", "campaign role forwarded")

ok, message = service:_establish_nearest_siege(deputy, "B")
equal(ok, true, "deputy establishes siege")
equal(conquest.siege.campaign_id, "WAR::A", "active campaign used")
equal(conquest.siege.target_id, "OUTPOST_B", "nearest valid target used")
equal(conquest.siege.camp.reference, "WORKBENCH_A", "physical camp used")

ok, message = service:_select_next_conquest_target(deputy, "B")
equal(ok, true, "deputy selects deterministic next target")
equal(conquest.next_target.campaign_id, "WAR::A", "campaign forwarded")
equal(conquest.next_target.role, "DEPUTY_LEADER", "target role forwarded")
equal(message, "Yeni aktif fetih hedefi: OUTPOST_B_2", "target response")

nearby.current = {
    node_id = "NEW_FLAG",
    flag_reference = "NEW_FLAG",
    guild_key = "A",
    name = "Klan Bayragi",
    x = 15, y = 20, z = 30
}
ok, message = service:_rebind_conquered_flag(deputy)
equal(ok, true, "deputy rebinds captured flag")
equal(conquest.rebound.actor_role, "DEPUTY_LEADER", "rebind role forwarded")
equal(conquest.rebound.flag.flag_reference, "NEW_FLAG", "new flag forwarded")
equal(
    message,
    "Fethedilen karakola yeni Klan Bayragi baglandi: CAPTURED_B",
    "rebind response"
)

os.remove("conquest_command_responses.tsv")
print("conquest_command_spec: ok")
