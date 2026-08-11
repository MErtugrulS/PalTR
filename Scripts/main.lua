local function current_directory()
    local source = debug.getinfo(1, "S").source or ""
    if source:sub(1, 1) == "@" then source = source:sub(2) end
    return source:match("^(.*[\\/])") or "./"
end

local root = current_directory()
package.path = root .. "?.lua;" .. root .. "?/init.lua;" .. package.path

local ok, bootstrap = pcall(require, "PalTR.bootstrap")
if not ok then
    print("[PalTR] BASLATMA_HATASI | " .. tostring(bootstrap))
    return
end

local started, error_message = pcall(bootstrap.start)
if not started then
    print("[PalTR] BASLATMA_HATASI | " .. tostring(error_message))
end
