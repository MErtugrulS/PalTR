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
    },
    {
        guild_key = "guild-neutral",
        guild_name = "Tarafsızlar",
        state = "NEUTRAL",
        previous_state = "NEUTRAL",
        proposal_direction = "none",
        can_manage = true,
        action_reason = "",
        actions = {
            { id = "DECLARE_WAR", label = "Savaş İlan Et" },
            { id = "ALLIANCE", label = "İttifak Teklif Et" }
        }
    }
}

local panel = PanelState.new()
equal(panel.view_model.active_tab, "CLAN", "default tab")
equal(panel.view_model.views.CHAT.available, false, "chat transport")
equal(panel.view_model.views.CHAT.message_count, 0, "empty chat")

equal(panel:apply_snapshot(snapshot(relations)), true, "valid snapshot")
equal(panel.selected_guild, "guild-alliance", "default relation selection")
equal(panel.view_model.views.CLAN.member_count, 2, "member count")
equal(panel.view_model.views.CLAN.online_count, 1, "online count")
equal(#panel.view_model.views.DIPLOMACY.relations, 3, "diplomacy count")
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
equal(panel.view_model.connection.ready, true, "snapshot connection ready")
equal(
    panel.view_model.connection.status_text,
    "Sunucu snapshoti hazir",
    "snapshot connection text"
)
equal(panel.view_model.views.CLAN.name_text, "Anka", "clan name text")
equal(
    panel.view_model.views.CLAN.summary_text,
    "2 uye | 1 cevrimici",
    "clan summary text"
)
equal(
    panel.view_model.views.CLAN.members_text,
    "Ada (cevrimici)\nBora",
    "clan members text"
)
equal(
    panel.view_model.views.CHAT.messages_text,
    panel.view_model.views.CHAT.empty_message,
    "empty chat presentation text"
)
equal(panel.view_model.tabs[1].control, "ClanTabButton", "clan tab control")
equal(panel.view_model.tabs[1].enabled, true, "inactive tab enabled")
equal(
    panel.view_model.tabs[2].text_control,
    "DiplomacyTabText",
    "diplomacy tab text control"
)
equal(panel.view_model.tabs[2].active, true, "diplomacy tab active")
equal(panel.view_model.tabs[2].enabled, false, "active tab disabled")
equal(panel.view_model.tabs[2].page_index, 1, "diplomacy page index")
equal(
    panel.view_model.tabs[2].display_label,
    "Diplomasi (3)",
    "diplomacy tab display label"
)

panel:select_guild("guild-neutral")
equal(
    panel.view_model.views.DIPLOMACY.list_text,
    "  Müttefikler | İttifak\n  Rakipler | Savaş\n> Tarafsızlar | Tarafsız",
    "diplomacy list text"
)
equal(
    panel.view_model.views.DIPLOMACY.title_text,
    "Tarafsızlar",
    "relation title text"
)
equal(
    panel.view_model.views.DIPLOMACY.state_text,
    "Tarafsız",
    "relation state text"
)
local action_controls = panel.view_model.views.DIPLOMACY.action_controls
equal(action_controls.WarRequestButton.enabled, true, "war action enabled")
equal(
    action_controls.WarRequestButton.action_id,
    "DECLARE_WAR",
    "war action identity"
)
equal(
    action_controls.AllianceRequestButton.enabled,
    true,
    "alliance action enabled"
)
equal(action_controls.AcceptButton.enabled, false, "missing action disabled")
equal(
    action_controls.AcceptButton.reason,
    "Aksiyon güncel snapshotta sunulmuyor.",
    "disabled action reason"
)

panel:select_guild("guild-war")
equal(
    panel.view_model.views.DIPLOMACY.selected_relation.guild.key,
    "guild-war",
    "selected relation"
)

equal(panel:set_tab("ALLIANCE"), true, "alliance tab accepted")
equal(panel.selected_guild, "guild-alliance", "alliance selection normalized")
equal(
    panel.view_model.views.ALLIANCE.selected_relation.guild.key,
    "guild-alliance",
    "alliance selected relation"
)
equal(panel:select_guild("guild-war"), false, "hidden relation rejected")
equal(panel.selected_guild, "guild-alliance", "alliance selection preserved")

equal(panel:set_tab("DIPLOMACY"), true, "diplomacy tab restored")
equal(panel:select_guild("guild-war"), true, "visible relation selected")

panel:apply_snapshot(snapshot({ relations[1] }))
equal(panel.selected_guild, "guild-alliance", "stale selection is replaced")

local invalid = snapshot()
invalid.members = "invalid"
equal(panel:apply_snapshot(invalid), false, "invalid snapshot shape")
equal(
    panel.view_model.error,
    "Sunucu UI verisi geçersiz: members",
    "contract field error"
)

local incompatible = snapshot()
incompatible.schema_version = 2
equal(panel:apply_snapshot(incompatible), false, "schema mismatch rejected")
equal(
    panel.view_model.error,
    "Sunucu UI veri sürümü uyumsuz.",
    "schema mismatch error"
)

local malformed_relation = snapshot({ "invalid" })
equal(panel:apply_snapshot(malformed_relation), false, "malformed relation rejected")
equal(#panel.view_model.views.DIPLOMACY.relations, 1, "previous snapshot preserved")
equal(
    panel.view_model.views.DIPLOMACY.relations[1].guild.key,
    "guild-alliance",
    "malformed relation does not reach presentation"
)

panel:set_chat_available(true)
equal(panel:append_chat({
    id = "message-1",
    sender = "Ada",
    text = "Merhaba",
    timestamp = 12346,
    kind = "GUILD",
    is_system = false
}), true, "chat message accepted")
equal(panel.view_model.views.CHAT.available, true, "chat available")
equal(panel.view_model.views.CHAT.message_count, 1, "chat count")
equal(panel.view_model.views.CHAT.messages[1].text, "Merhaba", "chat text")
equal(panel.view_model.tabs[4].badge_count, 1, "chat badge")

panel:clear_chat()
equal(panel.view_model.views.CHAT.empty, true, "chat cleared")
equal(
    panel.view_model.views.CHAT.empty_message,
    "Henüz sohbet mesajı yok.",
    "available chat empty message"
)

print("PALTR_UI_VIEW_MODEL_TEST_OK")
