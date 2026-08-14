local Bridge = {}
Bridge.__index = Bridge

local CLASS_PATH = "/Game/Mods/PalTRUI/WBP_PalTRPanel_DesignTemplate.WBP_PalTRPanel_DesignTemplate_C:"

PalTRUIDesignEventCallbacks = PalTRUIDesignEventCallbacks or {}
PalTRUIDesignEventState = PalTRUIDesignEventState or {
    registered = false,
    busy = false
}

local function boolean_value(value)
    if type(value) == "boolean" then return value end
    local ok, result = pcall(function() return value:get() end)
    if ok and type(result) == "boolean" then return result end
    return nil
end

local function first_boolean(...)
    for index = 1, select("#", ...) do
        local value = boolean_value(select(index, ...))
        if value ~= nil then return value end
    end
    return nil
end

function Bridge.new(router, options)
    options = type(options) == "table" and options or {}
    return setmetatable({
        router = router,
        register_hook = options.register_hook or RegisterHook,
        execute = options.execute or ExecuteInGameThread,
        callbacks = options.callbacks or PalTRUIDesignEventCallbacks,
        state = options.state or PalTRUIDesignEventState
    }, Bridge)
end

function Bridge:_route(control)
    if self.state.busy == true then return end
    self.state.busy = true
    local function run()
        local ok, handled, model, _, route_error = pcall(function()
            return self.router:handle(control)
        end)
        self.state.busy = false
        local error_text = ok == true
            and tostring(route_error or "") or tostring(handled or "")
        print(string.format(
            "[PalTRUI] PALTR_UI_EVENT_%s | control=%s | tab=%s | error=%s\n",
            ok and handled == true and "OK" or "ERROR",
            tostring(control),
            tostring(model and model.active_tab or ""),
            error_text
        ))
    end
    if type(self.execute) == "function" then self.execute(run) else run() end
end

function Bridge:register()
    if self.state.registered == true then return true end
    if type(self.register_hook) ~= "function" then
        return false, "UE4SS RegisterHook API hazir degil."
    end
    local definitions = {
        PalTR_HomeClicked = { control = "ClanTabButton" },
        PalTR_DiplomacyClicked = { control = "DiplomacyTabButton" },
        PalTR_OpenDiplomacyClicked = { control = "DashboardDiplomacyButton" },
        PalTR_DiplomacyAllianceClicked = { control = "AllianceRequestButton" },
        PalTR_DiplomacyWarClicked = { control = "WarRequestButton" },
        PalTR_DiplomacyAcceptClicked = { control = "AcceptButton" },
        PalTR_DiplomacyRejectClicked = { control = "RejectButton" },
        PalTR_DiplomacyCancelClicked = { control = "CancelButton" },
        PalTR_DiplomacyRelation01Clicked = { control = "DiplomacyRelationRowButton01" },
        PalTR_DiplomacyRelation02Clicked = { control = "DiplomacyRelationRowButton02" },
        PalTR_DiplomacyRelation03Clicked = { control = "DiplomacyRelationRowButton03" },
        PalTR_DiplomacyRelation04Clicked = { control = "DiplomacyRelationRowButton04" },
        PalTR_DiplomacyRelation05Clicked = { control = "DiplomacyRelationRowButton05" },
        PalTR_DiplomacyRelation06Clicked = { control = "DiplomacyRelationRowButton06" }
    }
    for function_name, definition in pairs(definitions) do
        self.callbacks[function_name] = function()
            self:_route(definition.control)
        end
        local ok, register_error = pcall(
            self.register_hook,
            CLASS_PATH .. function_name,
            self.callbacks[function_name]
        )
        if not ok then return false, tostring(register_error) end
    end
    self.callbacks.PalTR_HomeChanged = function(...)
        if first_boolean(...) == true then self:_route("ClanTabButton") end
    end
    local home_ok, home_error = pcall(
        self.register_hook,
        CLASS_PATH .. "PalTR_HomeChanged",
        self.callbacks.PalTR_HomeChanged
    )
    if not home_ok then return false, tostring(home_error) end
    self.callbacks.PalTR_DiplomacyChanged = function(...)
        if first_boolean(...) == true then self:_route("DiplomacyTabButton") end
    end
    local diplomacy_ok, diplomacy_error = pcall(
        self.register_hook,
        CLASS_PATH .. "PalTR_DiplomacyChanged",
        self.callbacks.PalTR_DiplomacyChanged
    )
    if not diplomacy_ok then return false, tostring(diplomacy_error) end
    self.state.registered = true
    return true
end

return Bridge
