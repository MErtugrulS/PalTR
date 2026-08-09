local UMGViewBinder = require("umg_view_binder")

local function equal(actual, expected, label)
    if actual ~= expected then
        error(string.format(
            "%s | expected=%s actual=%s",
            label,
            tostring(expected),
            tostring(actual)
        ))
    end
end

local function widget(name, children)
    local item = {
        name = name,
        children = children or {},
        GetFName = function(self)
            return { ToString = function() return self.name end }
        end,
        GetChildrenCount = function(self)
            return #self.children
        end,
        GetChildAt = function(self, index)
            return self.children[index + 1]
        end
    }
    return item
end

local text_values = {}
local function text_widget(name)
    local item = widget(name)
    item.SetText = function(_, value)
        text_values[name] = value
    end
    return item
end

local switch_index = nil
local switcher = widget("ContentSwitcher")
switcher.SetActiveWidgetIndex = function(_, index)
    switch_index = index
end

local names = {
    "TitleText",
    "ConnectionStatusText",
    "ClanNameText",
    "ClanSummaryText",
    "ClanMembersText",
    "RelationListEmptyText",
    "RelationTitleText",
    "RelationStateText",
    "RelationDescriptionText",
    "AllianceSummaryText",
    "AllianceMembersText",
    "ChatEmptyText"
}
local controls = { switcher }
for _, name in ipairs(names) do
    table.insert(controls, text_widget(name))
end
local root = widget("RootCanvas", {
    widget("PanelBackground", controls)
})
local panel = {
    WidgetTree = { RootWidget = root }
}

local binder = UMGViewBinder.new({
    make_text = function(value) return value end
})
local model = {
    schema_version = 1,
    active_tab = "DIPLOMACY",
    error = "",
    views = {
        CLAN = {
            guild = { name = "Anka" },
            member_count = 2,
            online_count = 1,
            empty = false,
            members = {
                { name = "Ada", online = true },
                { name = "Bora", online = false }
            }
        },
        DIPLOMACY = {
            empty = false,
            relations = {
                {
                    guild = { name = "Rakipler" },
                    status = { label = "Savas" }
                }
            },
            selected_relation = {
                guild = { name = "Rakipler" },
                status = {
                    label = "Savas",
                    proposal_direction_label = "",
                    note = "Sinir catismasi"
                },
                permissions = { reason = "" }
            }
        },
        ALLIANCE = {
            empty = true,
            empty_message = "Ittifak yok.",
            relations = {}
        },
        CHAT = {
            empty = false,
            messages = {
                { sender = "Ada", text = "Merhaba" }
            }
        }
    }
}

local bound, bind_error = binder:bind(panel, model)
equal(bound, true, "view model bound")
equal(bind_error, nil, "successful bind has no error")
equal(switch_index, 1, "diplomacy tab selected")
equal(text_values.ConnectionStatusText, "Sunucu snapshoti hazir", "status")
equal(text_values.ClanNameText, "Anka", "clan name")
equal(text_values.ClanSummaryText, "2 uye | 1 cevrimici", "clan summary")
equal(text_values.ClanMembersText, "Ada (cevrimici)\nBora", "members")
equal(text_values.RelationListEmptyText, "Rakipler | Savas", "relations")
equal(text_values.RelationTitleText, "Rakipler", "selected guild")
equal(text_values.RelationStateText, "Savas", "relation state")
equal(text_values.RelationDescriptionText, "Sinir catismasi", "relation detail")
equal(text_values.AllianceMembersText, "Ittifak yok.", "empty alliance")
equal(text_values.ChatEmptyText, "Ada: Merhaba", "chat messages")

local converted_values = {}
local fallback_binder = UMGViewBinder.new({
    get_text_library = function()
        return {
            Conv_StringToText = function(_, value)
                table.insert(converted_values, value)
                return "FText:" .. value
            end
        }
    end
})
local fallback_bound, fallback_error = fallback_binder:bind(panel, model)
equal(fallback_bound, true, "Kismet text fallback bound")
equal(fallback_error, nil, "Kismet text fallback has no error")
equal(#converted_values > 0, true, "Kismet text fallback used")
equal(
    text_values.ClanNameText,
    "FText:Anka",
    "Kismet text fallback result passed to widget"
)

local invalid_model, model_error = binder:bind(panel, nil)
equal(invalid_model, false, "missing model rejected")
equal(model_error, "Gorunum modeli bulunamadi.", "model error")

local missing_tree, tree_error = binder:bind({}, model)
equal(missing_tree, false, "missing tree rejected")
equal(tree_error, "PalTR widget agaci bulunamadi.", "tree error")

local missing_control_panel = {
    WidgetTree = { RootWidget = widget("RootCanvas", { switcher }) }
}
local controls_bound, controls_error = binder:bind(missing_control_panel, model)
equal(controls_bound, false, "missing text control rejected")
equal(controls_error, "UMG kontrolu bulunamadi: TitleText", "control error")

print("PALTR_UI_UMG_VIEW_BINDER_TEST_OK")
