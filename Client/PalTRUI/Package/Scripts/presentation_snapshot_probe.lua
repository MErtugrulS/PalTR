local PresentationSnapshotProbe = {}

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

function PresentationSnapshotProbe.apply(controller)
    if type(controller) ~= "table"
        or type(controller.apply_snapshot) ~= "function"
        or type(controller.select_guild) ~= "function"
        or type(controller.set_tab) ~= "function" then
        return false, nil, "UI sunum controller'i hazir degil."
    end

    local accepted = controller:apply_snapshot(
        PresentationSnapshotProbe.build()
    )
    if accepted ~= true then
        return false, controller:model(), "Sunum probe snapshoti reddedildi."
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

return PresentationSnapshotProbe
