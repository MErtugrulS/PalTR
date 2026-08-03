return {
    data_root = "C:/PalTR-Dev/Data",

    runtime = {
        scheduler_interval_ms = 5000,
        guild_scan_seconds = 60,
        player_validity_poll = true,
        enable_structure_damage_probe = true,

        -- Faz-03 yalnizca diplomasi durumlarini test eder.
        enable_damage_enforcement = false
    },

    diplomacy = {
        -- Runtime savas testi icin gecici olarak 2 dakika.
        -- Testten sonra 30 dakikaya cikarilacak.
        war_preparation_minutes = 2,

        -- Ateskes kabul edildikten sonra 12 saat surer.
        ceasefire_duration_hours = 12,

        -- Diplomasi teklifleri 24 saat cevap bekler.
        proposal_expiry_hours = 24
    },

    protection = {
        offline_grace_minutes = 10,
        minimum_online_defenders = 2,
        block_friendly_fire = true,
        block_non_war_damage = true
    }
}