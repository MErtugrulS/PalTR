local GuildIdentityModel = {}

local palette = {
    { id = "azure", hex = "#2475D8" },
    { id = "cyan", hex = "#18BBD1" },
    { id = "teal", hex = "#168E83" },
    { id = "green", hex = "#278A4C" },
    { id = "lime", hex = "#72A83B" },
    { id = "gold", hex = "#C49A32" },
    { id = "amber", hex = "#D17C22" },
    { id = "orange", hex = "#CB5727" },
    { id = "red", hex = "#BE3535" },
    { id = "crimson", hex = "#8F2943" },
    { id = "magenta", hex = "#B13E86" },
    { id = "purple", hex = "#7542A7" },
    { id = "violet", hex = "#574AA8" },
    { id = "steel", hex = "#526F83" },
    { id = "ivory", hex = "#B8AD8F" },
    { id = "rose", hex = "#B65F70" }
}

local emblem_order = {
    "wolf", "eagle", "stag", "lion", "raven", "serpent",
    "bear", "boar", "dragon", "sun", "moon", "tower"
}

local function table_or_empty(value)
    return type(value) == "table" and value or {}
end

local function text(value)
    return value == nil and "" or tostring(value)
end

local function safe_id(value)
    local candidate = text(value)
    if candidate == "" or #candidate > 32
        or candidate:find("[^a-z0-9_%-]") then
        return ""
    end
    return candidate
end

local function selected_id(snapshot_value, draft_value)
    local draft = safe_id(draft_value)
    if draft ~= "" then return draft end
    return safe_id(snapshot_value)
end

function GuildIdentityModel.build(snapshot, panel)
    snapshot = table_or_empty(snapshot)
    panel = table_or_empty(panel)
    local source = table_or_empty(snapshot.guild_identity)
    local colors = {}
    local locked = source.locked == true
    local can_manage = source.can_manage == true
    local selected_color = selected_id(
        source.selected_color_id,
        locked and "" or panel.guild_identity_color_id
    )
    local selected_emblem = selected_id(
        source.selected_emblem_id,
        locked and "" or panel.guild_identity_emblem_id
    )
    local pending = text(panel.action_status) ~= ""

    local colors_by_id = {}
    for _, item in ipairs(table_or_empty(source.colors)) do
        item = table_or_empty(item)
        local id = safe_id(item.id)
        if id ~= "" then colors_by_id[id] = item end
    end
    for index, definition in ipairs(palette) do
        local item = colors_by_id[definition.id]
        if item ~= nil then
            colors[index] = {
                index = index,
                id = definition.id,
                hex = text(item.hex) ~= "" and text(item.hex) or definition.hex,
                available = item.available == true
                    or definition.id == selected_color,
                selected = definition.id == selected_color
            }
        end
    end

    local emblems = {}
    local emblems_by_id = {}
    for _, item in ipairs(table_or_empty(source.emblems)) do
        item = table_or_empty(item)
        local id = safe_id(item.id)
        if id ~= "" then emblems_by_id[id] = item end
    end
    for index, id in ipairs(emblem_order) do
        local item = emblems_by_id[id]
        if item ~= nil then
            emblems[index] = {
                index = index,
                id = id,
                name = text(item.name) ~= "" and text(item.name) or id,
                selected = id == selected_emblem
            }
        end
    end

    local ready = can_manage and not locked and not pending
        and selected_color ~= "" and selected_emblem ~= ""
    local selected_color_available = false
    for index = 1, #palette do
        local color = colors[index]
        if color ~= nil
            and color.id == selected_color and color.available then
            selected_color_available = true
            break
        end
    end
    ready = ready and selected_color_available

    local reason = ""
    if pending then
        reason = "Sunucu sonucu bekleniyor."
    elseif locked then
        reason = "Klan kimliği kaydedildi ve bu sürümde kilitli."
    elseif not can_manage then
        reason = "Bu işlem için lider, yardımcı lider veya komutan yetkisi gerekir."
    elseif selected_color == "" or selected_emblem == "" then
        reason = "Kaydetmek için bir renk ve arma seçin."
    elseif not selected_color_available then
        reason = "Seçilen renk artık kullanılamıyor; başka bir renk seçin."
    end

    return {
        palette_version = tonumber(source.palette_version) or 0,
        colors = colors,
        emblems = emblems,
        selected_color_id = selected_color,
        selected_emblem_id = selected_emblem,
        locked = locked,
        can_manage = can_manage,
        read_only = locked or not can_manage,
        save_control = {
            action_id = "SET_GUILD_IDENTITY",
            enabled = ready,
            reason = reason,
            label = locked and "Klan Kimliği Kaydedildi" or "Kimliği Kaydet"
        },
        status_text = reason ~= "" and reason
            or "Seçiminiz sunucuda tek işlem olarak kaydedilecek."
    }
end

return GuildIdentityModel
