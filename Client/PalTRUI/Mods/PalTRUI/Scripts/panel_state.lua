local Contract = require("contract")

local PanelState = {}
PanelState.__index = PanelState

function PanelState.new()
    return setmetatable({
        open = false,
        active_tab = Contract.DEFAULT_TAB,
        selected_guild = "",
        snapshot = nil,
        error = ""
    }, PanelState)
end

function PanelState:toggle()
    self.open = not self.open
    return self.open
end

function PanelState:set_tab(tab_id)
    for _, tab in ipairs(Contract.TABS) do
        if tab.id == tab_id then
            self.active_tab = tab_id
            self.error = ""
            return true
        end
    end
    self.error = "Geçersiz panel sekmesi."
    return false
end

function PanelState:apply_snapshot(snapshot)
    if not Contract.accepts(snapshot) then
        self.error = "Sunucu UI veri sürümü uyumsuz."
        return false
    end
    self.snapshot = snapshot
    self.error = ""
    if self.selected_guild == "" and snapshot.relations and #snapshot.relations > 0 then
        self.selected_guild = snapshot.relations[1].guild_key or ""
    end
    return true
end

function PanelState:select_guild(guild_key)
    self.selected_guild = tostring(guild_key or "")
end

return PanelState
