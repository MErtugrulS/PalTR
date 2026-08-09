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

local function relation_matches_tab(relation, tab_id)
    if tab_id ~= "ALLIANCE" then return true end
    local state = tostring(relation.state or "")
    return state == "ALLIANCE" or state == "ALLIANCE_PENDING"
end

local function relation_exists(relations, guild_key, tab_id)
    for _, relation in ipairs(relations or {}) do
        if type(relation) == "table"
            and tostring(relation.guild_key or "") == guild_key
            and relation_matches_tab(relation, tab_id) then
            return true
        end
    end
    return false
end

local function first_relation_key(relations, tab_id)
    for _, relation in ipairs(relations or {}) do
        if type(relation) == "table"
            and relation_matches_tab(relation, tab_id) then
            return tostring(relation.guild_key or "")
        end
    end
    return ""
end

function PanelState:_normalize_relation_selection()
    local relations = self.snapshot and self.snapshot.relations or {}
    if not relation_exists(
        relations,
        self.selected_guild,
        self.active_tab
    ) then
        self.selected_guild = first_relation_key(
            relations,
            self.active_tab
        )
    end
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
            self:_normalize_relation_selection()
            self:_rebuild_view_model()
            return true
        end
    end
    self.error = "Geçersiz panel sekmesi."
    self:_rebuild_view_model()
    return false
end

function PanelState:apply_snapshot(snapshot)
    local accepted, contract_error = Contract.validate(snapshot)
    if not accepted then
        self.error = contract_error == "schema_version"
            and "Sunucu UI veri sürümü uyumsuz."
            or "Sunucu UI verisi geçersiz: " .. tostring(contract_error)
        self:_rebuild_view_model()
        return false
    end
    self.snapshot = snapshot
    self.error = ""
    self:_normalize_relation_selection()
    self:_rebuild_view_model()
    return true
end

function PanelState:select_guild(guild_key)
    local requested = tostring(guild_key or "")
    local relations = self.snapshot and self.snapshot.relations or {}
    if not relation_exists(relations, requested, self.active_tab) then
        self.error = "Seçilen klan bu sekmede bulunamadı."
        self:_rebuild_view_model()
        return false
    end
    self.selected_guild = requested
    self.error = ""
    self:_rebuild_view_model()
    return true
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
