local source = debug.getinfo(1, "S").source
local path = source:sub(1, 1) == "@" and source:sub(2) or source
local directory = path:gsub("\\", "/"):match("^(.*)/") or "."

package.path = directory .. "/../Package/Scripts/?.lua;" .. package.path

dofile(directory .. "/view_model_spec.lua")
dofile(directory .. "/ui_wire_spec.lua")
