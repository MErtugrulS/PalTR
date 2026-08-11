local Identity = {}

function Identity.guild_for_model(ue, registry, group_id, model)
    local guild = registry:find_guild_by_id(ue.guid(group_id))
    if guild then return guild end

    local ok_builder, builder_uid = ue.call(model, "GetBuildPlayerUId_BP")
    if not ok_builder then return nil end

    local builder = registry:find_by_uid(ue.guid(builder_uid))
    local guild_key = builder and tostring(builder.guild_key or "") or ""
    if guild_key == "" then return nil end

    return registry.guilds[guild_key] or { key = guild_key }
end

return Identity
