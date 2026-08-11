local Paths = {}

local function join(left, right)
    return tostring(left):gsub("[\\/]+$", "") .. "/" ..
        tostring(right):gsub("^[\\/]+", "")
end

function Paths.new(root)
    return {
        root = root,
        guilds = join(root, "guild_registry.tsv"),
        players = join(root, "player_registry.tsv"),
        online = join(root, "online_players.tsv"),
        protection = join(root, "guild_protection.tsv"),
        protection_activity = join(root, "guild_combat_activity.tsv"),
        conquest_nodes = join(root, "conquest_nodes.tsv"),
        conquest_edges = join(root, "conquest_edges.tsv"),
        conquest_campaigns = join(root, "conquest_campaigns.tsv"),
        conquest_occupations = join(root, "conquest_occupations.tsv"),
        conquest_loot = join(root, "conquest_loot_manifests.tsv"),
        conquest_loot_items = join(root, "conquest_loot_items.tsv"),
        conquest_events = join(root, "conquest_events.tsv"),
        conquest_damage_policy = join(root, "conquest_damage_policy.tsv"),
        relations = join(root, "diplomacy_relations.tsv"),
        events = join(root, "diplomacy_events.tsv"),
        responses = join(root, "command_responses.tsv"),
        damage = join(root, "passive_damage_events.tsv"),
        latest_status = join(root, "latest_status.txt"),
        health = join(root, "health.tsv")
    }
end

return Paths
