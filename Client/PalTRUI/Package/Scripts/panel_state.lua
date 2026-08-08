local Contract = require("contract")
local ViewModel = require("view_model")
local ChatState = require("chat_state")

local PanelState = {}
PanelState.__index = PanelState

function PanelState.new()
    local state = setmetatable({
        open = false,
        active_tab = Contract.DEFAULT_TAB,
        selected_guild = "",
        snapshot = nil,
        chat = ChatState.new(),
        view_model = nil,
        error = ""
    }, PanelState)
    state:_rebuild_view_model()
    return state
end

function PanelState:_rebuild_view_model()
    self.view_model = ViewModel.build(self.snapshot, self)
end

local function relation_exists(relations, guild_key)
    for _, relation in ipairs(relations or {}) do
        if type(relation) == "table"
            and tostring(relation.guild_key or "") == guild_key then
            return true
        end
    end
    return false
end

local function first_relation_key(relations)
    local relation = relations and relations[1]
    if type(relation) ~= "table" then return "" end
    return tostring(relation.guild_key or "")
end

function PanelState:toggle()
    self.open = not self.open
    self:_rebuild_view_model()
    return self.open
end

function PanelState:set_tab(tab_id)
    for _, tab in ipairs(Contract.TABS) do
        if tab.id == tab_id then
            self.active_tab = tab_id
            self.error = ""
            self:_rebuild_view_model()
            return true
        end
    end
    self.error = "Geçersiz panel sekmesi."
    self:_rebuild_view_model()
    return false
end

function PanelState:apply_snapshot(snapshot)
    if not Contract.accepts(snapshot) then
        self.error = "Sunucu UI veri sürümü uyumsuz."
        self:_rebuild_view_model()
        return false
    end
    self.snapshot = snapshot
    self.error = ""
    if not relation_exists(snapshot.relations, self.selected_guild) then
        self.selected_guild = first_relation_key(snapshot.relations)
    end
    self:_rebuild_view_model()
    return true
end

function PanelState:select_guild(guild_key)
    self.selected_guild = tostring(guild_key or "")
    self:_rebuild_view_model()
end

function PanelState:set_chat_available(available)
    self.chat:set_available(available)
    self:_rebuild_view_model()
end

function PanelState:replace_chat(messages)
    local accepted = self.chat:replace(messages)
    if accepted then self:_rebuild_view_model() end
    return accepted
end

function PanelState:append_chat(message)
    local accepted = self.chat:append(message)
    if accepted then self:_rebuild_view_model() end
    return accepted
end

function PanelState:clear_chat()
    self.chat:clear()
    self:_rebuild_view_model()
end

return PanelState
