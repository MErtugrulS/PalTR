package.path = table.concat({
    "Scripts/?.lua",
    "Scripts/?/init.lua",
    package.path
}, ";")

local Repository = require("PalTR.storage.conquest_repository")

local function equal(actual, expected, message)
    if actual ~= expected then
        error(message .. ": expected=" .. tostring(expected) ..
            " actual=" .. tostring(actual))
    end
end

local prefix = os.tmpname() .. "_paltr_conquest"
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
    updated_at = 100
}

equal(repository:save_nodes({ NODE_A = node }).ok, true, "nodes saved")
local loaded_node = repository:load_nodes().NODE_A
equal(loaded_node.current_controller, "GUILD_A", "node controller restored")
equal(loaded_node.x, 10, "node location restored")

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
    updated_at = 200
}

equal(
    repository:save_occupations({ NODE_B = occupation }).ok,
    true,
    "occupation saved"
)
local loaded_occupation = repository:load_occupations().NODE_B
equal(loaded_occupation.remaining_seconds, 800, "occupation timer restored")
equal(loaded_occupation.previous_state, "OCCUPIED", "pause state restored")

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

for _, path in pairs(paths) do
    os.remove(path)
end

print("conquest_repository_spec: ok")
