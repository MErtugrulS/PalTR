return {
    data_root = "C:/PalTR-Dev/Data",

    runtime = {
        scheduler_interval_ms = 5000,
        guild_scan_seconds = 60,
        player_validity_poll = true,
        -- Faz-04 oyuncu hasar politikasini uygular.
        enable_damage_enforcement = true
    },

    diplomacy = {
        war_preparation_minutes = 30,

        -- Ateskes bozulduktan sonra fetih hasarinin yeniden acilma gecikmesi.
        ceasefire_rearm_seconds = 1800,

        -- Diplomasi teklifleri 24 saat cevap bekler.
        proposal_expiry_hours = 24
    },

    protection = {
        -- Son klan uyesi ayrildiktan sonra offline koruma gecikmesi.
        offline_grace_seconds = 600,

        -- Son dis saldiridan sonra offline koruma icin gereken sakin sure.
        combat_lock_seconds = 1200
    },

    conquest = {
        max_outposts_per_clan = 10,
        world_units_per_meter = 100,
        flag_interaction_radius_meters = 20,
        flag_rebind_radius_meters = 30,
        conquest_flag_actor_class_tokens = {
            "BP_BuildObject_Believer_Flag_C",
            "BP_BuildObject_DarkIsland_Flag_C",
            "BP_BuildObject_FireCult_Flag_C",
            "BP_BuildObject_Hunter_Flag_C",
            "BP_BuildObject_Ninja_Flag_C",
            "BP_BuildObject_Police_Flag_C",
            "BP_BuildObject_Scientist_Flag_C",
            "BP_BuildObject_SkyIsland_Flag_C"
        },
        flag_candidate_actor_class_tokens = {
            "BP_BuildObject_Believer_Flag_C",
            "BP_BuildObject_DarkIsland_Flag_C",
            "BP_BuildObject_FireCult_Flag_C",
            "BP_BuildObject_Hunter_Flag_C",
            "BP_BuildObject_Ninja_Flag_C",
            "BP_BuildObject_Police_Flag_C",
            "BP_BuildObject_Scientist_Flag_C",
            "BP_BuildObject_SkyIsland_Flag_C"
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
        counter_attack_hold_seconds = 600,
        counter_attack_flag_radius_meters = 30,
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
        },
        loot_table = {
            {
                item_id = "PalSphere_Ancient_2",
                item_selector = "CAPTURE_SPHERE_LEVEL:Ancient_2",
                enabled = true,
                weight = 1,
                min_quantity = 1,
                max_quantity = 1,
                tier = "ANCIENT_2",
                category = "PAL_SPHERE"
            }
        }
    }
}
