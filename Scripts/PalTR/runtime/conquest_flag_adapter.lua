local Result = require("PalTR.core.result")
local UE = require("PalTR.runtime.ue")

local Adapter = {}
Adapter.__index = Adapter

local function number(value) return tonumber(value) or 0 end

local function matches(path, tokens)
    for _, token in ipairs(tokens or {}) do
        token = tostring(token or "")
        if token ~= "" and path:find(token, 1, true) then return true end
    end
    return false
end

local function position(ue, vector, scale)
    vector = ue.unwrap(vector)
    if vector == nil then return nil end
    return {
        x = number(ue.unwrap(ue.read(vector, "X"))) / scale,
        y = number(ue.unwrap(ue.read(vector, "Y"))) / scale,
        z = number(ue.unwrap(ue.read(vector, "Z"))) / scale
    }
end

local function distance(first, second)
    local dx = number(first.x) - number(second.x)
    local dy = number(first.y) - number(second.y)
    local dz = number(first.z) - number(second.z)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

function Adapter.new(ue) return setmetatable({ ue = ue or UE }, Adapter) end

function Adapter:_record(actor, registry, config, tokens)
    if not self.ue.valid(actor) then return nil, "INVALID" end
    local path = self.ue.full_name(actor)
    if path:find("Default__", 1, true)
        or not matches(path, tokens) then return nil, "CLASS_MISMATCH" end

    local ok_available, available = self.ue.call(actor, "IsAvailable")
    local ok_group, group_id = self.ue.call(actor, "GetGroupIdBelongTo")
    local ok_model, model = self.ue.call(actor, "GetModel")
    local ok_location, actor_location = self.ue.call(actor, "K2_GetActorLocation")
    if not ok_available or self.ue.unwrap(available) ~= true
        or not ok_group or not ok_model or not ok_location then
        return nil, "CONTRACT_UNREADABLE"
    end

    model = self.ue.unwrap(model)
    if not self.ue.valid(model) then return nil, "CONTRACT_UNREADABLE" end
    local ok_id, model_id = self.ue.call(model, "GetModelId")
    if not ok_id then return nil, "CONTRACT_UNREADABLE" end

    local guild = registry:find_guild_by_id(self.ue.guid(group_id))
    local reference = self.ue.guid(model_id)
    local location = position(self.ue, actor_location, number(config.world_units_per_meter))
    if not guild then return nil, "OWNER_UNRESOLVED" end
    if reference == "" or not location then return nil, "CONTRACT_UNREADABLE" end
    return {
        node_id = reference, flag_reference = reference,
        guild_key = guild.key, name = "Klan Bayragi",
        actor_reference = path,
        x = location.x, y = location.y, z = location.z
    }
end

function Adapter:_nearest_owned(player, registry, config, tokens)
    config = config or {}
    local scale = number(config.world_units_per_meter)
    tokens = tokens or {}
    if scale <= 0 then
        return Result.err("WORLD_UNIT_SCALE_INVALID", "World birim/metre orani gecersiz")
    end
    if #tokens == 0 then
        return Result.err(
            "CONQUEST_FLAG_CLASS_UNVERIFIED",
            "Dogrulanmis Klan Bayragi world sinifi henuz ayarlanmadi"
        )
    end

    local ok_player, player_vector = self.ue.call(
        player and player.pawn, "K2_GetActorLocation"
    )
    if not ok_player then
        return Result.err("PLAYER_LOCATION_UNAVAILABLE", "Oyuncu konumu okunamadi")
    end
    local player_location = position(self.ue, player_vector, scale)
    local nearest, nearest_distance = nil, math.huge
    local matched, readable, owned = 0, 0, 0
    local owner_unresolved = 0

    for _, actor in pairs(self.ue.find_all("PalBuildObject")) do
        local record, reason = self:_record(actor, registry, config, tokens)
        if reason ~= "INVALID" and reason ~= "CLASS_MISMATCH" then
            matched = matched + 1
        end
        if reason == "OWNER_UNRESOLVED" then
            owner_unresolved = owner_unresolved + 1
        end
        if record then
            readable = readable + 1
        end
        if record and record.guild_key == tostring(player.guild_key or "") then
            owned = owned + 1
            local current = distance(player_location, record)
            if current < nearest_distance then
                nearest, nearest_distance = record, current
            end
        end
    end

    local maximum = number(config.flag_interaction_radius_meters)
    if maximum <= 0 or not nearest or nearest_distance > maximum then
        local detail
        if matched == 0 then
            detail = "Ayarli Klan Bayragi sinifinda world aktoru bulunamadi"
        elseif readable == 0 and owner_unresolved > 0 then
            detail = "Yapi bulundu fakat klan sahipligi cozumlenemedi"
        elseif readable == 0 then
            detail = "Yapi bulundu fakat model, sahiplik veya konum okunamadi"
        elseif owned == 0 then
            detail = "Yapi bulundu fakat oyuncunun klanina ait degil"
        else
            detail = string.format(
                "En yakin klan yapisi %.1f m; izin verilen mesafe %.1f m",
                nearest_distance,
                maximum
            )
        end
        return Result.err(
            "OWN_CONQUEST_FLAG_NOT_NEAR",
            detail
        )
    end
    nearest.distance_meters = nearest_distance
    return Result.ok(nearest)
end

function Adapter:nearest_owned_flag(player, registry, config)
    config = config or {}
    return self:_nearest_owned(
        player,
        registry,
        config,
        config.conquest_flag_actor_class_tokens
    )
end

function Adapter:nearest_owned_candidate(player, registry, config)
    config = config or {}
    return self:_nearest_owned(
        player,
        registry,
        config,
        config.flag_candidate_actor_class_tokens
    )
end

return Adapter
