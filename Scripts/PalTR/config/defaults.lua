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

        -- Ateskes kabul edildikten sonra 12 saat surer.
        ceasefire_duration_hours = 12,

        -- Diplomasi teklifleri 24 saat cevap bekler.
        proposal_expiry_hours = 24
    },

    protection = {
        -- Son klan uyesi ayrildiktan sonra offline koruma gecikmesi.
        offline_grace_minutes = 5,

        -- Son dis saldiridan sonra offline koruma icin gereken sakin sure.
        combat_lock_minutes = 20
    }
}
