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

local tab_control_definitions = {
    CLAN = {
        control = "ClanTabButton",
        text_control = "ClanTabText"
    },
    DIPLOMACY = {
        control = "DiplomacyTabButton",
        text_control = "DiplomacyTabText"
    },
    ALLIANCE = {
        control = "AllianceTabButton",
        text_control = "AllianceTabText"
    },
    CHAT = {
        control = "ChatTabButton",
        text_control = "ChatTabText"
    }
}

local action_control_definitions = {
    {
        control = "AllianceRequestButton",
        text_control = "AllianceRequestButtonText",
        action_id = "ALLIANCE",
        default_label = "İttifak İste"
    },
    {
        control = "WarRequestButton",
        text_control = "WarRequestButtonText",
        action_id = "DECLARE_WAR",
        default_label = "Savaş İlan Et"
    },
    {
        control = "AcceptButton",
        text_control = "AcceptButtonText",
        action_id = "ACCEPT",
        default_label = "Kabul Et"
    },
    {
        control = "RejectButton",
        text_control = "RejectButtonText",
        action_id = "REJECT",
        default_label = "Reddet"
    },
    {
        control = "CancelButton",
        text_control = "CancelButtonText",
        action_id = "CANCEL",
        default_label = "İptal Et"
    }
}

local function text(value)
    if value == nil then return "" end
    return tostring(value)
end

local function table_or_empty(value)
    if type(value) == "table" then return value end
    return {}
end

local function label_for(labels, value)
    local id = text(value)
    return labels[id] or id
end

local function copy_actions(source)
    local result = {}

    for _, action in ipairs(table_or_empty(source)) do
        action = table_or_empty(action)
        table.insert(result, {
            id = text(action.id),
            label = text(action.label)
        })
    end

    return result
end

local function action_control_models(relation)
    relation = table_or_empty(relation)
    local permissions = table_or_empty(relation.permissions)
    local offered = {}
    for _, action in ipairs(table_or_empty(relation.actions)) do
        action = table_or_empty(action)
        offered[text(action.id)] = action
    end

    local result = {}
    for _, definition in ipairs(action_control_definitions) do
        local action = offered[definition.action_id]
        local label = action and text(action.label) or ""
        local enabled = permissions.can_manage == true and action ~= nil
        local reason = ""
        if not enabled then
            reason = text(permissions.reason)
            if reason == "" then
                reason = action == nil
                    and "Aksiyon güncel snapshotta sunulmuyor."
                    or "Diplomasi aksiyonu kullanılamaz."
            end
        end
        result[definition.control] = {
            control = definition.control,
            text_control = definition.text_control,
            action_id = definition.action_id,
            label = label ~= "" and label or definition.default_label,
            enabled = enabled,
            reason = reason
        }
    end
    return result
end

local function member_model(member)
    member = table_or_empty(member)
    return {
        key = text(member.key),
        name = text(member.name),
        role = tonumber(member.role) or -1,
        is_master = member.is_master == true,
        online = member.online == true
    }
end

local function relation_model(relation, selected_guild)
    relation = table_or_empty(relation)
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
    snapshot = table_or_empty(snapshot)
    local guild = table_or_empty(snapshot.guild)
    local members = {}
    local online_count = 0

    for _, member in ipairs(table_or_empty(snapshot.members)) do
        local item = member_model(member)
        table.insert(members, item)
        if item.online then online_count = online_count + 1 end
    end

    return {
        guild = {
            key = text(guild.key),
            name = text(guild.name)
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
    local selected_alliance = nil

    for _, relation in ipairs(table_or_empty(snapshot.relations)) do
        local item = relation_model(relation, selected_guild)
        table.insert(diplomacy, item)

        if item.selected then selected_relation = item end
        if item.status.id == "ALLIANCE" or item.status.id == "ALLIANCE_PENDING" then
            local alliance_item = relation_model(relation, selected_guild)
            table.insert(alliance, alliance_item)
            if alliance_item.selected then selected_alliance = alliance_item end
        end
    end

    return {
        diplomacy = {
            relations = diplomacy,
            selected_relation = selected_relation,
            action_controls = action_control_models(selected_relation),
            empty = #diplomacy == 0,
            empty_message = #diplomacy == 0 and "Diplomasi kaydı bulunamadı." or ""
        },
        alliance = {
            relations = alliance,
            selected_relation = selected_alliance,
            empty = #alliance == 0,
            empty_message = #alliance == 0 and "Aktif veya bekleyen ittifak bulunamadı." or ""
        }
    }
end

local function chat_view(source)
    source = table_or_empty(source)
    local messages = {}

    for _, message in ipairs(table_or_empty(source.messages)) do
        message = table_or_empty(message)
        table.insert(messages, {
            id = text(message.id),
            sender = text(message.sender),
            text = text(message.text),
            timestamp = tonumber(message.timestamp) or 0,
            kind = text(message.kind),
            is_system = message.is_system == true
        })
    end

    local available = source.available == true
    local empty = #messages == 0
    local empty_message = ""
    if empty then
        empty_message = available
            and "Henüz sohbet mesajı yok."
            or "Sohbet transport bağlantısı henüz hazır değil."
    end

    return {
        available = available,
        messages = messages,
        message_count = #messages,
        empty = empty,
        empty_message = empty_message
    }
end

local function tab_models(active_tab, counts)
    local result = {}

    for _, tab in ipairs(Contract.TABS) do
        local definition = tab_control_definitions[tab.id] or {}
        table.insert(result, {
            id = tab.id,
            label = tab.label,
            control = definition.control or "",
            text_control = definition.text_control or "",
            active = tab.id == active_tab,
            enabled = tab.id ~= active_tab,
            badge_count = counts[tab.id] or 0
        })
    end

    return result
end

function ViewModel.build(snapshot, panel)
    snapshot = table_or_empty(snapshot)
    panel = table_or_empty(panel)
    local player = table_or_empty(snapshot.player)

    local active_tab = text(panel.active_tab)
    if active_tab == "" then active_tab = Contract.DEFAULT_TAB end

    local selected_guild = text(panel.selected_guild)
    local clan = clan_view(snapshot)
    local relation_data = relation_views(snapshot, selected_guild)
    local chat = chat_view(panel.chat)
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
            name = text(player.name),
            guild_key = text(player.guild_key),
            role = tonumber(player.role) or -1,
            is_master = player.is_master == true
        },
        tabs = tab_models(active_tab, {
            CLAN = clan.member_count,
            DIPLOMACY = #relation_data.diplomacy.relations,
            ALLIANCE = #relation_data.alliance.relations,
            CHAT = chat.message_count
        }),
        views = views,
        content = views[active_tab] or views[Contract.DEFAULT_TAB]
    }
end

return ViewModel
