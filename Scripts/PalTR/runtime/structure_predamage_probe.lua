local UE = require("PalTR.runtime.ue")
local FileIO = require("PalTR.storage.file_io")
local TSV = require("PalTR.storage.tsv")
local Clock = require("PalTR.core.clock")

local StructurePreDamageProbe = {}

local DAMAGE_FUNCTION =
    "/Script/Pal.PalNetworkMapObjectComponent:RequestDamageMapObject_ToServer"

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

function StructurePreDamageProbe.register(
    hooks,
    path,
    logger
)
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

            local details = {
                "probe=STRUCTURE_PRE_DAMAGE_V1",
                "instance_id=" .. instance_id,
                "attacker_group=" .. attacker_group,
                "attacker_path=" .. attacker_path,

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
                "YAPI_PRE_DAMAGE_PROBE" ..
                " | instance_id=" ..
                tostring(instance_id) ..
                " | saldiran_klan=" ..
                tostring(attacker_group) ..
                " | saldiran=" ..
                attacker_path ..
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

    logger:info(
        "Yapi pre-damage probe aktif: " ..
        DAMAGE_FUNCTION
    )

    return 1
end

return StructurePreDamageProbe