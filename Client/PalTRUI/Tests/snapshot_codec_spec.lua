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
    schema_version = 1,
    generated_at = 1712345678,
    player = {
        name = "Oyuncu % 1\nIkinci satir",
        guild_key = "own|guild",
        role = 1,
        is_master = true
    },
    guild = { key = "own|guild", name = "Anka Birligi" },
    guilds = {
        {
            key = "other",
            name = "Kuzey Birligi",
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
    }
}

local server_payload = assert(ServerCodec.encode(snapshot))
local client_snapshot = assert(ClientCodec.decode(server_payload))
equal(client_snapshot.player.name, snapshot.player.name,
    "server to client escaped player name")
equal(client_snapshot.guilds[1].online_count, 2,
    "server to client guild count")
equal(client_snapshot.relations[1].actions[1].id,
    "CANCEL_ALLIANCE", "server to client relation action")

local client_payload = assert(ClientCodec.encode(snapshot))
local server_snapshot = assert(ServerCodec.decode(client_payload))
equal(server_snapshot.guild.key, "own|guild",
    "client to server guild key")
equal(server_snapshot.relations[1].note, "Teklif % hazir",
    "client to server escaped note")

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

print("PALTR_UI_SNAPSHOT_CODEC_TEST_OK")
