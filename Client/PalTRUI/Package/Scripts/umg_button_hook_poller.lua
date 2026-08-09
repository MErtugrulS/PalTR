local UMGButtonStateProbe = require("umg_button_state_probe")

local UMGButtonHookPoller = {}
UMGButtonHookPoller.__index = UMGButtonHookPoller

UMGButtonHookPoller.HOOK_PATH = "/Script/Pal.PalHUDInGame:TickWorldHUDs"

function UMGButtonHookPoller.new(options)
    options = type(options) == "table" and options or {}
    return setmetatable({
        widget_provider = options.widget_provider,
        router = options.router,
        control_names = options.control_names or {},
        sampler = options.sampler or UMGButtonStateProbe,
        register_hook = options.register_hook or RegisterHook,
        now = options.now or os.time,
        on_result = options.on_result,
        on_resume = options.on_resume,
        resume_after_seconds = tonumber(options.resume_after_seconds) or 2,
        active = false,
        registered = false,
        hook_callback = nil,
        pre_hook_id = nil,
        post_hook_id = nil,
        last_tick_at = nil,
        previous = {}
    }, UMGButtonHookPoller)
end

function UMGButtonHookPoller:poll_once()
    if type(self.widget_provider) ~= "function" then
        return false, "PalTR panel saglayicisi hazir degil."
    end
    local sampled, states, sample_error = self.sampler.sample(
        self.widget_provider(),
        self.control_names
    )
    if sampled ~= true then return false, sample_error end

    for _, state in ipairs(states) do
        local name = tostring(state.control or "")
        local was_pressed = self.previous[name] == true
        local released_over_control = was_pressed
            and state.pressed ~= true
            and state.hovered_available == true
            and state.hovered == true
        self.previous[name] = state.pressed == true
        if released_over_control then
            local handled, model, _, interaction_error =
                self.router:handle(name)
            if type(self.on_result) == "function" then
                self.on_result(name, handled, model, interaction_error)
            end
            if type(model) == "table" and model.open == false then
                self:stop()
            end
        end
    end
    return true
end

function UMGButtonHookPoller:_tick()
    if not self.active then return end
    local current = tonumber(self.now()) or 0
    local delayed = self.last_tick_at ~= nil
        and current - self.last_tick_at >= self.resume_after_seconds
    self.last_tick_at = current
    if delayed and type(self.on_resume) == "function" then
        self.on_resume(current)
    end
    self:poll_once()
end

function UMGButtonHookPoller:start()
    if type(self.router) ~= "table"
        or type(self.router.handle) ~= "function" then
        return false, "UI etkilesim router'i hazir degil."
    end
    if not self.registered then
        if type(self.register_hook) ~= "function" then
            return false, "UE4SS RegisterHook API hazir degil."
        end
        self.hook_callback = function()
            self:_tick()
        end
        local hooked, pre_id, post_id = pcall(
            self.register_hook,
            UMGButtonHookPoller.HOOK_PATH,
            self.hook_callback
        )
        if not hooked then
            self.hook_callback = nil
            return false, tostring(pre_id)
        end
        self.registered = true
        self.pre_hook_id = pre_id
        self.post_hook_id = post_id
    end
    self.active = true
    self.last_tick_at = tonumber(self.now()) or 0
    self.previous = {}
    return true
end

function UMGButtonHookPoller:stop()
    self.active = false
    self.last_tick_at = nil
    self.previous = {}
end

return UMGButtonHookPoller
