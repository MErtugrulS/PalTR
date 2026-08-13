package.path = table.concat({
    "Scripts/?.lua",
    "Scripts/?/init.lua",
    package.path
}, ";")

local Repository = require("PalTR.storage.conquest_repository")
local TempPath = dofile("Tests/support/temp_path.lua")

local function equal(actual, expected, message)
    if actual ~= expected then
        error(message .. ": expected=" .. tostring(expected) ..
            " actual=" .. tostring(actual))
    end
end

local prefix = TempPath.prefix("paltr_conquest")
local paths = {
    conquest_nodes = prefix .. "_nodes.tsv",
    conquest_edges = prefix .. "_edges.tsv",
    conquest_campaigns = prefix .. "_campaigns.tsv",
    conquest_occupations = prefix .. "_occupations.tsv",
    conquest_loot = prefix .. "_loot.tsv",
    conquest_loot_items = prefix .. "_loot_items.tsv"
}

local repository = Repository.new(paths)

local node = {
    key = "NODE_A",
    node_id = "NODE_A",
    guild_key = "GUILD_A",
    node_type = "CAPITAL",
    flag_reference = "FlagA",
    x = 10,
    y = 20,
    z = 30,
    parent_node_id = "",
    state = "PROTECTED",
    original_owner = "GUILD_A",
    current_controller = "GUILD_A",
    created_at = 100,
    updated_at = 100,
    flag_state = "BOUND",
    legacy_flag_reference = "",
    display_name = "NWO Kuzey Karakolu",
    territory_radius_meters = 175
}

equal(repository:save_nodes({ NODE_A = node }).ok, true, "nodes saved")
local loaded_node = repository:load_nodes().NODE_A
equal(loaded_node.current_controller, "GUILD_A", "node controller restored")
equal(loaded_node.x, 10, "node location restored")
equal(loaded_node.flag_state, "BOUND", "flag state restored")
equal(loaded_node.legacy_flag_reference, "", "no legacy flag restored")
equal(loaded_node.display_name, "NWO Kuzey Karakolu", "display name restored")
equal(loaded_node.territory_radius_meters, 175, "territory radius restored")

local legacy = assert(io.open(paths.conquest_nodes, "w"))
legacy:write(
    "node_id\tguild_key\tnode_type\tflag_reference\tlocation_x\tlocation_y\tlocation_z\tparent_node_id\tstate\toriginal_owner\tcurrent_controller\tcreated_at\tupdated_at\n" ..
    "LEGACY\tGUILD_B\tOUTPOST\tOLD_FLAG\t1\t2\t3\t\tCONQUERED\tGUILD_B\tGUILD_A\t1\t2\n"
)
legacy:close()
equal(
    repository:load_nodes().LEGACY.flag_state,
    "MISSING",
    "legacy transferred node requires replacement flag"
)
equal(
    repository:load_nodes().LEGACY.legacy_flag_reference,
    "OLD_FLAG",
    "legacy transferred node keeps cleanup reference"
)
equal(repository:load_nodes().LEGACY.display_name, "", "legacy name defaults empty")
equal(repository:load_nodes().LEGACY.territory_radius_meters, 0, "legacy radius defaults")

local edge = {
    edge_id = "NODE_A::NODE_B",
    node_a = "NODE_A",
    node_b = "NODE_B",
    created_at = 100
}

equal(
    repository:save_edges({ [edge.edge_id] = edge }).ok,
    true,
    "edge saved"
)
equal(
    repository:load_edges()[edge.edge_id].node_b,
    "NODE_B",
    "edge restored"
)

local campaign = {
    campaign_id = "WAR::GUILD_A",
    war_id = "WAR",
    attacker_guild = "GUILD_A",
    defender_guild = "GUILD_B",
    state = "ACTIVE",
    active_target_node_id = "NODE_B",
    siege_camp_reference = "CampA",
    siege_x = 100,
    siege_y = 200,
    siege_z = 0,
    rearm_until = 0,
    previous_relation_state = "WAR",
    created_at = 100,
    updated_at = 100
}

equal(
    repository:save_campaigns({ [campaign.campaign_id] = campaign }).ok,
    true,
    "campaign saved"
)
local loaded_campaign = repository:load_campaigns()[campaign.campaign_id]
equal(loaded_campaign.active_target_node_id, "NODE_B", "target restored")
equal(loaded_campaign.siege_y, 200, "siege location restored")

local occupation = {
    node_id = "NODE_B",
    original_owner = "GUILD_B",
    occupying_guild = "GUILD_A",
    war_id = "WAR",
    state = "PAUSED",
    previous_state = "OCCUPIED",
    occupation_started_at = 100,
    remaining_seconds = 800,
    last_resumed_at = 0,
    loot_manifest_id = "LOOT_B",
    frontline_state = "PAUSED",
    updated_at = 200,
    counter_flag_reference = "COUNTER_FLAG",
    counter_remaining_seconds = 60,
    counter_last_resumed_at = 0,
    counter_flag_x = 11,
    counter_flag_y = 22,
    counter_flag_z = 33
}

equal(
    repository:save_occupations({ NODE_B = occupation }).ok,
    true,
    "occupation saved"
)
local loaded_occupation = repository:load_occupations().NODE_B
equal(loaded_occupation.remaining_seconds, 800, "occupation timer restored")
equal(loaded_occupation.previous_state, "OCCUPIED", "pause state restored")
equal(loaded_occupation.counter_flag_reference, "COUNTER_FLAG", "counter flag restored")
equal(loaded_occupation.counter_remaining_seconds, 60, "counter timer restored")
equal(loaded_occupation.counter_flag_y, 22, "counter location restored")

local legacy_occupation = assert(io.open(paths.conquest_occupations, "w"))
legacy_occupation:write(
    "node_id\toriginal_owner\toccupying_guild\twar_id\tstate\tprevious_state\toccupation_started_at\tremaining_seconds\tlast_resumed_at\tloot_manifest_id\tfrontline_state\tupdated_at\n" ..
    "LEGACY_COUNTER\tGUILD_B\tGUILD_A\tWAR\tCOUNTER_ATTACK\t\t100\t800\t100\tLOOT_B\tCOUNTER_ATTACK\t200\n"
)
legacy_occupation:close()
equal(
    repository:load_occupations().LEGACY_COUNTER.state,
    "OCCUPIED",
    "legacy counter attack without physical flag fails closed"
)

local manifest = {
    manifest_id = "LOOT_B",
    node_id = "NODE_B",
    war_id = "WAR",
    owner_guild = "GUILD_A",
    state = "CREATED",
    created_at = 200,
    extracted_at = 0
}
local loot_item = {
    item_key = "LOOT_B::1",
    manifest_id = "LOOT_B",
    item_id = "",
    item_selector = "CAPTURE_SPHERE_LEVEL:Ancient_2",
    quantity = 1,
    tier = "ANCIENT_2",
    category = "PAL_SPHERE"
}

equal(
    repository:save_loot_manifests({ LOOT_B = manifest }).ok,
    true,
    "loot manifest saved"
)
equal(
    repository:save_loot_items({ [loot_item.item_key] = loot_item }).ok,
    true,
    "loot item saved"
)
equal(
    repository:load_loot_manifests().LOOT_B.state,
    "CREATED",
    "loot manifest restored"
)
equal(
    repository:load_loot_items()[loot_item.item_key].item_selector,
    "CAPTURE_SPHERE_LEVEL:Ancient_2",
    "loot selector restored"
)

local invalid = assert(io.open(paths.conquest_nodes, "w"))
invalid:write("wrong_header\n")
invalid:close()
local invalid_ok, invalid_error = pcall(function()
    repository:load_nodes()
end)
equal(invalid_ok, false, "invalid conquest header stops loading")
equal(
    tostring(invalid_error):find("Gecersiz fetih dosyasi basligi", 1, true)
        ~= nil,
    true,
    "invalid conquest header reports useful error"
)

for _, path in pairs(paths) do
    os.remove(path)
end

print("conquest_repository_spec: ok")
