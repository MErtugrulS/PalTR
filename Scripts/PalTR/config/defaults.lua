return {
    data_root = "C:/PalTR-Dev/Data",

    runtime = {
        scheduler_interval_ms = 5000,
        guild_scan_seconds = 60,
        player_validity_poll = true,
        enable_structure_damage_probe = true,

        -- Gercek hasar engelleme halen kapali.
        enable_damage_enforcement = false
    },

    diplomacy = {
        war_preparation_minutes = 30,
        war_duration_hours = 24,
        proposal_expiry_hours = 24
    },

    protection = {
        offline_grace_minutes = 15,
        minimum_online_defenders = 1,
        block_friendly_fire = true,
        block_non_war_damage = true
    }
}
