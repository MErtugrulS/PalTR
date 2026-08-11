local Result = require("PalTR.core.result")
local UE = require("PalTR.runtime.ue")
local StructureIdentity = require("PalTR.runtime.structure_identity")

local Adapter = {}
Adapter.__index = Adapter

local function number(value)
    return tonumber(value) or 0
end

local function location(ue, vector, units_per_meter)
    vector = ue.unwrap(vector)
    if vector == nil then return nil end

    return {
        x = number(ue.unwrap(ue.read(vector, "X"))) / units_per_meter,
        y = number(ue.unwrap(ue.read(vector, "Y"))) / units_per_meter,
        z = number(ue.unwrap(ue.read(vector, "Z"))) / units_per_meter
    }
end

local function distance(first, second)
    local dx = number(first.x) - number(second.x)
    local dy = number(first.y) - number(second.y)
    local dz = number(first.z) - number(second.z)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function matches(path, tokens)
    for _, token in ipairs(tokens or {}) do
        token = tostring(token or "")
        if token ~= "" and path:find(token, 1, true) then return true end
    end
    return false
end

function Adapter.new(ue)
    return setmetatable({ ue = ue or UE }, Adapter)
end

function Adapter:_record(actor, registry, config)
    if not self.ue.valid(actor) then return nil end

    local path = self.ue.full_name(actor)
    if path:find("Default__", 1, true) then return nil end
    if not matches(path, config.siege_camp_actor_class_tokens) then return nil end

    local ok_available, available = self.ue.call(actor, "IsAvailable")
    if not ok_available or self.ue.unwrap(available) ~= true then return nil end

    local ok_group, group_id = self.ue.call(actor, "GetGroupIdBelongTo")
    local ok_model, model = self.ue.call(actor, "GetModel")
    local ok_location, actor_location = self.ue.call(
        actor,
        "K2_GetActorLocation"
    )

    if not ok_group or not ok_model or not ok_location then return nil end
    model = self.ue.unwrap(model)
    if not self.ue.valid(model) then return nil end

    local ok_id, model_id = self.ue.call(model, "GetModelId")
    if not ok_id then return nil end

    local guild = StructureIdentity.guild_for_model(
        self.ue,
        registry,
        group_id,
        model
    )
    local reference = self.ue.guid(model_id)
    local position = location(
        self.ue,
        actor_location,
        number(config.world_units_per_meter)
    )

    if not guild or reference == "" or not position then return nil end

    return {
        reference = reference,
        guild_key = guild.key,
        actor_reference = path,
        x = position.x,
        y = position.y,
        z = position.z
    }
end

function Adapter:nearest_owned_siege_camp(player, registry, config)
    config = config or {}
    local units_per_meter = number(config.world_units_per_meter)
    local tokens = config.siege_camp_actor_class_tokens or {}

    if units_per_meter <= 0 then
        return Result.err(
            "WORLD_UNIT_SCALE_INVALID",
            "World birim/metre orani sifirdan buyuk olmali"
        )
    end

    if #tokens == 0 then
        return Result.err(
            "SIEGE_CAMP_CLASS_MISSING",
            "Kusatma kampi yapi sinifi ayarlanmamis"
        )
    end

    local ok_player, player_vector = self.ue.call(
        player and player.pawn,
        "K2_GetActorLocation"
    )
    if not ok_player then
        return Result.err(
            "PLAYER_LOCATION_UNAVAILABLE",
            "Oyuncu konumu okunamadi"
        )
    end

    local player_location = location(
        self.ue,
        player_vector,
        units_per_meter
    )
    local nearest = nil
    local nearest_distance = math.huge

    for _, actor in pairs(self.ue.find_all("PalBuildObject")) do
        local record = self:_record(actor, registry, config)

        if record and record.guild_key == tostring(player.guild_key or "") then
            local current_distance = distance(player_location, record)
            if current_distance < nearest_distance then
                nearest = record
                nearest_distance = current_distance
            end
        end
    end

    local maximum = number(config.siege_camp_interaction_radius_meters)
    if maximum <= 0 or not nearest or nearest_distance > maximum then
        return Result.err(
            "OWN_SIEGE_CAMP_NOT_NEAR",
            "Yakinda klanina ait gecerli kusatma kampi yapisi bulunamadi"
        )
    end

    nearest.distance_meters = nearest_distance
    return Result.ok(nearest)
end

return Adapter
