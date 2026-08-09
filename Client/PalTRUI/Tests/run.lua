local source = debug.getinfo(1, "S").source
local path = source:sub(1, 1) == "@" and source:sub(2) or source
local directory = path:gsub("\\", "/"):match("^(.*)/") or "."

package.path = directory .. "/../Package/Scripts/?.lua;" .. package.path

dofile(directory .. "/view_model_spec.lua")
dofile(directory .. "/action_intent_spec.lua")
dofile(directory .. "/presentation_controller_spec.lua")
dofile(directory .. "/presentation_snapshot_probe_spec.lua")
dofile(directory .. "/renderer_host_spec.lua")
dofile(directory .. "/umg_asset_loader_spec.lua")
dofile(directory .. "/umg_context_spec.lua")
dofile(directory .. "/umg_widget_port_spec.lua")
dofile(directory .. "/umg_view_binder_spec.lua")
dofile(directory .. "/ui_interaction_router_spec.lua")
dofile(directory .. "/ui_wire_spec.lua")
