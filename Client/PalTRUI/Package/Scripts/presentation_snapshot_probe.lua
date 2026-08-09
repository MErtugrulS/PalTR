local PresentationSnapshotProbe = {}

function PresentationSnapshotProbe.is_active(model)
    local player = type(model) == "table" and model.player or nil
    return type(player) == "table"
        and tostring(player.guild_key or "") == "probe-own"
        and tonumber(model.generated_at) == 1000
end

function PresentationSnapshotProbe.build()
    return {
        schema_version = 1,
        generated_at = 1000,
        player = {
            name = "Ada",
            guild_key = "probe-own",
            role = 1,
            is_master = true
        },
        guild = {
            key = "probe-own",
            name = "Anka"
        },
        members = {
            {
                key = "probe-player-1",
                name = "Ada",
                role = 1,
                is_master = true,
                online = true
            },
            {
                key = "probe-player-2",
                name = "Bora",
                role = 0,
                is_master = false,
                online = false
            }
        },
        guilds = {
            {
                key = "probe-active",
                name = "Gezginler",
                member_count = 4,
                online_count = 2,
                active = true
            }
        },
        relations = {
            {
                guild_key = "probe-alliance",
                guild_name = "Müttefikler",
                state = "ALLIANCE",
                previous_state = "NEUTRAL",
                proposal_direction = "none",
                can_manage = true,
                action_reason = "",
                actions = {}
            },
            {
                guild_key = "probe-neutral",
                guild_name = "Tarafsızlar",
                state = "NEUTRAL",
                previous_state = "NEUTRAL",
                proposal_direction = "none",
                note = "Yerel sunum probu",
                can_manage = true,
                action_reason = "",
                actions = {
                    { id = "DECLARE_WAR", label = "Savaş İlan Et" },
                    { id = "ALLIANCE", label = "İttifak Teklif Et" }
                }
            }
        }
    }
end

function PresentationSnapshotProbe.apply(controller, snapshot_inbox)
    if type(controller) ~= "table"
        or type(controller.select_guild) ~= "function"
        or type(controller.set_tab) ~= "function"
        or type(snapshot_inbox) ~= "table"
        or type(snapshot_inbox.receive) ~= "function" then
        return false, nil, "UI sunum controller'i hazir degil."
    end

    local accepted, snapshot_model, snapshot_rendered, snapshot_error =
        snapshot_inbox:receive(PresentationSnapshotProbe.build())
    if accepted ~= true or snapshot_rendered ~= true then
        return false, snapshot_model,
            snapshot_error or "Sunum probe snapshoti reddedildi."
    end

    local selected, selection_model, selection_rendered, selection_error =
        controller:select_guild("probe-neutral")
    if selected ~= true or selection_rendered ~= true then
        return false, selection_model,
            selection_error or "Probe iliski kaydi secilemedi."
    end
    local tab_accepted, model, rendered, render_error =
        controller:set_tab("DIPLOMACY")
    if tab_accepted ~= true or rendered ~= true then
        return false, model, render_error or "Probe sekmesi acilamadi."
    end
    return true, model
end

function PresentationSnapshotProbe.select_next(controller)
    if type(controller) ~= "table"
        or type(controller.model) ~= "function"
        or type(controller.select_guild) ~= "function" then
        return false, nil, "UI sunum controller'i hazir degil."
    end

    local model = controller:model()
    local views = type(model) == "table" and model.views or nil
    local diplomacy = type(views) == "table" and views.DIPLOMACY or nil
    local relations = type(diplomacy) == "table"
        and diplomacy.relations or nil
    if type(relations) ~= "table" or #relations == 0 then
        return false, model, "Secilebilir diplomasi kaydi bulunamadi."
    end

    local selected_guild = tostring(model.selected_guild or "")
    local next_index = 1
    for index, relation in ipairs(relations) do
        local guild = type(relation) == "table" and relation.guild or nil
        if type(guild) == "table"
            and tostring(guild.key or "") == selected_guild then
            next_index = index % #relations + 1
            break
        end
    end

    local next_relation = relations[next_index]
    local next_guild = type(next_relation) == "table"
        and next_relation.guild or nil
    local guild_key = type(next_guild) == "table"
        and tostring(next_guild.key or "") or ""
    local accepted, selected_model, rendered, selection_error =
        controller:select_guild(guild_key)
    if accepted ~= true or rendered ~= true then
        return false, selected_model,
            selection_error or "Probe iliski kaydi secilemedi."
    end
    return true, selected_model
end

return PresentationSnapshotProbe
