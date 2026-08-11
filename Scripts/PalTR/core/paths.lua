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
        relations = join(root, "diplomacy_relations.tsv"),
        events = join(root, "diplomacy_events.tsv"),
        responses = join(root, "command_responses.tsv"),
        damage = join(root, "passive_damage_events.tsv"),
        structure = join(root, "structure_damage_probe.tsv"),
        latest_status = join(root, "latest_status.txt"),
        health = join(root, "health.tsv")
    }
end

return Paths
