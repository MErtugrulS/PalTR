local UE = require("PalTR.runtime.ue")
local FileIO = require("PalTR.storage.file_io")
local TSV = require("PalTR.storage.tsv")
local Clock = require("PalTR.core.clock")

local StructurePreDamageProbe = {}

local DAMAGE_FUNCTION =
    "/Script/Pal.PalNetworkMapObjectComponent:RequestDamageMapObject_ToServer"

local CALC_DAMAGE_FUNCTION =
    "/Script/Pal.PalUtility:CalcDamage"

local EMPTY_GUID =
    "00000000000000000000000000000000"

local model_index = {}

local function read_field(value, field)
    local target = UE.unwrap(value)

    if target == nil then
        return nil
    end

    local direct_ok, direct_value =
        pcall(function()
            return target[field]
        end)

    if direct_ok and direct_value ~= nil then
        return direct_value
    end

    local getter_ok, getter_value =
        pcall(function()
            return target:GetPropertyValue(field)
        end)

    if getter_ok then
        return getter_value
    end

    return nil
end

local function object_path(value)
    local target = UE.unwrap(value)

    if target == nil then
        return ""
    end

    local ok, result =
        pcall(function()
            return UE.full_name(target)
        end)

    if ok then
        return tostring(result or "")
    end

    return tostring(target)
end

local function scalar_text(value)
    local target = UE.unwrap(value)

    if target == nil then
        return ""
    end

    return tostring(target)
end

local function valid_guid(value)
    local text = tostring(value or "")

    return text ~= ""
        and text ~= EMPTY_GUID
end

local function rebuild_model_index(logger)
    local new_index = {}
    local count = 0

    local ok, error_message =
        pcall(function()
            ForEachUObject(function(object)
                pcall(function()
                    local full_name =
                        UE.full_name(object)

                    if full_name:sub(1, 18) ~=
                        "PalMapObjectModel "
                    then
                        return
                    end

                    local instance_id =
                        UE.guid(
                            read_field(
                                object,
                                "InstanceId"
                            )
                        )

                    if valid_guid(instance_id) then
                        new_index[instance_id] =
                            object

                        count = count + 1
                    end
                end)
            end)
        end)

    if not ok then
        logger:warn(
            "Yapi model indeksi olusturulamadi: " ..
            tostring(error_message)
        )

        return false
    end

    model_index = new_index

    logger:info(
        "Yapi model indeksi yenilendi: " ..
        tostring(count)
    )

    return true
end

local function find_model(instance_id, logger)
    local model =
        model_index[instance_id]

    if model ~= nil then
        return model
    end

    rebuild_model_index(logger)

    return model_index[instance_id]
end

local function resolve_identity(
    registry,
    model,
    attacker_group
)
    local build_player_uid =
        UE.guid(
            read_field(
                model,
                "BuildPlayerUId"
            )
        )

    local target_guild_key = ""
    local attacker_guild_key = ""
    local owner = nil
    local resolve_error = ""

    if registry == nil
        or type(
            registry.resolve_structure_identity
        ) ~= "function"
    then
        return build_player_uid,
            target_guild_key,
            attacker_guild_key,
            owner,
            "REGISTRY_UNAVAILABLE"
    end

    local ok,
        resolved_target,
        resolved_attacker,
        resolved_owner =
        pcall(function()
            return registry:resolve_structure_identity(
                build_player_uid,
                attacker_group
            )
        end)

    if not ok then
        resolve_error =
            tostring(resolved_target)

        return build_player_uid,
            target_guild_key,
            attacker_guild_key,
            owner,
            resolve_error
    end

    target_guild_key =
        tostring(resolved_target or "")

    attacker_guild_key =
        tostring(resolved_attacker or "")

    owner = resolved_owner

    return build_player_uid,
        target_guild_key,
        attacker_guild_key,
        owner,
        resolve_error
end

local function evaluate_policy(
    damage_policy,
    target_guild_key,
    attacker_guild_key
)
    if target_guild_key == ""
        or attacker_guild_key == ""
    then
        return {
            block = false,
            reason =
                "STRUCTURE_IDENTITY_UNRESOLVED",
            state = ""
        }
    end

    if target_guild_key ==
        attacker_guild_key
    then
        return {
            block = true,
            reason =
                "SAME_GUILD_STRUCTURE_PROTECTION",
            state = "SAME_GUILD"
        }
    end

    if damage_policy == nil
        or type(
            damage_policy.evaluate_player_damage
        ) ~= "function"
    then
        return {
            block = false,
            reason =
                "STRUCTURE_POLICY_UNAVAILABLE",
            state = ""
        }
    end

    local ok, result =
        pcall(function()
            return damage_policy:evaluate_player_damage(
                {
                    guild_key =
                        attacker_guild_key
                },
                {
                    guild_key =
                        target_guild_key
                }
            )
        end)

    if not ok
        or type(result) ~= "table"
    then
        return {
            block = false,
            reason =
                "STRUCTURE_POLICY_ERROR",
            state = ""
        }
    end

    return result
end

function StructurePreDamageProbe.register(
    hooks,
    path,
    registry,
    damage_policy,
    logger
)
    rebuild_model_index(logger)

    local registered = hooks:register(
        "StructurePreDamageProbe",
        DAMAGE_FUNCTION,
        function(
            context,
            instance_id_param,
            damage_info_param
        )
            local info =
                UE.unwrap(damage_info_param)

            local attacker =
                read_field(
                    info,
                    "Attacker"
                )

            local attacker_path =
                object_path(attacker)

            if not attacker_path:find(
                "BP_Player_",
                1,
                true
            ) then
                return
            end

            local instance_id =
                UE.guid(
                    UE.unwrap(instance_id_param)
                )

            local attacker_group =
                UE.guid(
                    read_field(
                        info,
                        "AttackerGroupID"
                    )
                )

            local model =
                find_model(
                    instance_id,
                    logger
                )

            local build_player_uid = ""
            local target_guild_key = ""
            local attacker_guild_key = ""
            local owner = nil
            local resolve_error = ""

            if model ~= nil then
                build_player_uid,
                    target_guild_key,
                    attacker_guild_key,
                    owner,
                    resolve_error =
                    resolve_identity(
                        registry,
                        model,
                        attacker_group
                    )
            else
                resolve_error =
                    "MODEL_NOT_FOUND"
            end

            local policy_result =
                evaluate_policy(
                    damage_policy,
                    target_guild_key,
                    attacker_guild_key
                )

            local policy_label = "ALLOW"
            local applied = false
            local apply_error = ""

            -- PALTR_STRUCTURE_PRE_DAMAGE_ENFORCEMENT_V1
            if policy_result.block then
                policy_label = "BLOCK"

                local set_ok, set_error =
                    pcall(function()
                        -- PALTR_STRUCTURE_NATIVE_DAMAGE_ZERO_V1
                        info.NoDamage = true
                        info.NativeDamageValue = 0

                        -- PALTR_STRUCTURE_BASE_POWER_ZERO_V1
                        info.BasePower = 0

                        damage_info_param:set(info)
                    end)

                applied = set_ok

                if not set_ok then
                    apply_error =
                        tostring(set_error)
                end
            end

            local owner_name = ""

            if owner ~= nil then
                owner_name =
                    tostring(owner.name or "")
            end

            local details = {
                "probe=STRUCTURE_PRE_DAMAGE_V2",
                "instance_id=" .. instance_id,
                "model_path=" .. object_path(model),
                "build_player_uid=" ..
                    build_player_uid,
                "owner_name=" .. owner_name,
                "target_guild_key=" ..
                    target_guild_key,
                "attacker_guild_key=" ..
                    attacker_guild_key,
                "StructurePolicy=" ..
                    policy_label,
                "StructureReason=" ..
                    tostring(
                        policy_result.reason or ""
                    ),
                "RelationState=" ..
                    tostring(
                        policy_result.state or ""
                    ),
                "Applied=" ..
                    tostring(applied),
                "ApplyError=" ..
                    apply_error,
                "ResolveError=" ..
                    resolve_error,
                "attacker_group=" ..
                    attacker_group,
                "attacker_path=" ..
                    attacker_path,
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
                "NoDamage=" ..
                    scalar_text(
                        read_field(
                            info,
                            "NoDamage"
                        )
                    )
            }

            FileIO.append(
                path,
                TSV.encode({
                    Clock.now(),
                    DAMAGE_FUNCTION,
                    object_path(context),
                    instance_id,
                    table.concat(details, ";")
                })
            )

            logger:info(
                "YAPI_PRE_DAMAGE_POLICY" ..
                " | instance_id=" ..
                instance_id ..
                " | hedef_klan=" ..
                target_guild_key ..
                " | saldiran_klan=" ..
                attacker_guild_key ..
                " | policy=" ..
                policy_label ..
                " | reason=" ..
                tostring(
                    policy_result.reason or ""
                ) ..
                " | applied=" ..
                tostring(applied) ..
                " | apply_error=" ..
                apply_error ..
                " | resolve_error=" ..
                resolve_error ..
                " | NoDamage=" ..
                scalar_text(
                    read_field(
                        info,
                        "NoDamage"
                    )
                )
            )
        end
    )

    if not registered then
        logger:warn(
            "Pre-damage yapi hook'u kaydedilemedi"
        )

        return 0
    end

    -- PALTR_STRUCTURE_CALC_DAMAGE_RETURN_ZERO_V1
    local calc_ok,
        calc_pre_id,
        calc_post_id =
        pcall(function()
            return RegisterHook(
                CALC_DAMAGE_FUNCTION,

                function(
                    context,
                    damage_info_param,
                    defender_param,
                    calculated_info_param
                )
                    return nil
                end,

                function(
                    context,
                    damage_info_param,
                    defender_param,
                    calculated_info_param
                )
                    local info =
                        UE.unwrap(
                            damage_info_param
                        )

                    local defender =
                        UE.unwrap(
                            defender_param
                        )

                    local defender_path =
                        object_path(defender)

                    if not defender_path:find(
                        "BP_BuildObject_",
                        1,
                        true
                    ) then
                        return nil
                    end

                    local attacker =
                        read_field(
                            info,
                            "Attacker"
                        )

                    local attacker_path =
                        object_path(attacker)

                    if not attacker_path:find(
                        "BP_Player_",
                        1,
                        true
                    ) then
                        return nil
                    end

                    local model =
                        read_field(
                            defender,
                            "MapObjectModel"
                        )

                    if model == nil then
                        local instance_id =
                            UE.guid(
                                read_field(
                                    defender,
                                    "ModelInstanceId"
                                )
                            )

                        if valid_guid(instance_id) then
                            model =
                                find_model(
                                    instance_id,
                                    logger
                                )
                        end
                    end

                    local attacker_group =
                        UE.guid(
                            read_field(
                                info,
                                "AttackerGroupID"
                            )
                        )

                    local build_player_uid = ""
                    local target_guild_key = ""
                    local attacker_guild_key = ""
                    local owner = nil
                    local resolve_error = ""

                    if model ~= nil then
                        build_player_uid,
                            target_guild_key,
                            attacker_guild_key,
                            owner,
                            resolve_error =
                            resolve_identity(
                                registry,
                                model,
                                attacker_group
                            )
                    else
                        resolve_error =
                            "MODEL_NOT_FOUND"
                    end

                    local policy_result =
                        evaluate_policy(
                            damage_policy,
                            target_guild_key,
                            attacker_guild_key
                        )

                    local policy_label = "ALLOW"
                    local override_return = ""

                    if policy_result.block then
                        policy_label = "BLOCK"
                        override_return = "0"
                    end

                    local details = {
                        "probe=STRUCTURE_CALC_DAMAGE_V1",

                        "defender_path=" ..
                            defender_path,

                        "model_path=" ..
                            object_path(model),

                        "build_player_uid=" ..
                            build_player_uid,

                        "target_guild_key=" ..
                            target_guild_key,

                        "attacker_guild_key=" ..
                            attacker_guild_key,

                        "StructurePolicy=" ..
                            policy_label,

                        "StructureReason=" ..
                            tostring(
                                policy_result.reason or ""
                            ),

                        "RelationState=" ..
                            tostring(
                                policy_result.state or ""
                            ),

                        "ResolveError=" ..
                            resolve_error,

                        "attacker_group=" ..
                            attacker_group,

                        "attacker_path=" ..
                            attacker_path,

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

                        "OverrideReturn=" ..
                            override_return
                    }

                    FileIO.append(
                        path,
                        TSV.encode({
                            Clock.now(),
                            CALC_DAMAGE_FUNCTION,
                            defender_path,
                            target_guild_key,
                            table.concat(
                                details,
                                ";"
                            )
                        })
                    )

                    logger:info(
                        "YAPI_CALC_DAMAGE" ..
                        " | hedef_klan=" ..
                        target_guild_key ..
                        " | saldiran_klan=" ..
                        attacker_guild_key ..
                        " | policy=" ..
                        policy_label ..
                        " | reason=" ..
                        tostring(
                            policy_result.reason or ""
                        ) ..
                        " | resolve_error=" ..
                        resolve_error ..
                        " | override_return=" ..
                        override_return
                    )

                    if policy_result.block then
                        return 0
                    end

                    return nil
                end
            )
        end)

    if not calc_ok
        or calc_pre_id == nil
    then
        logger:warn(
            "CalcDamage hook'u kaydedilemedi: " ..
            tostring(calc_pre_id)
        )

        return 0
    end

    logger:info(
        "Yapi CalcDamage donus korumasi aktif: " ..
        CALC_DAMAGE_FUNCTION
    )

    logger:info(
        "Yapi pre-damage politika hook'u aktif: " ..
        DAMAGE_FUNCTION
    )

    return 2
end

return StructurePreDamageProbe