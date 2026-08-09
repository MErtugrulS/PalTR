local UIWire = require("ui_wire")

local Probe = {
    registered = false,
    pre_hook_id = nil,
    post_hook_id = nil,
    frame_handler = nil
}

local HOOK_PATH = "/Script/Pal.PalUIChat:OnReceivedChat"
local PRIVATE_PROBE_MARKER =
    "[FAZ-04] HEDEFLI SISTEM SOHBETI CALISIYOR"
local WIRE_PROBE_PAYLOAD =
    "PalTR Türkçe | yüzde % | satır\niki"

local function unwrap(value)
    if value == nil then return nil end
    local ok, result = pcall(function() return value:get() end)
    if ok and result ~= nil then return result end
    return value
end

local function read(value, field)
    value = unwrap(value)
    if value == nil then return nil end

    local direct_ok, direct_value = pcall(function()
        return value[field]
    end)
    if direct_ok and direct_value ~= nil then
        return unwrap(direct_value)
    end

    local getter_ok, getter_value = pcall(function()
        return value:GetPropertyValue(field)
    end)
    if getter_ok then return unwrap(getter_value) end
    return nil
end

local function text(value)
    value = unwrap(value)
    if value == nil then return "" end

    local kind = type(value)
    if kind == "string" or kind == "number" or kind == "boolean" then
        return tostring(value)
    end

    local ok, result = pcall(function() return value:ToString() end)
    if ok and result ~= nil then return tostring(result) end
    return tostring(value)
end

local function on_received_chat(_context, message_param)
    local message = text(read(message_param, "Message"))
    local category = text(read(message_param, "Category"))
    local sender = text(read(message_param, "Sender"))
    local marker_seen = message:find(
        PRIVATE_PROBE_MARKER,
        1,
        true
    ) ~= nil

    print(string.format(
        "[PalTRUI][CHAT] RECEIVE | category=%s | sender=%s | length=%d | private_probe_marker=%s\n",
        category,
        sender,
        #message,
        tostring(marker_seen)
    ))

    local frame = UIWire.decode(message)
    if frame ~= nil then
        print(string.format(
            "[PalTRUI][CHAT] WIRE_FRAME | kind=%s | request_id=%s | payload_length=%d\n",
            frame.kind,
            frame.request_id,
            #frame.payload
        ))

        if type(Probe.frame_handler) == "function" then
            local handled, handler_error = pcall(
                Probe.frame_handler,
                frame
            )
            if not handled then
                print(string.format(
                    "[PalTRUI][CHAT] WIRE_HANDLER_ERROR | %s\n",
                    tostring(handler_error)
                ))
            end
        end

        if frame.kind == "PROBE"
            and frame.request_id == "manual"
            and frame.payload == WIRE_PROBE_PAYLOAD then
            print("[PalTRUI][CHAT] WIRE_PROBE_OK\n")
        elseif frame.kind == "SIZE_PROBE" then
            local expected_size = tonumber(frame.request_id)
            local size_matches = expected_size ~= nil
                and #frame.payload == expected_size
                and frame.payload == string.rep("A", expected_size)

            print(string.format(
                "[PalTRUI][CHAT] WIRE_SIZE_PROBE | expected=%s | actual=%d | ok=%s\n",
                tostring(expected_size),
                #frame.payload,
                tostring(size_matches)
            ))
        end
    end
end

function Probe.register(frame_handler)
    if type(frame_handler) == "function" then
        Probe.frame_handler = frame_handler
    end
    if Probe.registered then
        print("[PalTRUI][CHAT] PROBE_ALREADY_REGISTERED\n")
        return true
    end

    if type(RegisterHook) ~= "function" then
        print("[PalTRUI][CHAT] PROBE_REGISTER_HOOK_UNAVAILABLE\n")
        return false
    end

    local ok, pre_id, post_id = pcall(
        RegisterHook,
        HOOK_PATH,
        on_received_chat
    )

    if not ok then
        print(string.format(
            "[PalTRUI][CHAT] PROBE_REGISTER_ERROR | %s\n",
            tostring(pre_id)
        ))
        return false
    end

    Probe.registered = true
    Probe.pre_hook_id = pre_id
    Probe.post_hook_id = post_id
    print(string.format(
        "[PalTRUI][CHAT] PROBE_REGISTERED | path=%s\n",
        HOOK_PATH
    ))
    return true
end

return Probe
