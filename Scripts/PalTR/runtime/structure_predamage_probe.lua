local UE = require("PalTR.runtime.ue")
local FileIO = require("PalTR.storage.file_io")
local TSV = require("PalTR.storage.tsv")
local Clock = require("PalTR.core.clock")

local StructurePreDamageProbe = {}

local DAMAGE_FUNCTION =
    "/Script/Pal.PalNetworkMapObjectComponent:RequestDamageMapObject_ToServer"

local EMPTY_GUID =
    "00000000000000000000000000000000"

local DAMAGABLE_NO_DAMAGE = 2

local model_index = {}
local actor_index = {}
local pending_restore = {}

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

local function write_field(value, field, new_value)
    local target = UE.unwrap(value)

    if target == nil then
        return false, "TARGET_NIL"
    end

    local direct_ok, direct_error =
        pcall(function()
            target[field] = new_value
        end)

    if direct_ok then
        return true, ""
    end

    local setter_ok, setter_error =
        pcall(function()
            target:SetPropertyValue(
                field,
                new_value
            )
        end)

    if setter_ok then
        return true, ""
    end

    return false,
        tostring(direct_error) ..
        " | " ..
        tostring(setter_error)
end

local function enum_value(value)
    local target = UE.unwrap(value)

    if type(target) == "number" then
        return target
    end

    local text = tostring(target or "")
    local numeric = tonumber(text)

    if numeric ~= nil then
        return numeric
    end

    if text:find("AllRecieve", 1, true) then
        return 0
    end

    if text:find("OtherGroup", 1, true) then
        return 1
    end

    if text:find("NoDamage", 1, true) then
        return 2
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

local function rebuild_actor_index(logger)
    local new_index = {}
    local count = 0

    local ok, error_message =
        pcall(function()
            ForEachUObject(function(object)
                pcall(function()
                    local full_name =
                        UE.full_name(object)

                    if not full_name:find(
                        "BP_BuildObject_",
                        1,
                        true
                    ) then
                        return
                    end

                    local instance_id =
                        UE.guid(
                            read_field(
                                object,
                                "ModelInstanceId"
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
            "Yapi actor indeksi olusturulamadi: " ..
            tostring(error_message)
        )

        return false
    end

    actor_index = new_index

    logger:info(
        "Yapi actor indeksi yenilendi: " ..
        tostring(count)
    )

    return true
end

local function find_actor(instance_id, logger)
    local actor =
        actor_index[instance_id]

    if actor ~= nil then
        return actor
    end

    rebuild_actor_index(logger)

    return actor_index[instance_id]
end

local function push_restore(instance_id, record)
    local stack =
        pending_restore[instance_id]

    if stack == nil then
        stack = {}
        pending_restore[instance_id] = stack
    end

    stack[#stack + 1] = record
end

local function pop_restore(instance_id)
    local stack =
        pending_restore[instance_id]

    if stack == nil
        or #stack == 0
    then
        return nil
    end

    local record =
        stack[#stack]

    stack[#stack] = nil

    if #stack == 0 then
        pending_restore[instance_id] = nil
    end

    return record
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
    rebuild_actor_index(logger)

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

            local actor =
                find_actor(
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

            local model_before =
                read_field(
                    model,
                    "DamagableType"
                )

            local actor_before =
                read_field(
                    actor,
                    "DamagableType"
                )

            -- PALTR_STRUCTURE_DAMAGEABILITY_LOCK_V1
            if policy_result.block then
                policy_label = "BLOCK"

                local model_ok = false
                local model_error = "MODEL_NIL"

                local actor_ok = false
                local actor_error = "ACTOR_NIL"

                if model ~= nil then
                    model_ok,
                        model_error =
                        write_field(
                            model,
                            "DamagableType",
                            DAMAGABLE_NO_DAMAGE
                        )
                end

                if actor ~= nil then
                    actor_ok,
                        actor_error =
                        write_field(
                            actor,
                            "DamagableType",
                            DAMAGABLE_NO_DAMAGE
                        )
                end

                applied =
                    model_ok or actor_ok

                if applied then
                    push_restore(
                        instance_id,
                        {
                            model = model,
                            actor = actor,
                            model_before =
                                model_before,
                            actor_before =
                                actor_before,
                            model_changed =
                                model_ok,
                            actor_changed =
                                actor_ok,
                            target_guild_key =
                                target_guild_key,
                            attacker_guild_key =
                                attacker_guild_key,
                            reason =
                                tostring(
                                    policy_result.reason or ""
                                )
                        }
                    )
                end

                if not model_ok
                    or not actor_ok
                then
                    apply_error =
                        "MODEL=" ..
                        tostring(model_error) ..
                        " | ACTOR=" ..
                        tostring(actor_error)
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
                "ModelDamagableBefore=" ..
                    tostring(
                        enum_value(model_before)
                    ),
                "ModelDamagableDuring=" ..
                    tostring(
                        enum_value(
                            read_field(
                                model,
                                "DamagableType"
                            )
                        )
                    ),
                "ActorDamagableBefore=" ..
                    tostring(
                        enum_value(actor_before)
                    ),
                "ActorDamagableDuring=" ..
                    tostring(
                        enum_value(
                            read_field(
                                actor,
                                "DamagableType"
                            )
                        )
                    ),
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

    local restore_ok,
        restore_pre_id,
        restore_post_id =
        pcall(function()
            return RegisterHook(
                DAMAGE_FUNCTION,

                function(
                    context,
                    instance_id_param,
                    damage_info_param
                )
                    return nil
                end,

                function(
                    context,
                    instance_id_param,
                    damage_info_param
                )
                    local instance_id =
                        UE.guid(
                            UE.unwrap(
                                instance_id_param
                            )
                        )

                    local record =
                        pop_restore(instance_id)

                    if record == nil then
                        return
                    end

                    local model_ok = true
                    local model_error = ""

                    local actor_ok = true
                    local actor_error = ""

                    if record.model_changed
                        and record.model_before ~= nil
                    then
                        model_ok,
                            model_error =
                            write_field(
                                record.model,
                                "DamagableType",
                                record.model_before
                            )
                    end

                    if record.actor_changed
                        and record.actor_before ~= nil
                    then
                        actor_ok,
                            actor_error =
                            write_field(
                                record.actor,
                                "DamagableType",
                                record.actor_before
                            )
                    end

                    local restored =
                        model_ok and actor_ok

                    local restore_error = ""

                    if not restored then
                        restore_error =
                            "MODEL=" ..
                            tostring(model_error) ..
                            " | ACTOR=" ..
                            tostring(actor_error)
                    end

                    FileIO.append(
                        path,
                        TSV.encode({
                            Clock.now(),
                            DAMAGE_FUNCTION,
                            object_path(context),
                            record.target_guild_key,
                            table.concat({
                                "probe=STRUCTURE_DAMAGEABILITY_V1",
                                "phase=POST",
                                "instance_id=" ..
                                    instance_id,
                                "StructurePolicy=BLOCK",
                                "StructureReason=" ..
                                    record.reason,
                                "Restored=" ..
                                    tostring(restored),
                                "RestoreError=" ..
                                    restore_error,
                                "ModelDamagableAfter=" ..
                                    tostring(
                                        enum_value(
                                            read_field(
                                                record.model,
                                                "DamagableType"
                                            )
                                        )
                                    ),
                                "ActorDamagableAfter=" ..
                                    tostring(
                                        enum_value(
                                            read_field(
                                                record.actor,
                                                "DamagableType"
                                            )
                                        )
                                    )
                            }, ";")
                        })
                    )

                    logger:info(
                        "YAPI_DAMAGEABILITY_POST" ..
                        " | instance_id=" ..
                        instance_id ..
                        " | restored=" ..
                        tostring(restored) ..
                        " | model_after=" ..
                        tostring(
                            enum_value(
                                read_field(
                                    record.model,
                                    "DamagableType"
                                )
                            )
                        ) ..
                        " | actor_after=" ..
                        tostring(
                            enum_value(
                                read_field(
                                    record.actor,
                                    "DamagableType"
                                )
                            )
                        ) ..
                        " | restore_error=" ..
                        restore_error
                    )
                end
            )
        end)

    if not restore_ok
        or restore_pre_id == nil
        or restore_post_id == nil
    then
        logger:warn(
            "DamagableType post-hook kaydedilemedi: " ..
            tostring(restore_pre_id)
        )

        return 0
    end

    logger:info(
        "Yapi gecici DamagableType korumasi aktif: " ..
        DAMAGE_FUNCTION
    )

    return 2
end

return StructurePreDamageProbe
