local GuildIdentityModel = require("guild_identity_model")

local function equal(actual, expected, label)
    if actual ~= expected then
        error(string.format("%s | expected=%s actual=%s", label,
            tostring(expected), tostring(actual)))
    end
end

local model = GuildIdentityModel.build({
    guild_identity = {
        palette_version = 1,
        selected_color_id = "",
        selected_emblem_id = "",
        locked = false,
        can_manage = true,
        colors = {
            { id = "cyan", hex = "#18BBD1", available = false },
            { id = "azure", hex = "#2475D8", available = true }
        },
        emblems = {
            { id = "eagle", name = "Kartal" },
            { id = "wolf", name = "Kurt" }
        }
    }
}, {
    guild_identity_color_id = "azure",
    guild_identity_emblem_id = "wolf"
})
equal(model.colors[1].id, "azure", "palette uses canonical order")
equal(model.colors[2].id, "cyan", "server order cannot move controls")
equal(model.colors[2].available, false, "reserved color disabled")
equal(model.emblems[1].id, "wolf", "emblems use canonical order")
equal(model.selected_color_id, "azure", "draft color selected")
equal(model.selected_emblem_id, "wolf", "draft emblem selected")
equal(model.save_control.enabled, true, "complete editable draft enabled")

local locked = GuildIdentityModel.build({
    guild_identity = {
        selected_color_id = "cyan",
        selected_emblem_id = "eagle",
        locked = true,
        can_manage = true,
        colors = { { id = "cyan", available = false } },
        emblems = { { id = "eagle", name = "Kartal" } }
    }
}, {
    guild_identity_color_id = "azure",
    guild_identity_emblem_id = "wolf"
})
equal(locked.selected_color_id, "cyan", "locked identity uses persisted color")
equal(locked.read_only, true, "locked identity read only")
equal(locked.save_control.enabled, false, "locked identity cannot save")

local unauthorized = GuildIdentityModel.build({
    guild_identity = {
        locked = false,
        can_manage = false,
        colors = { { id = "azure", available = true } },
        emblems = { { id = "wolf", name = "Kurt" } }
    }
}, {})
equal(unauthorized.read_only, true, "unauthorized identity read only")
equal(unauthorized.status_text:find("yetkisi", 1, true) ~= nil, true,
    "unauthorized reason exposed")

print("PALTR_UI_GUILD_IDENTITY_MODEL_TEST_OK")
