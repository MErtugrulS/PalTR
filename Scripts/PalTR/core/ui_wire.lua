local Wire = {}

Wire.VERSION = 1
Wire.PREFIX = "PALTRUI1"

local function encode_component(value)
    local encoded = tostring(value or ""):gsub(
        "([^%w%-%._~])",
        function(character)
            return string.format("%%%02X", string.byte(character))
        end
    )
    return encoded
end

local function decode_component(value)
    local index = 1

    while true do
        local position = value:find("%", index, true)
        if position == nil then break end

        local encoded = value:sub(position + 1, position + 2)
        if #encoded ~= 2 or not encoded:match("^%x%x$") then
            return nil
        end

        index = position + 3
    end

    local decoded = value:gsub("%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end)
    return decoded
end

function Wire.encode(kind, request_id, payload)
    return table.concat({
        Wire.PREFIX,
        encode_component(kind),
        encode_component(request_id),
        encode_component(payload)
    }, "|")
end

function Wire.decode(message)
    if type(message) ~= "string" then return nil end

    local prefix, encoded_kind, encoded_request, encoded_payload =
        message:match("^([^|]*)|([^|]*)|([^|]*)|([^|]*)$")

    if prefix ~= Wire.PREFIX then return nil end

    local kind = decode_component(encoded_kind)
    local request_id = decode_component(encoded_request)
    local payload = decode_component(encoded_payload)

    if kind == nil or kind == ""
        or request_id == nil
        or payload == nil then
        return nil
    end

    return {
        version = Wire.VERSION,
        kind = kind,
        request_id = request_id,
        payload = payload
    }
end

return Wire
