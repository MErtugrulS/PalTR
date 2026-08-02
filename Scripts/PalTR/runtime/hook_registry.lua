local HookRegistry = {}
HookRegistry.__index = HookRegistry

function HookRegistry.new(logger)
    return setmetatable({ logger = logger, hooks = {} }, HookRegistry)
end

function HookRegistry:register(name, path, callback)
    if self.hooks[path] then return true end

    local ok, pre_id, post_id = pcall(RegisterHook, path, callback)
    if not ok or (pre_id == nil and post_id == nil) then
        self.logger:warn("Hook kaydedilemedi: " .. name .. " | " .. path)
        return false
    end

    self.hooks[path] = {
        name = name,
        pre_id = pre_id,
        post_id = post_id
    }
    self.logger:info("Hook hazir: " .. name)
    return true
end

return HookRegistry
