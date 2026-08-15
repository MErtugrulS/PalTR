local ClientCodec = require("snapshot_codec")
local ServerCodec = require("PalTR.core.ui_snapshot_codec")

local function equal(actual, expected, label)
    if actual ~= expected then
        error(string.format(
            "%s | expected=%s actual=%s",
            label,
            tostring(expected),
            tostring(actual)
        ))
    end
end

local snapshot = {
    schema_version = 2,
    generated_at = 1712345678,
    player = {
        name = "Oyuncu % 1\nIkinci satir",
        guild_key = "own|guild",
        role = 1,
        is_master = true
    },
    guild = {
        key = "own|guild", name = "Anka Birligi",
        color_id = "azure", emblem_id = "wolf"
    },
    guild_identity = {
        palette_version = 1,
        selected_color_id = "azure",
        selected_emblem_id = "wolf",
        locked = true,
        can_manage = false,
        colors = {
            { id = "azure", hex = "#2F80ED", available = true },
            { id = "red", hex = "#D94A4A", available = false }
        },
        emblems = { { id = "wolf", name = "Kurt" } }
    },
    protection = {
        available = true,
        protected = true,
        reason = "OFFLINE_PROTECTED",
        online_count = 0,
        protected_at = 1712345000,
        raid_open = false,
        raid_window_start = "20:00",
        raid_window_end = "00:00"
    },
    guilds = {
        {
            key = "other",
            name = "Kuzey Birligi",
            color_id = "red",
            emblem_id = "eagle",
            member_count = 4,
            online_count = 2,
            active = true
        }
    },
    members = {
        {
            key = "member-1",
            name = "Ada",
            role = 2,
            is_master = false,
            online = true
        }
    },
    relations = {
        {
            guild_key = "other",
            guild_name = "Kuzey Birligi",
            state = "ALLY_PENDING",
            previous_state = "NEUTRAL",
            requested_by = "own|guild",
            accepted_by = "",
            proposal_direction = "OUTGOING",
            active_at = 100,
            expires_at = 200,
            note = "Teklif % hazir",
            can_manage = true,
            action_reason = "",
            actions = {
                { id = "CANCEL_ALLIANCE", label = "Iptal Et" }
            }
        }
    },
    territories = {
        nodes = {
            {
                node_id = "CAPITAL", display_name = "Anka Baskenti",
                node_type = "CAPITAL", controller_guild = "own|guild",
                controller_name = "Anka Birligi", x = -100.5, y = 200.25,
                z = 3, radius = 250, state = "PROTECTED",
                flag_state = "BOUND"
            }
        },
        boundaries = {
            {
                boundary_id = "own|guild::001",
                controller_guild = "own|guild",
                controller_name = "Anka Birligi", component_index = 1,
                min_x = -200, min_y = 100, max_x = 0, max_y = 300,
                points = {
                    { x = -200.125, y = 100.5 },
                    { x = 0, y = 100.5 },
                    { x = 0, y = 300.75 }
                }
            }
        }
    }
}

local server_payload = assert(ServerCodec.encode(snapshot))
local client_snapshot = assert(ClientCodec.decode(server_payload))
equal(client_snapshot.player.name, snapshot.player.name,
    "server to client escaped player name")
equal(client_snapshot.guilds[1].online_count, 2,
    "server to client guild count")
equal(client_snapshot.guild.color_id, "azure",
    "server to client own guild color")
equal(client_snapshot.guilds[1].emblem_id, "eagle",
    "server to client other guild emblem")
equal(#client_snapshot.guild_identity.colors, 2,
    "server to client identity palette")
equal(client_snapshot.protection.protected, true,
    "server to client protection state")
equal(client_snapshot.protection.raid_window_start, "20:00",
    "server to client raid window")
equal(client_snapshot.relations[1].actions[1].id,
    "CANCEL_ALLIANCE", "server to client relation action")
equal(client_snapshot.territories.nodes[1].node_type,
    "CAPITAL", "server to client territory node")
equal(client_snapshot.territories.boundaries[1].points[3].y,
    300.75, "server to client organic boundary point")

local client_payload = assert(ClientCodec.encode(snapshot))
local server_snapshot = assert(ServerCodec.decode(client_payload))
equal(server_snapshot.guild.key, "own|guild",
    "client to server guild key")
equal(server_snapshot.guild_identity.selected_emblem_id, "wolf",
    "client to server identity selection")
equal(server_snapshot.protection.reason, "OFFLINE_PROTECTED",
    "client to server protection reason")
equal(server_snapshot.relations[1].note, "Teklif % hazir",
    "client to server escaped note")
equal(server_snapshot.territories.boundaries[1].controller_guild,
    "own|guild", "client to server territory owner")

local legacy_payload = server_payload
    :gsub("\nguild%.color_id\t[^\n]*", "")
    :gsub("\nguild%.emblem_id\t[^\n]*", "")
    :gsub("\nguild_identity%.[^\n]*", "")
    :gsub("\nguilds%.1%.color_id\t[^\n]*", "")
    :gsub("\nguilds%.1%.emblem_id\t[^\n]*", "")
    :gsub("schema_version\t2", "schema_version\t1", 1)
local legacy_snapshot = assert(ClientCodec.decode(legacy_payload))
equal(legacy_snapshot.schema_version, 1, "legacy v1 decoded")
equal(legacy_snapshot.guild.color_id, "", "legacy neutral guild color")
equal(legacy_snapshot.guild_identity.palette_version, 0,
    "legacy neutral identity")

local invalid, invalid_error = ClientCodec.decode(
    "schema_version\t1\ngenerated_at\t1\nguilds.count\tbad"
)
equal(invalid, nil, "invalid count rejected")
equal(invalid_error, "header", "invalid count error")

local count_bomb = table.concat({
    "schema_version\t1",
    "generated_at\t1",
    "guilds.count\t999999999",
    "members.count\t0",
    "relations.count\t0"
}, "\n")
local client_bomb, client_bomb_error = ClientCodec.decode(count_bomb)
equal(client_bomb, nil, "client count bomb rejected")
equal(client_bomb_error, "count", "client count bomb error")
local server_bomb, server_bomb_error = ServerCodec.decode(count_bomb)
equal(server_bomb, nil, "server count bomb rejected")
equal(server_bomb_error, "count", "server count bomb error")

local truncated = table.concat({
    "schema_version\t1",
    "generated_at\t1",
    "player.name\tAda",
    "player.guild_key\town",
    "player.role\t1",
    "player.is_master\t1",
    "guild.key\town",
    "guild.name\tAnka",
    "guilds.count\t1",
    "members.count\t0",
    "relations.count\t0",
    "guilds.1.key\tother"
}, "\n")
local truncated_snapshot, truncated_error = ClientCodec.decode(truncated)
equal(truncated_snapshot, nil, "truncated guild rejected")
equal(truncated_error, "guilds", "truncated guild error")

print("PALTR_UI_SNAPSHOT_CODEC_TEST_OK")
