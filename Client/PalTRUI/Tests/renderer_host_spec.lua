local RendererHost = require("renderer_host")

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

local calls = {}
local port = {
    open = function(_, model)
        table.insert(calls, { name = "open", model = model })
        return true
    end,
    update = function(_, model)
        table.insert(calls, { name = "update", model = model })
        return true
    end,
    close = function()
        table.insert(calls, { name = "close" })
        return true
    end
}

local host = RendererHost.new(port)
equal(host:available(), true, "renderer port available")

local closed_model = { open = false, active_tab = "CLAN" }
equal(host:render(closed_model), true, "initial closed model accepted")
equal(#calls, 0, "closed model does not create widget")

local open_model = { open = true, active_tab = "CLAN" }
equal(host:render(open_model), true, "open model rendered")
equal(calls[1].name, "open", "widget opened first")
equal(calls[1].model, open_model, "open receives view model")
equal(calls[2].name, "update", "widget updated after open")

local diplomacy_model = { open = true, active_tab = "DIPLOMACY" }
equal(host:render(diplomacy_model), true, "updated model rendered")
equal(#calls, 3, "open widget is reused")
equal(calls[3].name, "update", "existing widget updated")
equal(calls[3].model, diplomacy_model, "update receives view model")

equal(host:render(closed_model), true, "close model rendered")
equal(calls[4].name, "close", "widget closed")

local unavailable = RendererHost.new()
local rendered, render_error = unavailable:render(open_model)
equal(rendered, false, "missing widget port rejected")
equal(render_error, "UMG widget portu hazir degil.", "missing port error")

print("PALTR_UI_RENDERER_HOST_TEST_OK")
