local UE = require("PalTR.runtime.ue")
local Text = require("PalTR.core.text")
local FileIO = require("PalTR.storage.file_io")
local TSV = require("PalTR.storage.tsv")
local Clock = require("PalTR.core.clock")

local StructureProbe = {}

local function is_candidate(path)
    local lower = Text.lower_ascii(path)
    if not lower:find("/script/pal.", 1, true) then return false end

    local class_match =
        lower:find("mapobject", 1, true) or
        lower:find("basecamp", 1, true) or
        lower:find("build", 1, true) or
        lower:find("grouporganization", 1, true)

    local damage_match =
        lower:find(":ondamage", 1, true) or
        lower:find(":ondamaged", 1, true) or
        lower:find(":receivedamage", 1, true) or
        lower:find(":applydamage", 1, true)

    return class_match and damage_match
end

function StructureProbe.register(hooks, path, logger)
    local candidates = {}
    local ok = pcall(function()
        ForEachUObject(function(object)
            local full = UE.full_name(object)
            if full:sub(1, 9) == "Function " then
                local path_name = full:sub(10)
                if is_candidate(path_name) then
                    candidates[path_name] = true
                end
            end
        end)
    end)

    if not ok then
        logger:warn("Yapi hasar aday taramasi basarisiz")
        return 0
    end

    local count = 0
    for candidate in pairs(candidates) do
        if count >= 30 then break end

        local registered = hooks:register(
            "StructureDamageProbe",
            candidate,
            function(context, ...)
                local object = UE.unwrap(context)
                local guild_id = ""
                local ok_group, group_value =
                    UE.call(object, "GetGroupIdBelongTo")
                if ok_group then guild_id = UE.guid(group_value) end

                local args = {}
                for index, value in ipairs({...}) do
                    table.insert(args, "p" .. index .. "=" .. UE.text(value))
                end

                FileIO.append(path, TSV.encode({
                    Clock.now(),
                    candidate,
                    UE.full_name(object),
                    guild_id,
                    table.concat(args, ";")
                }))
            end
        )

        if registered then count = count + 1 end
    end

    logger:info("Yapi hasar probe hook sayisi: " .. tostring(count))
    return count
end

return StructureProbe
