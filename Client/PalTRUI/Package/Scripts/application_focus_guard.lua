local ApplicationFocusGuard = {}

ApplicationFocusGuard.HOOK_PATH =
    "/Script/Pal.PalHUDInGame:OnApplicationActivationStateChanged"

local retained_callback = nil
local registered = false

local function unwrap(value)
    if value == nil then return nil end
    local ok, result = pcall(function() return value:get() end)
    if ok then return result end
    return value
end

function ApplicationFocusGuard.register(options)
    options = type(options) == "table" and options or {}
    if registered then return true end
    local register_hook = options.register_hook or RegisterHook
    if type(register_hook) ~= "function" then
        return false, "UE4SS RegisterHook API bulunamadi."
    end

    retained_callback = function(_context, focused_param)
        local focused = unwrap(focused_param)
        if focused == false and type(options.on_focus_lost) == "function" then
            options.on_focus_lost()
        elseif focused == true
            and type(options.on_focus_gained) == "function" then
            options.on_focus_gained()
        end
    end

    local hooked, pre_id, post_id = pcall(
        register_hook,
        ApplicationFocusGuard.HOOK_PATH,
        retained_callback
    )
    if not hooked then
        retained_callback = nil
        return false, tostring(pre_id)
    end

    registered = true
    return true, { pre_id = pre_id, post_id = post_id }
end

return ApplicationFocusGuard
