local UE = require("PalTR.runtime.ue")
local Clock = require("PalTR.core.clock")

local PlayerAdapter = {}

function PlayerAdapter.from_connection(context, pawn_param)
    local controller = UE.unwrap(context)
    local pawn = UE.unwrap(pawn_param)
    local player_state =
        UE.read(controller, "PlayerState") or UE.read(pawn, "PlayerState")

    local name = UE.text(UE.read(player_state, "PlayerNamePrivate"))
    local player_id = UE.text(UE.read(player_state, "PlayerId"))
    local key = name .. "#" .. player_id

    return {
        key = key,
        name = name,
        player_id = player_id,
        uid = UE.guid(UE.read(player_state, "PlayerUId")),
        guild_key = "",
        role = -1,
        is_master = false,
        controller = controller,
        pawn = pawn,
        player_state = player_state,
        controller_path = UE.full_name(controller),
        pawn_path = UE.full_name(pawn),
        player_state_path = UE.full_name(player_state),
        first_seen = Clock.now(),
        last_seen = Clock.now(),
        online = true
    }
end

function PlayerAdapter.refresh_authority(player, guild, uid)
    if not player then return end

    local ok_role, role = UE.call(guild, "GetPlayerRole", uid)
    if ok_role then player.role = tonumber(UE.unwrap(role)) or -1 end

    local ok_master, is_master = UE.call(player.pawn, "IsGuildMaster")
    if ok_master then player.is_master = UE.unwrap(is_master) == true end
end

return PlayerAdapter
