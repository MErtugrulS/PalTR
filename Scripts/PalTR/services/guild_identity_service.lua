local Clock = require("PalTR.core.clock")
local FileIO = require("PalTR.storage.file_io")
local Result = require("PalTR.core.result")
local TSV = require("PalTR.storage.tsv")
local Text = require("PalTR.core.text")
local Tables = require("PalTR.core.table_utils")
local ConquestRules = require("PalTR.domain.conquest_rules")
local Catalog = require("PalTR.domain.guild_identity_catalog")

local Service = {}
Service.__index = Service

local HEADER = "guild_key\tcolor_id\temblem_id\tselected_by\tselected_at"

local function load(path)
    local read = FileIO.read_lines(path)
    if not read.ok then error(Result.describe(read)) end
    if #(read.value or {}) == 0 then return {} end
    if read.value[1] ~= HEADER then
        error("Gecersiz klan kimligi basligi: " .. tostring(path))
    end

    local records = {}
    for index, line in ipairs(read.value) do
        if index > 1 and line ~= "" then
            local columns = TSV.decode(line)
            local guild_key = Text.clean(columns[1])
            if guild_key ~= "" then
                records[guild_key] = {
                    guild_key = guild_key,
                    color_id = Text.clean(columns[2]),
                    emblem_id = Text.clean(columns[3]),
                    selected_by = Text.clean(columns[4]),
                    selected_at = tonumber(columns[5]) or 0
                }
            end
        end
    end
    return records
end

local function save(path, records)
    local lines = { HEADER }
    for _, guild_key in ipairs(Tables.sorted_keys(records)) do
        local record = records[guild_key]
        table.insert(lines, TSV.encode({
            record.guild_key,
            record.color_id,
            record.emblem_id,
            record.selected_by,
            record.selected_at
        }))
    end
    return FileIO.overwrite(path, lines)
end

function Service.new(paths, config, logger, options)
    options = options or {}
    local path = paths and paths.guild_identity or ""
    return setmetatable({
        path = path,
        config = config and (config.conquest or config) or {},
        logger = logger,
        clock = options.clock or Clock,
        records = options.records or load(path)
    }, Service)
end

function Service:get(guild_key)
    return self.records[Text.clean(guild_key)]
end

function Service:has_identity(guild_key)
    local record = self:get(guild_key)
    return record ~= nil
        and Catalog.COLOR_BY_ID[record.color_id] ~= nil
        and Catalog.EMBLEM_BY_ID[record.emblem_id] ~= nil
end

function Service:can_manage(role)
    return ConquestRules.can_operate(role, self.config)
end

function Service:set_identity(request)
    request = request or {}
    local guild_key = Text.clean(request.guild_key)
    local color_id = Text.lower_ascii(Text.clean(request.color_id))
    local emblem_id = Text.lower_ascii(Text.clean(request.emblem_id))

    if guild_key == "" then
        return Result.err("GUILD_IDENTITY_MISSING", "Klan kimligi bulunamadi")
    end
    if not self:can_manage(request.actor_role) then
        return Result.err(
            "GUILD_IDENTITY_ROLE_REQUIRED",
            "Lider, yardimci lider veya komutan yetkisi gerekli"
        )
    end
    if self.records[guild_key] ~= nil then
        return Result.err(
            "GUILD_IDENTITY_LOCKED",
            "Klan rengi ve armasi kilitli"
        )
    end
    if Catalog.COLOR_BY_ID[color_id] == nil then
        return Result.err("INVALID_GUILD_COLOR", "Gecersiz klan rengi")
    end
    if Catalog.EMBLEM_BY_ID[emblem_id] == nil then
        return Result.err("INVALID_GUILD_EMBLEM", "Gecersiz klan armasi")
    end

    for other_guild, record in pairs(self.records) do
        if other_guild ~= guild_key and record.color_id == color_id then
            return Result.err(
                "GUILD_COLOR_TAKEN",
                "Bu klan rengi baska bir klan tarafindan kullaniliyor"
            )
        end
    end

    local record = {
        guild_key = guild_key,
        color_id = color_id,
        emblem_id = emblem_id,
        selected_by = Text.clean(request.selected_by),
        selected_at = tonumber(request.now) or self.clock.now()
    }
    self.records[guild_key] = record
    local saved = save(self.path, self.records)
    if not saved.ok then
        self.records[guild_key] = nil
        return saved
    end

    if self.logger then
        self.logger:info(
            "GUILD_IDENTITY_SELECTED | guild=" .. guild_key ..
            " | color=" .. color_id .. " | emblem=" .. emblem_id
        )
    end
    return Result.ok(record)
end

function Service:catalog_for(guild_key, role)
    guild_key = Text.clean(guild_key)
    local selected = self:get(guild_key)
    local used = {}
    for owner, record in pairs(self.records) do
        if owner ~= guild_key then used[record.color_id] = true end
    end

    local colors = {}
    for _, color in ipairs(Catalog.COLORS) do
        table.insert(colors, {
            id = color.id,
            hex = color.hex,
            available = not used[color.id]
                or (selected ~= nil and selected.color_id == color.id)
        })
    end
    local emblems = {}
    for _, emblem in ipairs(Catalog.EMBLEMS) do
        table.insert(emblems, { id = emblem.id, name = emblem.name })
    end

    return {
        palette_version = Catalog.PALETTE_VERSION,
        selected_color_id = selected and selected.color_id or "",
        selected_emblem_id = selected and selected.emblem_id or "",
        locked = selected ~= nil,
        can_manage = selected == nil and self:can_manage(role),
        colors = colors,
        emblems = emblems
    }
end

return Service
