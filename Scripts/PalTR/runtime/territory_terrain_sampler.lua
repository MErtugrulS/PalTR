local UE = require("PalTR.runtime.ue")

local Sampler = {}
Sampler.__index = Sampler

local function finite_number(value)
    value = tonumber(value)
    if value == nil or value ~= value
        or value == math.huge or value == -math.huge then
        return nil
    end
    return value
end

local function coordinate(vector, field)
    return finite_number(UE.unwrap(UE.read(vector, field)))
end

local function surface_name(hit)
    local handle = UE.unwrap(UE.read(hit, "HitObjectHandle"))
    local actor = handle and UE.unwrap(UE.read(handle, "Actor")) or nil
    local component = UE.unwrap(UE.read(hit, "Component"))
    local name = (UE.full_name(actor) .. " " .. UE.full_name(component)):lower()
    if name:find("water", 1, true)
        or name:find("river", 1, true)
        or name:find("lake", 1, true) then
        return "water"
    end
    return "land"
end

local function find_library()
    if type(StaticFindObject) ~= "function" then return nil end
    local ok, value = pcall(
        StaticFindObject,
        "/Script/Engine.Default__KismetSystemLibrary"
    )
    if not ok then return nil end
    return UE.unwrap(value)
end

function Sampler.new(config, options)
    config = config or {}
    options = options or {}
    return setmetatable({
        scale = math.max(1, finite_number(config.world_units_per_meter) or 100),
        max_traces = math.max(0, math.floor(finite_number(
            config.territory_terrain_max_traces_per_pass
        ) or 1800)),
        context = options.context,
        trace = options.trace,
        library = options.library,
        library_checked = options.library ~= nil,
        cache = {},
        traces_this_pass = 0,
        revision = 0
    }, Sampler)
end

function Sampler:set_context(context)
    context = UE.unwrap(context)
    if context == nil or not UE.valid(context) then return false end
    if self.context ~= context then
        self.context = context
        self.revision = self.revision + 1
    end
    return true
end

function Sampler:is_ready()
    if type(self.trace) == "function" then return self.context ~= nil end
    return UE.valid(self.context)
end

function Sampler:begin_pass()
    self.traces_this_pass = 0
end

function Sampler:_library()
    if self.library_checked then return self.library end
    self.library_checked = true
    self.library = find_library()
    return self.library
end

function Sampler:_runtime_trace(x, y)
    local library = self:_library()
    if not UE.valid(library) or not UE.valid(self.context) then return nil end

    local scale = self.scale
    local hit = {}
    local transparent = { R = 0, G = 0, B = 0, A = 0 }
    local ok, was_hit = pcall(function()
        return library:LineTraceSingle(
            self.context,
            { X = x * scale, Y = y * scale, Z = 500000 },
            { X = x * scale, Y = y * scale, Z = -500000 },
            0,
            false,
            {},
            0,
            hit,
            true,
            transparent,
            transparent,
            0.0
        )
    end)
    if not ok or was_hit ~= true then return nil end

    local impact = UE.unwrap(UE.read(hit, "ImpactPoint"))
        or UE.unwrap(UE.read(hit, "Location"))
    local z = coordinate(impact, "Z")
    if z == nil then return nil end
    return {
        height = z / scale,
        surface = surface_name(hit)
    }
end

function Sampler:sample(x, y)
    x, y = finite_number(x), finite_number(y)
    if x == nil or y == nil or not self:is_ready() then return nil end

    local key = string.format("%.1f:%.1f", x, y)
    if self.cache[key] ~= nil then
        local cached = self.cache[key]
        return cached ~= false and cached or nil
    end
    if self.traces_this_pass >= self.max_traces then return nil end
    self.traces_this_pass = self.traces_this_pass + 1

    local ok, value
    if type(self.trace) == "function" then
        ok, value = pcall(self.trace, self.context, x, y)
    else
        ok, value = pcall(self._runtime_trace, self, x, y)
    end
    if not ok or type(value) ~= "table"
        or finite_number(value.height or value.z) == nil then
        self.cache[key] = false
        return nil
    end

    local result = {
        height = finite_number(value.height or value.z),
        surface = tostring(value.surface or "land")
    }
    self.cache[key] = result
    return result
end

return Sampler
