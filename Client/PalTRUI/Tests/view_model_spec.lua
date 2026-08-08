local PanelState = require("panel_state")

local function equal(actual, expected, label)
    if actual ~= expected then
        error(string.format(
            "%s | expected=%s actual=%s",
            label,
            tostring(expected),
            tostring(actual)
        ))
    end
end

local function snapshot(relations)
    return {
        schema_version = 1,
        generated_at = 12345,
        player = {
            name = "Ada",
            guild_key = "guild-own",
            role = 1,
            is_master = true
        },
        guild = {
            key = "guild-own",
            name = "Anka"
        },
        members = {
            {
                key = "player-1",
                name = "Ada",
                role = 1,
                is_master = true,
                online = true
            },
            {
                key = "player-2",
                name = "Bora",
                role = 0,
                is_master = false,
                online = false
            }
        },
        relations = relations or {}
    }
end

local relations = {
    {
        guild_key = "guild-alliance",
        guild_name = "Müttefikler",
        state = "ALLIANCE",
        previous_state = "NEUTRAL",
        proposal_direction = "none",
        can_manage = true,
        action_reason = "",
        actions = {
            { id = "RETURN_NEUTRAL", label = "İttifaktan Ayrıl" }
        }
    },
    {
        guild_key = "guild-war",
        guild_name = "Rakipler",
        state = "WAR",
        previous_state = "WAR_PENDING",
        proposal_direction = "none",
        can_manage = true,
        action_reason = "",
        actions = {
            { id = "CEASEFIRE", label = "Ateşkes Teklif Et" },
            { id = "PEACE", label = "Barış Teklif Et" }
        }
    }
}

local panel = PanelState.new()
equal(panel.view_model.active_tab, "CLAN", "default tab")
equal(panel.view_model.views.CHAT.available, false, "chat transport")

equal(panel:apply_snapshot(snapshot(relations)), true, "valid snapshot")
equal(panel.selected_guild, "guild-alliance", "default relation selection")
equal(panel.view_model.views.CLAN.member_count, 2, "member count")
equal(panel.view_model.views.CLAN.online_count, 1, "online count")
equal(#panel.view_model.views.DIPLOMACY.relations, 2, "diplomacy count")
equal(#panel.view_model.views.ALLIANCE.relations, 1, "alliance filter")
equal(
    panel.view_model.views.DIPLOMACY.relations[2].actions[1].id,
    "CEASEFIRE",
    "server action is preserved"
)
equal(
    #panel.view_model.views.DIPLOMACY.relations[2].actions,
    2,
    "client does not infer actions"
)

panel:set_tab("DIPLOMACY")
equal(panel.view_model.content, panel.view_model.views.DIPLOMACY, "active content")

panel:select_guild("guild-war")
equal(
    panel.view_model.views.DIPLOMACY.selected_relation.guild.key,
    "guild-war",
    "selected relation"
)

panel:apply_snapshot(snapshot({ relations[1] }))
equal(panel.selected_guild, "guild-alliance", "stale selection is replaced")

local invalid = snapshot()
invalid.members = "invalid"
equal(panel:apply_snapshot(invalid), false, "invalid snapshot shape")
equal(panel.view_model.error, "Sunucu UI veri sürümü uyumsuz.", "contract error")

local malformed_relation = snapshot({ "invalid" })
equal(panel:apply_snapshot(malformed_relation), true, "malformed relation is isolated")
equal(#panel.view_model.views.DIPLOMACY.relations, 1, "relation slot is preserved")
equal(
    panel.view_model.views.DIPLOMACY.relations[1].guild.key,
    "",
    "malformed relation has safe defaults"
)

print("PALTR_UI_VIEW_MODEL_TEST_OK")
