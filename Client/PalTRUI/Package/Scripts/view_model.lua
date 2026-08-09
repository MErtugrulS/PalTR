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
        text_control = "ClanTabText",
        page_index = 0
    },
    DIPLOMACY = {
        control = "DiplomacyTabButton",
        text_control = "DiplomacyTabText",
        page_index = 1
    },
    ALLIANCE = {
        control = "AllianceTabButton",
        text_control = "AllianceTabText",
        page_index = 2
    },
    GUILDS = {
        control = "ChatTabButton",
        text_control = "ChatTabText",
        page_index = 3
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

local relation_navigation_definitions = {
    {
        control = "PreviousRelationButton",
        text_control = "PreviousRelationButtonText",
        label = "Onceki",
        step = -1
    },
    {
        control = "NextRelationButton",
        text_control = "NextRelationButtonText",
        label = "Sonraki",
        step = 1
    }
}

local alliance_navigation_definitions = {
    {
        control = "PreviousAllianceButton",
        text_control = "PreviousAllianceButtonText",
        label = "Onceki",
        step = -1
    },
    {
        control = "NextAllianceButton",
        text_control = "NextAllianceButtonText",
        label = "Sonraki",
        step = 1
    }
}

local dashboard_action_definitions = {
    {
        control = "DashboardDiplomacyButton",
        text_control = "DashboardDiplomacyButtonText",
        label = "Diplomasiyi Ac",
        target_tab = "DIPLOMACY"
    },
    {
        control = "DashboardOffersButton",
        text_control = "DashboardOffersButtonText",
        label = "Teklifleri Gor",
        target_tab = "DIPLOMACY",
        requires_pending = true
    },
    {
        control = "DashboardGuildsButton",
        text_control = "DashboardGuildsButtonText",
        label = "Klanlari Listele",
        target_tab = "GUILDS",
        requires_guilds = true
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

local function action_control_models(relation, action_transport_ready)
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
        local enabled = action_transport_ready == true
            and permissions.can_manage == true and action ~= nil
        local reason = ""
        if not enabled then
            if action_transport_ready ~= true then
                reason = "Client-server UI transportu hazir degil."
            else
                reason = text(permissions.reason)
            end
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

local function relation_navigation_controls(relation_count, definitions)
    local result = {}
    local enabled = tonumber(relation_count) ~= nil and relation_count > 1
    for _, definition in ipairs(definitions or relation_navigation_definitions) do
        result[definition.control] = {
            control = definition.control,
            text_control = definition.text_control,
            label = definition.label,
            step = definition.step,
            enabled = enabled,
            reason = enabled and ""
                or "Gezinmek icin en az iki klan gerekli."
        }
    end
    return result
end

local function member_model(member)
    member = table_or_empty(member)
    local name = text(member.name)
    local is_master = member.is_master == true
    local online = member.online == true
    local role_label = is_master and "Lider" or "Üye"
    local presence_label = online and "Çevrimiçi" or "Çevrimdışı"
    return {
        key = text(member.key),
        name = name,
        role = tonumber(member.role) or -1,
        is_master = is_master,
        online = online,
        role_label = role_label,
        presence_label = presence_label,
        display_text = string.format(
            "%s | %s | %s",
            name ~= "" and name or "-",
            role_label,
            presence_label
        )
    }
end

local function member_lines(members)
    local lines = {}
    for _, member in ipairs(members) do
        table.insert(lines, text(member.display_text))
    end
    return table.concat(lines, "\n")
end

local function sort_members(members)
    table.sort(members, function(left, right)
        if left.is_master ~= right.is_master then
            return left.is_master == true
        end
        if left.online ~= right.online then
            return left.online == true
        end
        local left_name = string.lower(text(left.name))
        local right_name = string.lower(text(right.name))
        if left_name ~= right_name then return left_name < right_name end
        return text(left.key) < text(right.key)
    end)
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

local function presentation_relations(snapshot)
    local result = {}
    local known = {}

    for _, relation in ipairs(table_or_empty(snapshot.relations)) do
        table.insert(result, relation)
        if type(relation) == "table" then
            known[text(relation.guild_key)] = true
        end
    end

    for _, guild in ipairs(table_or_empty(snapshot.guilds)) do
        guild = table_or_empty(guild)
        local key = text(guild.key)
        if guild.active == true and key ~= "" and not known[key] then
            table.insert(result, {
                guild_key = key,
                guild_name = text(guild.name),
                state = "NEUTRAL",
                previous_state = "NEUTRAL",
                proposal_direction = "none",
                note = string.format(
                    "%d uye | %d cevrimici",
                    tonumber(guild.member_count) or 0,
                    tonumber(guild.online_count) or 0
                ),
                can_manage = false,
                action_reason = "Diplomasi kaydi henuz olusmadi.",
                actions = {}
            })
            known[key] = true
        end
    end

    table.sort(result, function(a, b)
        return string.lower(text(table_or_empty(a).guild_name))
            < string.lower(text(table_or_empty(b).guild_name))
    end)
    return result
end

local function relation_lines(relations)
    local lines = {}
    for _, relation in ipairs(relations) do
        local prefix = relation.selected and "> " or "  "
        table.insert(lines, string.format(
            "%s%s | %s",
            prefix,
            relation.guild.name,
            relation.status.label
        ))
    end
    return table.concat(lines, "\n")
end

local function relation_description(relation)
    relation = table_or_empty(relation)
    local status = table_or_empty(relation.status)
    local permissions = table_or_empty(relation.permissions)
    local parts = {}
    for _, value in ipairs({
        status.proposal_direction_label,
        status.note,
        permissions.reason
    }) do
        value = text(value)
        if value ~= "" then table.insert(parts, value) end
    end
    return #parts > 0 and table.concat(parts, " | ")
        or "Iliski ayrintisi yok."
end

local function action_transport_status(action_transport_ready)
    if action_transport_ready == true then return "" end
    return "Client-server UI transportu hazir degil."
end

local function append_status(description, status)
    description = text(description)
    status = text(status)
    if status == "" then return description end
    if description == "" then return status end
    return description .. " | " .. status
end

local function clan_view(snapshot)
    snapshot = table_or_empty(snapshot)
    local guild = table_or_empty(snapshot.guild)
    local members = {}
    local online_count = 0
    local leader_name = ""

    for _, member in ipairs(table_or_empty(snapshot.members)) do
        local item = member_model(member)
        table.insert(members, item)
        if item.online then online_count = online_count + 1 end
        if item.is_master and leader_name == "" then
            leader_name = item.name
        end
    end
    sort_members(members)

    local war_count = 0
    local alliance_count = 0
    local pending_count = 0
    local pending_offers = {}
    local relation_preview_lines = {}
    local relation_preview_count = 0
    for _, relation in ipairs(table_or_empty(snapshot.relations)) do
        relation = table_or_empty(relation)
        local state = text(relation.state)
        if state == "WAR" then war_count = war_count + 1 end
        if state == "ALLIANCE" then alliance_count = alliance_count + 1 end
        if string.sub(state, -8) == "_PENDING" then
            pending_count = pending_count + 1
            table.insert(pending_offers, {
                guild_key = text(relation.guild_key),
                guild_name = text(relation.guild_name),
                state = state,
                state_label = label_for(state_labels, state),
                direction = text(relation.proposal_direction),
                direction_label = label_for(
                    direction_labels,
                    relation.proposal_direction
                )
            })
        end
        local relation_name = text(relation.guild_name)
        if relation_name ~= "" then
            relation_preview_count = relation_preview_count + 1
            if relation_preview_count <= 4 then
                table.insert(relation_preview_lines, string.format(
                    "%s | %s",
                    relation_name,
                    label_for(state_labels, state)
                ))
            end
        end
    end

    if relation_preview_count > 4 then
        table.insert(relation_preview_lines, string.format(
            "+%d klan daha",
            relation_preview_count - 4
        ))
    end

    local pending_lines = {}
    for _, offer in ipairs(pending_offers) do
        local detail = offer.direction_label ~= ""
            and " | " .. offer.direction_label or ""
        table.insert(pending_lines, string.format(
            "%s | %s%s",
            offer.guild_name,
            offer.state_label,
            detail
        ))
    end

    local guild_name = text(guild.name)
    local empty = #members == 0
    local empty_message = empty and "Klan üyesi bulunamadı." or ""

    local clan_card = {
        id = "CLAN_STATUS",
        title_control = "DashboardClanCardTitleText",
        value_control = "DashboardClanCardValueText",
        detail_control = "DashboardClanCardDetailText",
        title = "Klanım",
        value = guild_name ~= "" and guild_name or "-",
        detail = string.format(
            "Lider: %s | Üye: %d | Çevrimiçi: %d",
            leader_name ~= "" and leader_name or "-",
            #members,
            online_count
        )
    }
    local diplomacy_card = {
        id = "DIPLOMACY_STATUS",
        title_control = "DashboardDiplomacyCardTitleText",
        value_control = "DashboardDiplomacyCardValueText",
        detail_control = "DashboardDiplomacyCardDetailText",
        title = "Diplomasi",
        value = string.format(
            "Savaş: %d | İttifak: %d | Bekleyen: %d",
            war_count,
            alliance_count,
            pending_count
        ),
        detail = ""
    }
    local quick_actions = {}
    local guild_count = #table_or_empty(snapshot.guilds)
    for _, definition in ipairs(dashboard_action_definitions) do
        local enabled = true
        local reason = ""
        if definition.requires_pending and pending_count == 0 then
            enabled = false
            reason = "Bekleyen teklif yok."
        elseif definition.requires_guilds and guild_count == 0 then
            enabled = false
            reason = "Listelenecek klan yok."
        end
        quick_actions[definition.control] = {
            control = definition.control,
            text_control = definition.text_control,
            label = definition.label,
            target_tab = definition.target_tab,
            target_guild = definition.requires_pending
                and text(table_or_empty(pending_offers[1]).guild_key) or "",
            enabled = enabled,
            reason = reason
        }
    end

    return {
        guild = {
            key = text(guild.key),
            name = guild_name
        },
        members = members,
        member_count = #members,
        online_count = online_count,
        offline_count = #members - online_count,
        leader_name = leader_name,
        members_heading_text = string.format(
            "KLAN ÜYELERİ (%d)",
            #members
        ),
        members_status_text = string.format(
            "%d çevrimiçi | %d çevrimdışı",
            online_count,
            #members - online_count
        ),
        dashboard = {
            cards = { clan_card, diplomacy_card },
            war_count = war_count,
            alliance_count = alliance_count,
            pending_count = pending_count,
            relations_empty = #relation_preview_lines == 0,
            relations_text = #relation_preview_lines == 0
                and "Iliski kaydi yok."
                or table.concat(relation_preview_lines, "\n")
        },
        pending_offers = pending_offers,
        pending_count = pending_count,
        pending_empty = pending_count == 0,
        pending_text = pending_count == 0
            and "Bekleyen teklif yok."
            or table.concat(pending_lines, "\n"),
        quick_actions = quick_actions,
        empty = empty,
        empty_message = empty_message,
        name_text = guild_name ~= ""
            and guild_name or "Klan bilgisi bekleniyor",
        summary_text = clan_card.detail .. "\n" .. diplomacy_card.value,
        members_text = empty and empty_message or member_lines(members)
    }
end

local function relation_views(snapshot, selected_guild, action_transport_ready)
    local diplomacy = {}
    local alliance = {}
    local selected_relation = nil
    local selected_alliance = nil

    for _, relation in ipairs(presentation_relations(snapshot)) do
        local item = relation_model(relation, selected_guild)
        table.insert(diplomacy, item)

        if item.selected then selected_relation = item end
        if item.status.id == "ALLIANCE" or item.status.id == "ALLIANCE_PENDING" then
            local alliance_item = relation_model(relation, selected_guild)
            table.insert(alliance, alliance_item)
            if alliance_item.selected then selected_alliance = alliance_item end
        end
    end

    local diplomacy_empty = #diplomacy == 0
    local diplomacy_empty_message = diplomacy_empty
        and "Diplomasi kaydı bulunamadı." or ""
    local selected_guild_model = table_or_empty(
        table_or_empty(selected_relation).guild
    )
    local selected_status = table_or_empty(
        table_or_empty(selected_relation).status
    )
    local transport_status = action_transport_status(
        action_transport_ready
    )
    local alliance_empty = #alliance == 0
    local selected_alliance_guild = table_or_empty(
        table_or_empty(selected_alliance).guild
    )
    local selected_alliance_status = table_or_empty(
        table_or_empty(selected_alliance).status
    )
    local alliance_empty_message = alliance_empty
        and "Aktif veya bekleyen ittifak bulunamadı." or ""

    return {
        diplomacy = {
            relations = diplomacy,
            selected_relation = selected_relation,
            action_controls = action_control_models(
                selected_relation,
                action_transport_ready
            ),
            navigation_controls = relation_navigation_controls(#diplomacy),
            empty = diplomacy_empty,
            empty_message = diplomacy_empty_message,
            list_text = diplomacy_empty
                and diplomacy_empty_message or relation_lines(diplomacy),
            title_text = text(selected_guild_model.name) ~= ""
                and selected_guild_model.name or "Klan secin",
            state_text = text(selected_status.label) ~= ""
                and selected_status.label or "Iliski durumu: -",
            description_text = append_status(
                relation_description(selected_relation),
                transport_status
            )
        },
        alliance = {
            relations = alliance,
            selected_relation = selected_alliance,
            navigation_controls = relation_navigation_controls(
                #alliance,
                alliance_navigation_definitions
            ),
            empty = alliance_empty,
            empty_message = alliance_empty_message,
            summary_text = string.format("%d ittifak kaydi", #alliance),
            members_text = alliance_empty
                and alliance_empty_message or relation_lines(alliance),
            title_text = text(selected_alliance_guild.name) ~= ""
                and selected_alliance_guild.name or "Ittifak secin",
            state_text = text(selected_alliance_status.label) ~= ""
                and selected_alliance_status.label or "Ittifak durumu: -",
            description_text = relation_description(selected_alliance)
        }
    }
end

local function guild_catalog_view(snapshot)
    local guilds = {}
    local active_count = 0

    for _, guild in ipairs(table_or_empty(snapshot.guilds)) do
        guild = table_or_empty(guild)
        local item = {
            key = text(guild.key),
            name = text(guild.name),
            member_count = tonumber(guild.member_count) or 0,
            online_count = tonumber(guild.online_count) or 0,
            active = guild.active == true
        }
        if item.active then active_count = active_count + 1 end
        table.insert(guilds, item)
    end

    table.sort(guilds, function(a, b)
        if a.active ~= b.active then return a.active end
        return string.lower(a.name) < string.lower(b.name)
    end)

    local lines = {}
    local active_lines = {}
    local registered_lines = {}
    for _, guild in ipairs(guilds) do
        local line = string.format(
            "%s | %s | %d uye | %d cevrimici",
            guild.name ~= "" and guild.name or guild.key,
            guild.active and "Aktif" or "Kayitli",
            guild.member_count,
            guild.online_count
        )
        table.insert(lines, line)
        table.insert(guild.active and active_lines or registered_lines, line)
    end

    local empty = #guilds == 0
    local empty_message = empty and "Klan kaydi bulunamadi." or ""
    return {
        guilds = guilds,
        guild_count = #guilds,
        active_count = active_count,
        registered_count = #guilds - active_count,
        empty = empty,
        empty_message = empty_message,
        summary_text = string.format(
            "%d klan | %d aktif",
            #guilds,
            active_count
        ),
        list_text = empty and empty_message
            or table.concat(lines, "\n"),
        active_text = #active_lines == 0
            and "Aktif klan yok." or table.concat(active_lines, "\n"),
        registered_text = #registered_lines == 0
            and "Kayitli klan yok." or table.concat(registered_lines, "\n")
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

    local lines = {}
    for _, message in ipairs(messages) do
        table.insert(lines, string.format(
            "%s: %s",
            message.sender,
            message.text
        ))
    end

    return {
        available = available,
        messages = messages,
        message_count = #messages,
        empty = empty,
        empty_message = empty_message,
        messages_text = empty
            and empty_message or table.concat(lines, "\n")
    }
end

local function tab_models(active_tab, counts)
    local result = {}

    for _, tab in ipairs(Contract.TABS) do
        local definition = tab_control_definitions[tab.id] or {}
        local badge_count = counts[tab.id] or 0
        local active = tab.id == active_tab
        local counted_label = badge_count > 0
            and string.format("%s (%d)", tab.label, badge_count)
            or tab.label
        table.insert(result, {
            id = tab.id,
            label = tab.label,
            display_label = active
                and "> " .. counted_label or counted_label,
            control = definition.control or "",
            text_control = definition.text_control or "",
            page_index = tonumber(definition.page_index) or -1,
            active = active,
            enabled = true,
            badge_count = badge_count
        })
    end

    return result
end

function ViewModel.build(snapshot, panel)
    snapshot = table_or_empty(snapshot)
    panel = table_or_empty(panel)
    local player = table_or_empty(snapshot.player)
    local guild = table_or_empty(snapshot.guild)

    local active_tab = text(panel.active_tab)
    if active_tab == "" then active_tab = Contract.DEFAULT_TAB end

    local selected_guild = text(panel.selected_guild)
    local schema_version = tonumber(snapshot.schema_version) or 0
    local panel_error = text(panel.error)
    local clan = clan_view(snapshot)
    local action_transport_ready = panel.action_transport_ready == true
    local relation_data = relation_views(
        snapshot,
        selected_guild,
        action_transport_ready
    )
    local guilds = guild_catalog_view(snapshot)
    local chat = chat_view(panel.chat)
    local views = {
        CLAN = clan,
        DIPLOMACY = relation_data.diplomacy,
        ALLIANCE = relation_data.alliance,
        GUILDS = guilds,
        CHAT = chat
    }

    return {
        schema_version = schema_version,
        generated_at = tonumber(snapshot.generated_at) or 0,
        open = panel.open == true,
        active_tab = active_tab,
        selected_guild = selected_guild,
        error = panel_error,
        connection = {
            ready = schema_version > 0 and panel_error == "",
            status_text = panel_error ~= "" and panel_error
                or (schema_version > 0
                    and "Sunucu snapshoti hazir"
                    or "Sunucu baglantisi bekleniyor")
        },
        header = {
            guild_text = text(guild.name) ~= ""
                and "Klan: " .. text(guild.name) or "Klan: -",
            role_text = schema_version == 0 and "Yetki: -"
                or (player.is_master == true
                    and "Yetki: Lider" or "Yetki: Uye"),
            notification_text = string.format(
                "Bildirim: %d",
                tonumber(clan.pending_count) or 0
            )
        },
        capabilities = {
            action_transport_ready = action_transport_ready,
            action_transport_status_text = action_transport_status(
                action_transport_ready
            )
        },
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
            GUILDS = guilds.active_count
        }),
        views = views,
        content = views[active_tab] or views[Contract.DEFAULT_TAB]
    }
end

return ViewModel
