return {
    data_root = "C:/PalTR-Dev/Data",

    runtime = {
        scheduler_interval_ms = 5000,
        guild_scan_seconds = 60,
        player_validity_poll = true,
        enable_structure_damage_probe = true,

        -- Faz-03 yalnizca diplomasi durumunu test eder.
        -- Gercek oyuncu/yapi hasar engelleme halen kapali.
        enable_damage_enforcement = false
    },

    diplomacy = {
        -- Runtime testi gecince 30 dakikaya cikacak.
        war_preparation_minutes = 2,
        proposal_expiry_hours = 24
    },

    protection = {
        -- Sonraki hasar/koruma fazi icin kilitlenen kurallar.
        offline_grace_minutes = 10,
        minimum_online_defenders = 2,
        block_friendly_fire = true,
        block_non_war_damage = true
    }
}