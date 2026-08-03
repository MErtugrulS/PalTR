local UE = require("PalTR.runtime.ue")
local FileIO = require("PalTR.storage.file_io")
local TSV = require("PalTR.storage.tsv")
local Clock = require("PalTR.core.clock")

local StructureProbe = {}

local DAMAGE_FUNCTION =
    "/Script/Pal.PalBuildObject:OnDamage"

local function read_field(value, field)
    local target = UE.unwrap(value)

    if target == nil then
        return nil
    end

    local ok, result = pcall(function()
        return target[field]
    end)

    if ok then
        return result
    end

    return nil
end

-- PALTR_KISMET_GUID_V1
local guid_library = nil
local guid_library_checked = false

local function get_guid_library()
    if guid_library_checked then
        return guid_library
    end

    guid_library_checked = true

    local ok, result = pcall(function()
        return StaticFindObject(
            "/Script/Engine.Default__KismetGuidLibrary"
        )
    end)

    if not ok or result == nil then
        return nil
    end

    guid_library = UE.unwrap(result)
    return guid_library
end

local function guid_text(value)
    local target = UE.unwrap(value)

    if target == nil then
        return ""
    end

    local library = get_guid_library()

    if library ~= nil then
        local ok, result = pcall(function()
            return library:Conv_GuidToString(target)
        end)

        if ok and result ~= nil then
            local text = UE.text(result)

            if text ~= ""
                and not text:find(
                    "CoreUObject.Guid",
                    1,
                    true
                )
            then
                return text
            end
        end
    end

    return ""
end

local function object_path(value)
    local target = UE.unwrap(value)

    if target == nil then
        return ""
    end

    local ok, result = pcall(function()
        return UE.full_name(target)
    end)

    if ok and result ~= nil then
        return tostring(result)
    end

    return ""
end

local function scalar_text(value)
    if value == nil then
        return ""
    end

    local value_type = type(value)

    if value_type == "string"
        or value_type == "number"
        or value_type == "boolean" then

        return tostring(value)
    end

    local text_ok, text_value = pcall(function()
        return UE.text(value)
    end)

    if text_ok
        and text_value ~= nil
        and tostring(text_value) ~= "" then

        return tostring(text_value)
    end

    return tostring(value)
end

local function call_guid(object, method_name)
    local target = UE.unwrap(object)

    if target == nil then
        return ""
    end

    local ok, result = pcall(function()
        local method = target[method_name]

        if type(method) ~= "function" then
            return nil
        end

        return method(target)
    end)

    if not ok then
        return ""
    end

    return guid_text(result)
end

local function is_zero_guid(value)
    local compact = tostring(value or "")
        :gsub("[^0-9A-Fa-f]", "")

    return compact == ""
        or compact == "00000000000000000000000000000000"
end

function StructureProbe.register(hooks, path, registry, logger)
    local registered = hooks:register(
        "StructureDamageProbe",
        DAMAGE_FUNCTION,
        function(context, damaged_model_param, damage_info_param)
            local actor = UE.unwrap(context)
            local model = UE.unwrap(damaged_model_param)
            local info = UE.unwrap(damage_info_param)

            local model_group =
                guid_text(
                    read_field(
                        model,
                        "GroupIdBelongTo"
                    )
                )

            local actor_group =
                call_guid(
                    actor,
                    "GetGroupIdBelongTo"
                )

            local target_group = model_group

            if is_zero_guid(target_group) then
                target_group = actor_group
            end

            local attacker_group =
                guid_text(
                    read_field(
                        info,
                        "AttackerGroupID"
                    )
                )

            -- PALTR_STRUCTURE_IDENTITY_PROBE_V1
            local build_player_uid =
                guid_text(
                    read_field(
                        model,
                        "BuildPlayerUId"
                    )
                )

            local target_guild_key = ""
            local attacker_guild_key = ""
            local build_player_name = ""

            if registry ~= nil
                and type(
                    registry.resolve_structure_identity
                ) == "function"
            then
                local resolved_target,
                    resolved_attacker,
                    owner_player =
                        registry:resolve_structure_identity(
                            build_player_uid,
                            attacker_group
                        )

                target_guild_key =
                    tostring(resolved_target or "")

                attacker_guild_key =
                    tostring(resolved_attacker or "")

                if owner_player ~= nil then
                    build_player_name =
                        tostring(owner_player.name or "")
                end
            end
            local attacker =
                read_field(
                    info,
                    "Attacker"
                )

            local override_owner =
                read_field(
                    info,
                    "OverrideNetworkOwner"
                )

            local details = {
                "probe=STRUCTURE_DAMAGE_V2",
                "model_path=" .. object_path(model),
                "model_group=" .. model_group,
                "actor_group=" .. actor_group,
                "base_camp=" ..
                    guid_text(
                        read_field(
                            model,
                            "BaseCampIdBelongTo"
                        )
                    ),
                "build_player_uid=" .. build_player_uid,
                "build_player_name=" .. build_player_name,
                "target_guild_key=" .. target_guild_key,
                "attacker_guild_key=" .. attacker_guild_key,
                "attacker_group=" .. attacker_group,
                "attacker_path=" .. object_path(attacker),
                "override_owner_path=" ..
                    object_path(override_owner),
                "NativeDamageValue=" ..
                    scalar_text(
                        read_field(
                            info,
                            "NativeDamageValue"
                        )
                    ),
                "BasePower=" ..
                    scalar_text(
                        read_field(
                            info,
                            "BasePower"
                        )
                    ),
                "PvPBuildingDamageRate=" ..
                    scalar_text(
                        read_field(
                            info,
                            "PvPBuildingDamageRate"
                        )
                    ),
                "bAttackableToFriend=" ..
                    scalar_text(
                        read_field(
                            info,
                            "bAttackableToFriend"
                        )
                    ),
                "NoDamage=" ..
                    scalar_text(
                        read_field(
                            info,
                            "NoDamage"
                        )
                    ),
                "AttackType=" ..
                    scalar_text(
                        read_field(
                            info,
                            "AttackType"
                        )
                    ),
                "WeaponType=" ..
                    scalar_text(
                        read_field(
                            info,
                            "WeaponType"
                        )
                    ),
                "bIsExplosionDamage=" ..
                    scalar_text(
                        read_field(
                            info,
                            "bIsExplosionDamage"
                        )
                    )
            }

            FileIO.append(
                path,
                TSV.encode({
                    Clock.now(),
                    DAMAGE_FUNCTION,
                    object_path(actor),
                    target_guild_key ~= ""
                        and target_guild_key
                        or target_group,
                    table.concat(details, ";")
                })
            )

            if not is_zero_guid(attacker_group)
                or object_path(attacker) ~= "" then

                logger:info(
                    "YAPI_HASAR_PROBE" ..
                    " | hedef_klan=" ..
                    tostring(target_group) ..
                    " | saldiran_klan=" ..
                    tostring(attacker_group) ..
                    " | hedef_klan_anahtar=" ..
                    tostring(target_guild_key) ..
                    " | saldiran_klan_anahtar=" ..
                    tostring(attacker_guild_key) ..
                    " | yapi_sahibi=" ..
                    tostring(build_player_name) ..
                    " | saldiran=" ..
                    object_path(attacker) ..
                    " | NoDamage=" ..
                    scalar_text(
                        read_field(
                            info,
                            "NoDamage"
                        )
                    )
                )
            end
        end
    )

    if not registered then
        logger:warn(
            "Dar yapi hasar probe hook'u kaydedilemedi"
        )

        return 0
    end

    logger:info(
        "Dar yapi hasar probe aktif: " ..
        DAMAGE_FUNCTION
    )

    return 1
end

return StructureProbe