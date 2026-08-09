local UMGButtonStateProbe = require("umg_button_state_probe")

local UMGButtonPoller = {}
UMGButtonPoller.__index = UMGButtonPoller

function UMGButtonPoller.new(options)
    options = type(options) == "table" and options or {}
    return setmetatable({
        widget_provider = options.widget_provider,
        router = options.router,
        control_names = options.control_names or {},
        sampler = options.sampler or UMGButtonStateProbe,
        schedule_loop = options.schedule_loop or LoopAsync,
        execute_in_game_thread = options.execute_in_game_thread
            or ExecuteInGameThread,
        on_result = options.on_result,
        on_resume = options.on_resume,
        interval_ms = tonumber(options.interval_ms) or 16,
        resume_after_delayed_ticks = tonumber(
            options.resume_after_delayed_ticks
        ) or 8,
        pending_timeout_ticks = tonumber(options.pending_timeout_ticks) or 120,
        active = false,
        game_thread_pending = false,
        game_thread_callback = nil,
        pending_callbacks = {},
        generation_counter = 0,
        current_generation = nil,
        loop_callback = nil,
        delayed_ticks = 0,
        recovery_ticks = 0,
        previous = {}
    }, UMGButtonPoller)
end

function UMGButtonPoller:poll_once()
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

function UMGButtonPoller:start()
    if self.active then return true end
    if type(self.router) ~= "table"
        or type(self.router.handle) ~= "function" then
        return false, "UI etkilesim router'i hazir degil."
    end
    if type(self.schedule_loop) ~= "function"
        or type(self.execute_in_game_thread) ~= "function" then
        return false, "UE4SS button polling API hazir degil."
    end

    self.active = true
    self.game_thread_pending = false
    self.delayed_ticks = 0
    self.recovery_ticks = 0
    self.previous = {}
    self.loop_callback = function()
        if not self.active then return true end
        if self.game_thread_pending then
            self.delayed_ticks = self.delayed_ticks + 1
            if self.delayed_ticks >= self.pending_timeout_ticks then
                self.recovery_ticks = self.recovery_ticks
                    + self.delayed_ticks
                self.delayed_ticks = 0
                self.game_thread_pending = false
                self.game_thread_callback = nil
                self.current_generation = nil
            end
            return false
        end

        self.game_thread_pending = true
        self.generation_counter = self.generation_counter + 1
        local generation = self.generation_counter
        self.current_generation = generation
        local callback
        callback = function()
            self.pending_callbacks[generation] = nil
            if self.current_generation ~= generation then return end
            local delayed_ticks = self.delayed_ticks + self.recovery_ticks
            self.game_thread_pending = false
            self.game_thread_callback = nil
            self.current_generation = nil
            self.delayed_ticks = 0
            self.recovery_ticks = 0
            if not self.active then return end
            if delayed_ticks >= self.resume_after_delayed_ticks
                and type(self.on_resume) == "function" then
                self.on_resume(delayed_ticks)
            end
            self:poll_once()
        end
        self.game_thread_callback = callback
        self.pending_callbacks[generation] = callback
        local queued = pcall(
            self.execute_in_game_thread,
            self.game_thread_callback
        )
        if not queued and self.current_generation == generation then
            self.pending_callbacks[generation] = nil
            self.game_thread_pending = false
            self.game_thread_callback = nil
            self.current_generation = nil
            self.delayed_ticks = 0
            self.recovery_ticks = 0
        end
        return false
    end
    self.schedule_loop(self.interval_ms, self.loop_callback)
    return true
end

function UMGButtonPoller:stop()
    self.active = false
    self.game_thread_pending = false
    self.game_thread_callback = nil
    self.current_generation = nil
    self.loop_callback = nil
    self.delayed_ticks = 0
    self.recovery_ticks = 0
    self.previous = {}
end

return UMGButtonPoller
