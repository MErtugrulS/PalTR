local UE = require("PalTR.runtime.ue")
local FileIO = require("PalTR.storage.file_io")
local TSV = require("PalTR.storage.tsv")
local Clock = require("PalTR.core.clock")

local Observer = {}
Observer.__index = Observer

local DAMAGE_FUNCTION =
    "/Script/Pal.PalPlayerCharacter:OnDamagePlayer_Server"

local function runtime_type(value)
    if value == nil then
        return "nil"
    end

    local lua_type = type(value)

    local ok, ue_type = pcall(function()
        return value:type()
    end)

    if ok and ue_type ~= nil then
        return lua_type .. "/" .. tostring(ue_type)
    end

    return lua_type
end

local function fname_text(value)
    if value == nil then
        return ""
    end

    local ok, result = pcall(function()
        return value:ToString()
    end)

    if ok and result ~= nil then
        return tostring(result)
    end

    return ""
end

local function property_name(property)
    local ok, result = pcall(function()
        return fname_text(property:GetFName())
    end)

    if ok then
        return result
    end

    return ""
end

local function property_class(property)
    local ok, result = pcall(function()
        local class = property:GetClass()

        if class == nil then
            return ""
        end

        return fname_text(class:GetFName())
    end)

    if ok then
        return result
    end

    return ""
end

local function property_full_name(property)
    local ok, result = pcall(function()
        return property:GetFullName()
    end)

    if ok and result ~= nil then
        return tostring(result)
    end

    return ""
end

function Observer.new(path, registry, logger)
    return setmetatable({
        path = path,
        registry = registry,
        logger = logger,
        signature_logged = false
    }, Observer)
end

function Observer:_append_probe(detail)
    FileIO.append(self.path, TSV.encode({
        Clock.now(),
        "<damage-signature-probe>",
        "",
        "",
        detail
    }))
end

function Observer:_probe_signature(result_param)
    if self.signature_logged then
        return
    end

    self.signature_logged = true

    self:_append_probe(
        "probe=wrapper" ..
        ";type=" .. runtime_type(result_param)
    )

    local underlying = UE.unwrap(result_param)

    self:_append_probe(
        "probe=underlying" ..
        ";type=" .. runtime_type(underlying)
    )

    local ok_find, function_object = pcall(
        StaticFindObject,
        DAMAGE_FUNCTION
    )

    if not ok_find
        or function_object == nil
        or not UE.valid(function_object) then

        self:_append_probe(
            "probe=function" ..
            ";status=not_found" ..
            ";path=" .. DAMAGE_FUNCTION
        )

        self.logger:warn(
            "Hasar fonksiyon imzasi bulunamadi"
        )

        return
    end

    self:_append_probe(
        "probe=function" ..
        ";status=found" ..
        ";path=" .. DAMAGE_FUNCTION
    )

    local ok_properties, property_error = pcall(function()
        function_object:ForEachProperty(function(property)
            local name = property_name(property)
            local class = property_class(property)

            self:_append_probe(
                "probe=function_property" ..
                ";name=" .. name ..
                ";class=" .. class ..
                ";full=" .. property_full_name(property)
            )

            local is_struct = false

            if PropertyTypes ~= nil
                and PropertyTypes.StructProperty ~= nil then

                local ok_struct_check, result =
                    pcall(function()
                        return property:IsA(
                            PropertyTypes.StructProperty
                        )
                    end)

                is_struct =
                    ok_struct_check and result == true
            end

            if is_struct then
                local ok_struct, struct =
                    pcall(function()
                        return property:GetStruct()
                    end)

                if ok_struct
                    and struct ~= nil
                    and UE.valid(struct) then

                    local ok_members, member_error =
                        pcall(function()
                            struct:ForEachProperty(
                                function(member)
                                    self:_append_probe(
                                        "probe=struct_member" ..
                                        ";parent=" .. name ..
                                        ";name=" ..
                                            property_name(member) ..
                                        ";class=" ..
                                            property_class(member) ..
                                        ";full=" ..
                                            property_full_name(member)
                                    )
                                end
                            )
                        end)

                    if not ok_members then
                        self:_append_probe(
                            "probe=struct_members_error" ..
                            ";parent=" .. name ..
                            ";error=" .. tostring(member_error)
                        )
                    end
                else
                    self:_append_probe(
                        "probe=struct_unavailable" ..
                        ";parent=" .. name
                    )
                end
            end
        end)
    end)

    if not ok_properties then
        self:_append_probe(
            "probe=function_properties_error" ..
            ";error=" .. tostring(property_error)
        )
    end

    self.logger:info(
        "Hasar fonksiyon imzasi kaydedildi"
    )
end

function Observer:on_player_damage(context, result_param)
    self:_probe_signature(result_param)

    local pawn = UE.unwrap(context)
    local result = UE.unwrap(result_param)

    local target_player = nil
    local pawn_path = UE.full_name(pawn)

    for _, player in pairs(
        self.registry.runtime_players
    ) do
        if player.pawn_path == pawn_path then
            target_player = player
            break
        end
    end

    local fields = {}

    for _, field in ipairs({
        "Damage",
        "DamageAmount",
        "FinalDamage",
        "Attacker",
        "DamageCauser",
        "Instigator",
        "AttackerPlayerUId",
        "TargetPlayerUId",
        "AttackType",
        "DamageType",
        "IsDead"
    }) do
        local value = UE.read(result, field)
        local rendered = UE.text(value)

        if rendered ~= "" then
            table.insert(
                fields,
                field .. "=" .. rendered
            )
        end
    end

    FileIO.append(self.path, TSV.encode({
        Clock.now(),
        pawn_path,
        target_player and target_player.name or "",
        target_player and target_player.guild_key or "",
        table.concat(fields, ";")
    }))

    self.logger:info(
        "Pasif oyuncu hasari kaydedildi: " ..
        (
            target_player
            and target_player.name
            or pawn_path
        )
    )
end

return Observer