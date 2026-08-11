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
                key = "player-2",
                name = "Bora",
                role = 0,
                is_master = false,
                online = false
            },
            {
                key = "player-1",
                name = "Ada",
                role = 1,
                is_master = true,
                online = true
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

local panel = PanelState.new({ action_transport_ready = true })
equal(panel.view_model.active_tab, "CLAN", "default tab")
equal(panel.view_model.views.CHAT.available, false, "chat transport")
equal(panel.view_model.views.CHAT.message_count, 0, "empty chat")
equal(panel.view_model.connection.status_text, "Baglanti bekleniyor",
    "waiting connection text is compact")
equal(panel.view_model.header.guild_text, "Klan: ...",
    "waiting guild header")
equal(panel.view_model.header.role_text, "Rol: ...",
    "waiting role header")
equal(panel.view_model.views.CLAN.dashboard.cards[1].value, "",
    "waiting clan card does not show fake data")
equal(panel.view_model.views.CLAN.dashboard.war_count_text, "",
    "waiting diplomacy card does not show fake counts")
equal(panel.view_model.views.CLAN.dashboard.relation_rows[1].guild_name, "",
    "waiting relation row stays empty")

equal(panel:apply_snapshot(snapshot(relations)), true, "valid snapshot")
equal(panel.selected_guild, "guild-alliance", "default relation selection")
equal(panel.view_model.views.CLAN.member_count, 2, "member count")
equal(panel.view_model.views.CLAN.online_count, 1, "online count")
equal(panel.view_model.views.CLAN.offline_count, 1, "offline count")
equal(panel.view_model.views.CLAN.members_heading_text, "KLAN ÜYELERİ (2)",
    "member section heading")
equal(panel.view_model.views.CLAN.members_status_text,
    "1 çevrimiçi | 1 çevrimdışı", "member section status")
equal(panel.view_model.views.CLAN.members[1].name, "Ada",
    "leader sorted before snapshot order")
equal(panel.view_model.views.CLAN.members[1].role_label, "Lider",
    "leader presentation role")
equal(panel.view_model.views.CLAN.members[1].presence_label, "Çevrimiçi",
    "online presentation state")
equal(panel.view_model.views.CLAN.members[2].role_label, "Üye",
    "member presentation role")
equal(panel.view_model.views.CLAN.members[2].presence_label, "Çevrimdışı",
    "offline presentation state")
equal(
    panel.view_model.views.CLAN.members_text,
    "Ada | Lider | Çevrimiçi\nBora | Üye | Çevrimdışı",
    "member renderer text"
)
equal(#panel.view_model.views.DIPLOMACY.relations, 3, "diplomacy count")
equal(#panel.view_model.views.ALLIANCE.relations, 1, "alliance filter")
equal(panel.view_model.views.ALLIANCE.title_text, relations[1].guild_name,
    "selected alliance title")
equal(panel.view_model.views.ALLIANCE.navigation_controls.PreviousAllianceButton.enabled,
    false, "single alliance navigation disabled")
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
equal(panel.view_model.header.guild_text, "Klan: Anka",
    "header guild presentation")
equal(panel.view_model.header.role_text, "Rol: Lider",
    "header role presentation")
equal(panel.view_model.header.notification_text, "Bildirim: 0",
    "header notification presentation")
equal(
    panel.view_model.connection.status_text,
    "Sunucu Aktif",
    "snapshot connection text"
)
equal(panel.view_model.views.CLAN.name_text, "Anka", "clan name text")
equal(
    panel.view_model.views.CLAN.summary_text,
    "Rol: Lider\nÜye: 2\nÇevrimiçi: 1\nSavaş: 1\nİttifak: 1\nBekleyen: 0",
    "clan summary text"
)
equal(panel.view_model.views.CLAN.leader_name, "Ada", "clan leader")
equal(panel.view_model.views.CLAN.dashboard.war_count, 1,
    "dashboard war count")
equal(panel.view_model.views.CLAN.dashboard.alliance_count, 1,
    "dashboard alliance count")
equal(panel.view_model.views.CLAN.dashboard.pending_count, 0,
    "dashboard pending count")
equal(panel.view_model.views.CLAN.dashboard.relations_empty, false,
    "dashboard relations available")
equal(panel.view_model.views.CLAN.dashboard.relation_rows[1].guild_name,
    "Rakipler", "dashboard first relation card")
equal(panel.view_model.views.CLAN.dashboard.relation_rows[1].state_label,
    "Savaş", "dashboard first relation state")
equal(string.find(
    panel.view_model.views.CLAN.dashboard.relations_text,
    "Rakipler",
    1,
    true
) ~= nil, true, "dashboard relation preview")

local overflow_relations = {}
for _, relation in ipairs(relations) do
    table.insert(overflow_relations, relation)
end
table.insert(overflow_relations, {
    guild_key = "guild-four",
    guild_name = "Dordunculer",
    state = "NEUTRAL",
    can_manage = false,
    actions = {}
})
table.insert(overflow_relations, {
    guild_key = "guild-five",
    guild_name = "Besinciler",
    state = "NEUTRAL",
    can_manage = false,
    actions = {}
})
local overflow_panel = PanelState.new({ action_transport_ready = true })
equal(overflow_panel:apply_snapshot(snapshot(overflow_relations)), true,
    "overflow snapshot")
equal(string.find(
    overflow_panel.view_model.views.CLAN.dashboard.relations_text,
    "+1 klan daha",
    1,
    true
) ~= nil, true, "dashboard relation preview is bounded")
equal(string.find(
    overflow_panel.view_model.views.CLAN.dashboard.relations_text,
    "Besinciler",
    1,
    true
) == nil, true, "dashboard overflow relation stays in full list only")
equal(panel.view_model.views.CLAN.pending_empty, true,
    "dashboard pending offers empty")
equal(panel.view_model.views.CLAN.pending_text, "Bekleyen teklif yok.",
    "dashboard pending empty text")
equal(panel.view_model.views.CLAN.dashboard.cards[1].id, "CLAN_STATUS",
    "clan dashboard card")
equal(panel.view_model.views.CLAN.dashboard.cards[1].value_control,
    "DashboardClanCardValueText", "clan dashboard renderer control")
equal(panel.view_model.views.CLAN.dashboard.cards[2].id,
    "DIPLOMACY_STATUS", "diplomacy dashboard card")
equal(panel.view_model.views.CLAN.dashboard.cards[2].value_control,
    "DashboardDiplomacyCardValueText",
    "diplomacy dashboard renderer control")
equal(panel.view_model.views.CLAN.quick_actions.DashboardOffersButton.enabled,
    false, "pending quick action disabled")
equal(panel.view_model.views.CLAN.quick_actions.DashboardOffersButton.reason,
    "Bekleyen teklif yok.", "pending quick action reason")

local pending_relations = {
    relations[1],
    {
        guild_key = "guild-offer",
        guild_name = "Teklifçiler",
        state = "ALLIANCE_PENDING",
        previous_state = "NEUTRAL",
        proposal_direction = "incoming",
        can_manage = true,
        action_reason = "",
        actions = {
            { id = "ACCEPT", label = "Kabul Et" },
            { id = "REJECT", label = "Reddet" }
        }
    }
}
local pending_panel = PanelState.new()
equal(pending_panel:apply_snapshot(snapshot(pending_relations)), true,
    "pending snapshot accepted")
equal(pending_panel.view_model.views.CLAN.pending_count, 1,
    "pending offer count")
equal(pending_panel.view_model.views.CLAN.pending_offers[1].guild_key,
    "guild-offer", "pending offer identity")
equal(pending_panel.view_model.views.CLAN.pending_text,
    "Teklifçiler | İttifak teklifi bekliyor | Gelen teklif",
    "pending offer presentation text")
equal(pending_panel.view_model.views.CLAN.quick_actions.DashboardOffersButton.enabled,
    true, "pending quick action enabled")
equal(pending_panel.view_model.views.CLAN.quick_actions.DashboardOffersButton.target_guild,
    "guild-offer", "pending quick action target guild")
equal(pending_panel.view_model.views.CLAN.dashboard.pending_guild_text,
    "Teklifçiler", "pending dashboard guild")
equal(pending_panel.view_model.views.CLAN.dashboard.pending_state_text,
    "İttifak teklifi bekliyor", "pending dashboard state")
equal(pending_panel.view_model.views.CLAN.quick_actions.DashboardPendingAcceptButton.enabled,
    false, "pending accept requires transport")

local action_ready_pending_panel = PanelState.new({
    action_transport_ready = true
})
equal(action_ready_pending_panel:apply_snapshot(snapshot(pending_relations)), true,
    "action-ready pending snapshot accepted")
equal(action_ready_pending_panel.view_model.views.CLAN.quick_actions.DashboardPendingAcceptButton.enabled,
    true, "server-offered pending accept enabled")
equal(action_ready_pending_panel.view_model.views.CLAN.quick_actions.DashboardPendingRejectButton.enabled,
    true, "server-offered pending reject enabled")

local outgoing_pending = {
    relations[1],
    {
        guild_key = "guild-outgoing",
        guild_name = "Giden Teklif",
        state = "ALLIANCE_PENDING",
        previous_state = "NEUTRAL",
        proposal_direction = "outgoing",
        can_manage = true,
        action_reason = "",
        actions = {
            { id = "CANCEL", label = "Teklifi Iptal Et" }
        }
    }
}
local outgoing_panel = PanelState.new({ action_transport_ready = true })
equal(outgoing_panel:apply_snapshot(snapshot(outgoing_pending)), true,
    "outgoing pending snapshot accepted")
equal(outgoing_panel.view_model.views.CLAN.quick_actions.DashboardPendingAcceptButton.enabled,
    false, "unoffered dashboard accept disabled")
equal(outgoing_panel.view_model.views.CLAN.quick_actions.DashboardPendingRejectButton.enabled,
    false, "unoffered dashboard reject disabled")
equal(outgoing_panel.view_model.views.CLAN.quick_actions.DashboardPendingAcceptButton.reason,
    "Aksiyon guncel sunucu snapshotinda sunulmuyor.",
    "unoffered dashboard action reason")

local mixed_pending_panel = PanelState.new({ action_transport_ready = true })
equal(mixed_pending_panel:apply_snapshot(snapshot({
    outgoing_pending[2],
    pending_relations[2]
})), true, "mixed pending snapshot accepted")
equal(mixed_pending_panel.view_model.views.CLAN.dashboard.pending_guild_text,
    "Teklifçiler", "actionable incoming offer prioritized")
equal(mixed_pending_panel.view_model.views.CLAN.quick_actions.DashboardPendingAcceptButton.target_guild,
    "guild-offer", "dashboard accept targets actionable offer")
equal(mixed_pending_panel.view_model.views.CLAN.quick_actions.DashboardPendingAcceptButton.enabled,
    true, "prioritized incoming accept enabled")
equal(
    panel.view_model.views.CLAN.members_text,
    "Ada | Lider | Çevrimiçi\nBora | Üye | Çevrimdışı",
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
equal(panel.view_model.tabs[2].enabled, true, "active tab remains interactive")
equal(panel.view_model.tabs[2].page_index, 1, "diplomacy page index")
equal(
    panel.view_model.tabs[2].display_label,
    "> Diplomasi (3)",
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
local navigation_controls =
    panel.view_model.views.DIPLOMACY.navigation_controls
equal(navigation_controls.PreviousRelationButton.enabled, true,
    "previous relation enabled")
equal(navigation_controls.PreviousRelationButton.step, -1,
    "previous relation step")
equal(navigation_controls.NextRelationButton.enabled, true,
    "next relation enabled")
equal(navigation_controls.NextRelationButton.step, 1,
    "next relation step")

panel:select_guild("guild-war")
equal(
    panel.view_model.views.DIPLOMACY.selected_relation.guild.key,
    "guild-war",
    "selected relation"
)
local war_actions = panel.view_model.views.DIPLOMACY.action_controls
equal(war_actions.AllianceRequestButton.enabled, true,
    "ceasefire action slot enabled")
equal(war_actions.AllianceRequestButton.action_id, "CEASEFIRE",
    "ceasefire action assigned from server offer")
equal(war_actions.AllianceRequestButton.label, "Ateşkes Teklif Et",
    "ceasefire server label preserved")
equal(war_actions.CancelButton.enabled, true,
    "peace action slot enabled")
equal(war_actions.CancelButton.action_id, "PEACE",
    "peace action assigned from server offer")

panel:select_guild("guild-alliance")
local alliance_actions = panel.view_model.views.DIPLOMACY.action_controls
equal(alliance_actions.CancelButton.enabled, true,
    "return neutral action slot enabled")
equal(alliance_actions.CancelButton.action_id, "RETURN_NEUTRAL",
    "return neutral action assigned from server offer")

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
equal(
    panel.view_model.views.DIPLOMACY.navigation_controls.NextRelationButton.enabled,
    false,
    "single relation navigation disabled"
)

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

local catalog_snapshot = snapshot({ relations[1] })
catalog_snapshot.guilds = {
    {
        key = "guild-active",
        name = "Gezginler",
        member_count = 4,
        online_count = 2,
        active = true
    },
    {
        key = "guild-inactive",
        name = "Uykudakiler",
        member_count = 3,
        online_count = 0,
        active = false
    }
}
equal(panel:apply_snapshot(catalog_snapshot), true, "guild catalog accepted")
equal(#panel.view_model.views.DIPLOMACY.relations, 2,
    "active guild added to diplomacy presentation")
equal(panel:select_guild("guild-active"), true,
    "active guild can be selected")
equal(panel.view_model.views.DIPLOMACY.selected_relation.status.id,
    "NEUTRAL", "active guild defaults to neutral presentation")
equal(panel.view_model.views.DIPLOMACY.selected_relation.permissions.can_manage,
    false, "catalog guild does not infer permissions")
equal(panel:select_guild("guild-inactive"), false,
    "inactive guild is not selectable")
equal(panel.view_model.views.GUILDS.guild_count, 2,
    "guild catalog count")
equal(panel.view_model.views.GUILDS.active_count, 1,
    "active guild count")
equal(panel.view_model.views.GUILDS.registered_count, 1,
    "registered guild count")
equal(panel.view_model.views.GUILDS.active_heading_text,
    "AKTİF KLANLAR (1)", "active guild heading count")
equal(panel.view_model.views.GUILDS.registered_heading_text,
    "KAYITLI KLANLAR (1)", "registered guild heading count")
equal(string.find(panel.view_model.views.GUILDS.active_text,
    "Gezginler", 1, true) ~= nil, true, "active guild group")
equal(string.find(panel.view_model.views.GUILDS.registered_text,
    "Uykudakiler", 1, true) ~= nil, true, "registered guild group")
equal(panel.view_model.views.GUILDS.list_text,
    "Gezginler | Aktif | 4 uye | 2 cevrimici\nUykudakiler | Kayitli | 3 uye | 0 cevrimici",
    "guild catalog presentation text")
equal(panel:set_tab("GUILDS"), true, "guild catalog tab accepted")
equal(panel.view_model.active_tab, "GUILDS", "guild catalog tab active")
equal(panel.view_model.content, panel.view_model.views.GUILDS,
    "guild catalog content selected")

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
equal(panel.view_model.tabs[4].badge_count, 1, "active guild badge")

panel:clear_chat()
equal(panel.view_model.views.CHAT.empty, true, "chat cleared")
equal(
    panel.view_model.views.CHAT.empty_message,
    "Henüz sohbet mesajı yok.",
    "available chat empty message"
)

print("PALTR_UI_VIEW_MODEL_TEST_OK")
