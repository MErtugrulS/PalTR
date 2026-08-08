local ActionIntent = {}

local function text(value)
    if value == nil then return "" end
    return tostring(value)
end

function ActionIntent.build(model, action_id)
    if type(model) ~= "table" then
        return nil, "Gorunum modeli bulunamadi."
    end

    local views = type(model.views) == "table" and model.views or {}
    local diplomacy = views.DIPLOMACY
    local relation = diplomacy and diplomacy.selected_relation
    if type(relation) ~= "table" then
        return nil, "Diplomasi kaydi secilmedi."
    end

    local requested_id = text(action_id)
    if requested_id == "" then
        return nil, "Diplomasi aksiyonu secilmedi."
    end

    local permissions = relation.permissions or {}
    if permissions.can_manage ~= true then
        return nil, text(permissions.reason) ~= ""
            and text(permissions.reason)
            or "Diplomasi aksiyonu kullanilamaz."
    end

    local guild_key = text(relation.guild and relation.guild.key)
    if guild_key == "" then
        return nil, "Diplomasi klan kimligi bulunamadi."
    end

    for _, action in ipairs(relation.actions or {}) do
        if type(action) == "table"
            and text(action.id) == requested_id then
            return {
                kind = "DIPLOMACY_ACTION",
                guild_key = guild_key,
                action_id = requested_id,
                snapshot_generated_at = tonumber(model.generated_at) or 0
            }
        end
    end

    return nil, "Aksiyon guncel sunucu snapshotinda sunulmuyor."
end

return ActionIntent
