local Contract = require("contract")

local ViewModel = {}

local state_labels = {
    NEUTRAL = "Tarafsız",
    WAR_PENDING = "Savaş ilanı bekliyor",
    WAR = "Savaş",
    CEASEFIRE_PENDING = "Ateşkes teklifi bekliyor",
    CEASEFIRE = "Ateşkes",
    PEACE_PENDING = "Barış teklifi bekliyor",
    ALLIANCE_PENDING = "İttifak teklifi bekliyor",
    ALLIANCE = "İttifak"
}

local direction_labels = {
    incoming = "Gelen teklif",
    outgoing = "Gönderilen teklif",
    none = ""
}

local function text(value)
    if value == nil then return "" end
    return tostring(value)
end

local function label_for(labels, value)
    local id = text(value)
    return labels[id] or id
end

local function copy_actions(source)
    local result = {}

    for _, action in ipairs(source or {}) do
        table.insert(result, {
            id = text(action.id),
            label = text(action.label)
        })
    end

    return result
end

local function member_model(member)
    return {
        key = text(member.key),
        name = text(member.name),
        role = tonumber(member.role) or -1,
        is_master = member.is_master == true,
        online = member.online == true
    }
end

local function relation_model(relation, selected_guild)
    local state = text(relation.state)
    local direction = text(relation.proposal_direction)

    return {
        guild = {
            key = text(relation.guild_key),
            name = text(relation.guild_name)
        },
        selected = text(relation.guild_key) == selected_guild,
        status = {
            id = state,
            label = label_for(state_labels, state),
            previous_id = text(relation.previous_state),
            proposal_direction = direction,
            proposal_direction_label = label_for(direction_labels, direction),
            active_at = tonumber(relation.active_at) or 0,
            expires_at = tonumber(relation.expires_at) or 0,
            note = text(relation.note)
        },
        permissions = {
            can_manage = relation.can_manage == true,
            reason = text(relation.action_reason)
        },
        actions = copy_actions(relation.actions)
    }
end

local function clan_view(snapshot)
    local members = {}
    local online_count = 0

    for _, member in ipairs(snapshot.members or {}) do
        local item = member_model(member)
        table.insert(members, item)
        if item.online then online_count = online_count + 1 end
    end

    return {
        guild = {
            key = text(snapshot.guild and snapshot.guild.key),
            name = text(snapshot.guild and snapshot.guild.name)
        },
        members = members,
        member_count = #members,
        online_count = online_count,
        empty = #members == 0,
        empty_message = #members == 0 and "Klan üyesi bulunamadı." or ""
    }
end

local function relation_views(snapshot, selected_guild)
    local diplomacy = {}
    local alliance = {}
    local selected_relation = nil

    for _, relation in ipairs(snapshot.relations or {}) do
        local item = relation_model(relation, selected_guild)
        table.insert(diplomacy, item)

        if item.selected then selected_relation = item end
        if item.status.id == "ALLIANCE" or item.status.id == "ALLIANCE_PENDING" then
            table.insert(alliance, relation_model(relation, selected_guild))
        end
    end

    return {
        diplomacy = {
            relations = diplomacy,
            selected_relation = selected_relation,
            empty = #diplomacy == 0,
            empty_message = #diplomacy == 0 and "Diplomasi kaydı bulunamadı." or ""
        },
        alliance = {
            relations = alliance,
            empty = #alliance == 0,
            empty_message = #alliance == 0 and "Aktif veya bekleyen ittifak bulunamadı." or ""
        }
    }
end

local function tab_models(active_tab, counts)
    local result = {}

    for _, tab in ipairs(Contract.TABS) do
        table.insert(result, {
            id = tab.id,
            label = tab.label,
            active = tab.id == active_tab,
            badge_count = counts[tab.id] or 0
        })
    end

    return result
end

function ViewModel.build(snapshot, panel)
    snapshot = type(snapshot) == "table" and snapshot or {}
    panel = type(panel) == "table" and panel or {}

    local active_tab = text(panel.active_tab)
    if active_tab == "" then active_tab = Contract.DEFAULT_TAB end

    local selected_guild = text(panel.selected_guild)
    local clan = clan_view(snapshot)
    local relation_data = relation_views(snapshot, selected_guild)
    local chat = {
        available = false,
        messages = {},
        empty = true,
        empty_message = "Sohbet transport bağlantısı henüz hazır değil."
    }
    local views = {
        CLAN = clan,
        DIPLOMACY = relation_data.diplomacy,
        ALLIANCE = relation_data.alliance,
        CHAT = chat
    }

    return {
        schema_version = tonumber(snapshot.schema_version) or 0,
        generated_at = tonumber(snapshot.generated_at) or 0,
        open = panel.open == true,
        active_tab = active_tab,
        selected_guild = selected_guild,
        error = text(panel.error),
        player = {
            name = text(snapshot.player and snapshot.player.name),
            guild_key = text(snapshot.player and snapshot.player.guild_key),
            role = tonumber(snapshot.player and snapshot.player.role) or -1,
            is_master = snapshot.player and snapshot.player.is_master == true or false
        },
        tabs = tab_models(active_tab, {
            CLAN = clan.member_count,
            DIPLOMACY = #relation_data.diplomacy.relations,
            ALLIANCE = #relation_data.alliance.relations,
            CHAT = 0
        }),
        views = views,
        content = views[active_tab] or views[Contract.DEFAULT_TAB]
    }
end

return ViewModel
