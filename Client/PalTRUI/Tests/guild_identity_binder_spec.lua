local source = debug.getinfo(1, "S").source
local path = source:sub(1, 1) == "@" and source:sub(2) or source
local directory = path:gsub("\\", "/"):match("^(.*)/") or "."
package.path = directory .. "/../Package/Scripts/?.lua;" .. package.path

local UMGViewBinder = require("umg_view_binder")

local function equal(actual, expected, label)
    if actual ~= expected then
        error(string.format("%s | expected=%s actual=%s", label,
            tostring(expected), tostring(actual)))
    end
end

local function control()
    return {
        visible = nil,
        enabled = nil,
        text = nil,
        SetVisibility = function(self, value) self.visible = value end,
        SetIsEnabled = function(self, value) self.enabled = value end,
        SetText = function(self, value) self.text = value end,
        SetActiveWidgetIndex = function(self, value) self.index = value end
    }
end

local controls = {
    TemplatePanelBackground = control(),
    TemplatePageSwitcher = control(),
    PalTRSidebarManagementArrow = control(),
    GuildIdentityStatusText = control(),
    GuildIdentitySaveButton = control(),
    GuildIdentitySaveText = control()
}
for index = 1, 16 do
    controls[string.format("GuildIdentityColorButton%02d", index)] = control()
    controls[string.format("GuildIdentityColorText%02d", index)] = control()
end
for index = 1, 12 do
    controls[string.format("GuildIdentityEmblemButton%02d", index)] = control()
    controls[string.format("GuildIdentityEmblemText%02d", index)] = control()
end

local root = { GetChildrenCount = function() return 0 end }
local tree = {
    RootWidget = root,
    FindWidget = function(_, name) return controls[name] end
}
local panel = { WidgetTree = tree }
local binder = UMGViewBinder.new({ make_text = function(value) return value end })
local bound = binder:bind(panel, {
    active_tab = "MANAGEMENT",
    views = {
        CLAN = {}, DIPLOMACY = {}, MANAGEMENT = {
            read_only = false,
            colors = {
                { id = "azure", available = true, selected = true },
                { id = "cyan", available = false, selected = false }
            },
            emblems = {
                { id = "wolf", name = "Kurt", selected = true }
            },
            status_text = "Hazır",
            save_control = { enabled = true, label = "Kimliği Kaydet" }
        }
    },
    header = {}, connection = {}
})
equal(bound, true, "management design template bound")
equal(controls.TemplatePageSwitcher.index, 2, "management switcher page")
equal(controls.PalTRSidebarManagementArrow.visible, 3,
    "management arrow visible")
equal(controls.GuildIdentityColorButton01.enabled, true,
    "available color enabled")
equal(controls.GuildIdentityColorText01.text, "✓ azure",
    "selected color marked")
equal(controls.GuildIdentityColorButton02.enabled, false,
    "reserved color disabled")
equal(controls.GuildIdentityEmblemText01.text, "✓ Kurt",
    "selected emblem marked")
equal(controls.GuildIdentitySaveButton.enabled, true, "save enabled")

print("PALTR_UI_GUILD_IDENTITY_BINDER_TEST_OK")
