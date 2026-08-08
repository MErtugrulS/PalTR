local UIWire = require("ui_wire")

local function equal(actual, expected, label)
    if actual ~= expected then
        error(string.format(
            "%s | expected=%s actual=%s",
            label,
            tostring(expected),
            tostring(actual)
        ))
    end
end

local payload = "PalTR Türkçe | yüzde % | satır\niki"
local encoded = UIWire.encode("PROBE", "manual", payload)
local decoded = UIWire.decode(encoded)

equal(decoded.version, 1, "wire version")
equal(decoded.kind, "PROBE", "wire kind")
equal(decoded.request_id, "manual", "wire request id")
equal(decoded.payload, payload, "wire payload round trip")
equal(UIWire.decode("normal chat"), nil, "unrelated chat")
equal(UIWire.decode("PALTRUI1|PROBE|manual|bad%2"), nil, "invalid escape")
equal(UIWire.decode("PALTRUI1||manual|payload"), nil, "empty kind")

print("PALTR_UI_WIRE_TEST_OK")
