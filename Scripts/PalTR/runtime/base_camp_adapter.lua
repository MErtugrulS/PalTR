local Result = require("PalTR.core.result")
local UE = require("PalTR.runtime.ue")

local Adapter = {}
Adapter.__index = Adapter

local function number(value)
    return tonumber(value) or 0
end

local function distance(first, second)
    local dx = number(first.x) - number(second.x)
    local dy = number(first.y) - number(second.y)
    local dz = number(first.z) - number(second.z)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

function Adapter.new(ue)
    return setmetatable({ ue = ue or UE }, Adapter)
end

function Adapter:_location_from_transform(transform, units_per_meter)
    transform = self.ue.unwrap(transform)
    local translation = self.ue.unwrap(
        self.ue.read(transform, "Translation")
    )

    if translation == nil then return nil end

    return {
        x = number(self.ue.unwrap(self.ue.read(translation, "X"))) /
            units_per_meter,
        y = number(self.ue.unwrap(self.ue.read(translation, "Y"))) /
            units_per_meter,
        z = number(self.ue.unwrap(self.ue.read(translation, "Z"))) /
            units_per_meter
    }
end

function Adapter:_model_record(model, registry, units_per_meter)
    if not self.ue.valid(model) then return nil end

    local ok_available, available = self.ue.call(model, "IsAvailable")
    if not ok_available or self.ue.unwrap(available) ~= true then return nil end

    local ok_id, id = self.ue.call(model, "GetId")
    local ok_group, group_id = self.ue.call(model, "GetGroupIdBelongTo")
    local ok_owner, owner_id = self.ue.call(
        model,
        "GetOwnerMapObjectInstanceId"
    )
    local ok_transform, transform = self.ue.call(model, "GetTransform")

    if not ok_id or not ok_group or not ok_owner or not ok_transform then
        return nil
    end

    local node_id = self.ue.guid(id)
    local group_key = self.ue.guid(group_id)
    local flag_reference = self.ue.guid(owner_id)
    local guild = registry:find_guild_by_id(group_key)
    local location = self:_location_from_transform(
        transform,
        units_per_meter
    )

    if node_id == "" or flag_reference == "" or not guild or not location then
        return nil
    end

    local ok_name, name = self.ue.call(model, "GetBaseCampName")

    return {
        node_id = node_id,
        flag_reference = flag_reference,
        guild_key = guild.key,
        name = ok_name and self.ue.text(name) or "",
        model_reference = self.ue.full_name(model),
        x = location.x,
        y = location.y,
        z = location.z
    }
end

function Adapter:scan(registry, config)
    config = config or {}
    local units_per_meter = number(config.world_units_per_meter)

    if units_per_meter <= 0 then
        return Result.err(
            "WORLD_UNIT_SCALE_INVALID",
            "World birim/metre orani sifirdan buyuk olmali"
        )
    end

    local records = {}

    for _, model in pairs(self.ue.find_all("PalBaseCampModel")) do
        local record = self:_model_record(
            model,
            registry,
            units_per_meter
        )

        if record then table.insert(records, record) end
    end

    return Result.ok(records)
end

function Adapter:nearest_owned(player, registry, config)
    config = config or {}
    local units_per_meter = number(config.world_units_per_meter)

    if units_per_meter <= 0 then
        return Result.err(
            "WORLD_UNIT_SCALE_INVALID",
            "World birim/metre orani sifirdan buyuk olmali"
        )
    end

    local ok_location, actor_location = self.ue.call(
        player and player.pawn,
        "K2_GetActorLocation"
    )

    if not ok_location then
        return Result.err(
            "PLAYER_LOCATION_UNAVAILABLE",
            "Oyuncu konumu okunamadi"
        )
    end

    local player_location = {
        x = number(self.ue.unwrap(self.ue.read(actor_location, "X"))) /
            units_per_meter,
        y = number(self.ue.unwrap(self.ue.read(actor_location, "Y"))) /
            units_per_meter,
        z = number(self.ue.unwrap(self.ue.read(actor_location, "Z"))) /
            units_per_meter
    }

    local scanned = self:scan(registry, config)
    if not scanned.ok then return scanned end

    local nearest = nil
    local nearest_distance = math.huge

    for _, record in ipairs(scanned.value) do
        if record.guild_key == tostring(player.guild_key or "") then
            local current_distance = distance(player_location, record)

            if current_distance < nearest_distance then
                nearest = record
                nearest_distance = current_distance
            end
        end
    end

    local maximum = number(config.registration_interaction_radius_meters)

    if maximum <= 0 or not nearest or nearest_distance > maximum then
        return Result.err(
            "OWN_BASE_CAMP_NOT_NEAR",
            "Yakinda klanina ait Pal Kutusu bulunamadi"
        )
    end

    nearest.distance_meters = nearest_distance
    return Result.ok(nearest)
end

return Adapter
