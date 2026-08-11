return {
    diplomacy = {
        war_preparation_minutes = 30,
        ceasefire_rearm_seconds = 1800
    },

    runtime = {
        enable_damage_enforcement = true
    },

    protection = {
        offline_grace_seconds = 600,
        combat_lock_seconds = 1200
    },

    conquest = {
        max_outposts_per_clan = 10,
        world_units_per_meter = 100,
        flag_interaction_radius_meters = 20,
        conquest_flag_actor_class_tokens = {},
        flag_candidate_actor_class_tokens = {
            "BP_BuildObject_Signboard"
        },
        siege_camp_interaction_radius_meters = 20,
        siege_camp_actor_class_tokens = {
            "BP_BuildObject_WorkBench_C"
        },
        raid_timezone = "Europe/Istanbul",
        raid_utc_offset_minutes = 180,
        raid_window_start = "20:00",
        raid_window_end = "00:00",
        occupation_hold_seconds = 86400,
        outpost_link_max_distance_meters = 1500,
        conquest_zone_radius_meters = 150,
        siege_min_distance_from_target_meters = 250,
        siege_max_distance_from_target_meters = 600,
        siege_min_distance_from_other_enemy_node_meters = 300,
        peace_occupation_resolution = "OCCUPIER_WINS",
        capital_defeat_resolution = "TRANSFER_ALL_NODES",
        operator_roles = {
            LEADER = true,
            DEPUTY_LEADER = true,
            COMMANDER = true
        },
        game_role_map = {
            [1] = "LEADER",
            [2] = "DEPUTY_LEADER"
        }
    }
}
