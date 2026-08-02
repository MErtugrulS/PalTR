local UE = require("PalTR.runtime.ue")
local Clock = require("PalTR.core.clock")

local GuildAdapter = {}

function GuildAdapter.from_object(object)
    if not UE.valid(object) then return nil end

    local path = UE.full_name(object)
    if path:find("Default__", 1, true)
        or not path:find("/Game/Pal/Maps/", 1, true)
        or not path:find("PalGroupGuild_", 1, true) then
        return nil
    end

    local ok_name, name_value = UE.call(object, "GetGuildName")
    local ok_key, key_value = UE.call(object, "GetGroupName")
    local ok_id, id_value = UE.call(object, "GetId")

    local name = ok_name and UE.text(name_value)
        or UE.text(UE.read(object, "GuildName"))
    local key = ok_key and UE.text(key_value)
        or UE.text(UE.read(object, "GroupName"))
    local id = ok_id and UE.guid(id_value)
        or UE.guid(UE.read(object, "Id"))

    if name == "" or key == "" then return nil end

    return {
        key = key,
        name = name,
        id = id,
        object_path = path,
        object = object,
        first_seen = Clock.now(),
        last_seen = Clock.now()
    }
end

function GuildAdapter.scan()
    local records = {}
    for _, object in pairs(UE.find_all("PalGroupGuild")) do
        local record = GuildAdapter.from_object(object)
        if record then records[record.key] = record end
    end
    return records
end

return GuildAdapter
