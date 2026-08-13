local UE = require("PalTR.runtime.ue")
local FileIO = require("PalTR.storage.file_io")
local TSV = require("PalTR.storage.tsv")
local Clock = require("PalTR.core.clock")
local Result = require("PalTR.core.result")

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
    logger,
    options
)
    options = options or {}
    return setmetatable({
        path = path,
        registry = registry,
        policy = policy,
        logger = logger,
        audit_enabled = options.audit_enabled == true,
        last_write_error_at = 0,
        last_decision_log_at = {}
    }, Observer)
end

function Observer:_log_decision(level, key, message)
    local now = Clock.now()
    local last = self.last_decision_log_at[key] or 0
    if now - last < 5 then return end

    self.last_decision_log_at[key] = now
    self.logger[level](self.logger, message)
end

function Observer:_append(
    target_path,
    player,
    fields
)
    local now = Clock.now()
    local result = FileIO.append(self.path, TSV.encode({
        now,
        target_path or "",
        player and player.name or "",
        player and player.guild_key or "",
        table.concat(fields or {}, ";")
    }))
    if not result.ok
        and self.logger
        and now - self.last_write_error_at >= 60 then

        self.last_write_error_at = now
        self.logger:error(
            "DAMAGE_AUDIT_WRITE_FAILED | " .. Result.describe(result)
        )
    end
    return result
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
        if self.audit_enabled then
            self:_append(
                defender_path,
                defender_player,
                {
                    "Hook=EnemyPlayerDamagePolicy",
                    "Policy=SKIP",
                    "Reason=NOT_PLAYER_VS_PLAYER"
                }
            )
        end

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

    if self.audit_enabled then
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
    end

    if result.block and applied then
        self:_log_decision(
            "info",
            result.reason .. "|" .. result.state,
            "Oyuncu hasari engellendi: " ..
            result.reason ..
            " | " ..
            result.state
        )
    elseif result.block then
        self:_log_decision(
            "error",
            "APPLY_FAILED|" .. result.reason,
            "Oyuncu hasari engellenemedi: " ..
            apply_error
        )
    end
end

return Observer
