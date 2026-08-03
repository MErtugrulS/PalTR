local UE = require("PalTR.runtime.ue")
local FileIO = require("PalTR.storage.file_io")
local TSV = require("PalTR.storage.tsv")
local Clock = require("PalTR.core.clock")

local Observer = {}
Observer.__index = Observer

local function find_player_by_pawn_path(
    registry,
    pawn_path
)
    for _, player in pairs(
        registry.runtime_players or {}
    ) do
        if player.pawn_path == pawn_path then
            return player
        end
    end

    return nil
end

local function read_field(struct, field)
    if struct == nil then
        return nil
    end

    local ok, value = pcall(function()
        return struct[field]
    end)

    if not ok then
        return nil
    end

    return value
end

local function render(value)
    if value == nil then
        return ""
    end

    local value_type = type(value)

    if value_type == "string"
        or value_type == "number"
        or value_type == "boolean" then

        return tostring(value)
    end

    local text = UE.text(value)

    if text ~= "" then
        return text
    end

    local ok, full_name = pcall(function()
        return UE.full_name(value)
    end)

    if ok and full_name ~= nil then
        return tostring(full_name)
    end

    return ""
end

function Observer.new(
    path,
    registry,
    policy,
    logger
)
    return setmetatable({
        path = path,
        registry = registry,
        policy = policy,
        logger = logger
    }, Observer)
end

function Observer:_append(
    target_path,
    player,
    fields
)
    FileIO.append(self.path, TSV.encode({
        Clock.now(),
        target_path or "",
        player and player.name or "",
        player and player.guild_key or "",
        table.concat(fields or {}, ";")
    }))
end

function Observer:on_enemy_player_damage_request(
    context,
    info_param,
    defender_param
)
    local controller = UE.unwrap(context)
    local info = UE.unwrap(info_param)
    local defender = UE.unwrap(defender_param)

    local defender_path = UE.full_name(defender)

    local attacker_player =
        self.registry:find_by_controller(
            controller
        )

    local defender_player =
        find_player_by_pawn_path(
            self.registry,
            defender_path
        )

    local is_pvp =
        read_field(
            info,
            "IsPlayerVsPlayerDamage"
        ) == true

    if not is_pvp then
        self:_append(
            defender_path,
            defender_player,
            {
                "Hook=EnemyPlayerDamagePolicy",
                "Policy=SKIP",
                "Reason=NOT_PLAYER_VS_PLAYER"
            }
        )

        return
    end

    local result =
        self.policy:evaluate_player_damage(
            attacker_player,
            defender_player
        )

    local applied = false
    local apply_error = ""

    if result.block then
        local ok, error_message =
            pcall(function()
                info.NoDamage = true
                info_param:set(info)
            end)

        applied = ok

        if not ok then
            apply_error =
                tostring(error_message)
        end
    end

    local fields = {
        "Hook=EnemyPlayerDamagePolicy",

        "Policy=" ..
            (
                result.block
                and "BLOCK"
                or "ALLOW"
            ),

        "Reason=" .. result.reason,
        "RelationState=" .. result.state,
        "Applied=" .. tostring(applied),

        "AttackerPlayer=" ..
            (
                attacker_player
                and attacker_player.name
                or ""
            ),

        "AttackerGuild=" ..
            (
                attacker_player
                and attacker_player.guild_key
                or ""
            ),

        "DefenderPlayer=" ..
            (
                defender_player
                and defender_player.name
                or ""
            ),

        "DefenderGuild=" ..
            (
                defender_player
                and defender_player.guild_key
                or ""
            ),

        "NativeDamageValue=" ..
            render(
                read_field(
                    info,
                    "NativeDamageValue"
                )
            ),

        "BasePower=" ..
            render(
                read_field(
                    info,
                    "BasePower"
                )
            ),

        "NoDamage=" ..
            render(
                read_field(
                    info,
                    "NoDamage"
                )
            )
    }

    if apply_error ~= "" then
        table.insert(
            fields,
            "ApplyError=" .. apply_error
        )
    end

    self:_append(
        defender_path,
        defender_player,
        fields
    )

    if result.block and applied then
        self.logger:info(
            "Oyuncu hasari engellendi: " ..
            result.reason ..
            " | " ..
            result.state
        )
    elseif result.block then
        self.logger:error(
            "Oyuncu hasari engellenemedi: " ..
            apply_error
        )
    else
        self.logger:info(
            "Oyuncu hasarina izin verildi: " ..
            result.reason ..
            " | " ..
            result.state
        )
    end
end

function Observer:on_player_damage(
    context,
    result_param
)
    local pawn = UE.unwrap(context)
    local result = UE.unwrap(result_param)

    local pawn_path = UE.full_name(pawn)

    local target_player =
        find_player_by_pawn_path(
            self.registry,
            pawn_path
        )

    self:_append(
        pawn_path,
        target_player,
        {
            "Hook=PlayerDamageResult",

            "Damage=" ..
                render(
                    read_field(
                        result,
                        "Damage"
                    )
                ),

            "ActualDamage=" ..
                render(
                    read_field(
                        result,
                        "ActualDamage"
                    )
                ),

            "BasePower=" ..
                render(
                    read_field(
                        result,
                        "BasePower"
                    )
                ),

            "Attacker=" ..
                render(
                    read_field(
                        result,
                        "Attacker"
                    )
                )
        }
    )
end

return Observer
