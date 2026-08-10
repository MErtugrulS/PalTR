local captured = {}
package.loaded["PalTR.runtime.private_messenger"] = {
    send = function(_controller, player, message)
        table.insert(captured, {
            player = player,
            message = message
        })
        return true
    end
}
package.loaded["PalTR.services.ui_snapshot_publisher"] = nil

local Publisher = require("PalTR.services.ui_snapshot_publisher")
local ServerWire = require("PalTR.core.ui_wire")
local ClientWire = require("ui_wire")
local Transport = require("snapshot_transport")

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
    generated_at = 700,
    player = {
        name = "Ada",
        guild_key = "own",
        role = 1,
        is_master = true
    },
    guild = { key = "own", name = "Anka Birligi" },
    guilds = {
        {
            key = "north",
            name = string.rep("Kuzey Birligi ", 30),
            member_count = 4,
            online_count = 2,
            active = true
        }
    },
    members = {
        {
            key = "member-1",
            name = "Ada",
            role = 1,
            is_master = true,
            online = true
        }
    },
    relations = {
        {
            guild_key = "north",
            guild_name = "Kuzey Birligi",
            state = "NEUTRAL",
            previous_state = "NEUTRAL",
            requested_by = "",
            accepted_by = "",
            proposal_direction = "none",
            active_at = 0,
            expires_at = 0,
            note = "",
            can_manage = true,
            action_reason = "",
            actions = {
                { id = "PROPOSE_ALLIANCE", label = "Ittifak Teklif Et" }
            }
        }
    }
}

local service = {
    build = function() return snapshot end
}
local player = {
    key = "ada#1",
    name = "Ada",
    online = true,
    controller = {},
    player_state = {}
}
local publisher = Publisher.new(service, nil)
equal(Publisher.MAX_CHUNKS, Transport.MAX_CHUNKS,
    "server and client chunk limits match")
local published, chunk_count = publisher:publish(player, true)
equal(published, true, "snapshot published")
equal(chunk_count > 1, true, "snapshot split into chunks")
equal(#captured, chunk_count, "all chunks sent privately")

local frames = {}
for index, item in ipairs(captured) do
    equal(item.player, player, "chunk keeps target player")
    equal(#item.message <= 1024, true, "wire frame stays below probe limit")
    local server_frame = assert(ServerWire.decode(item.message))
    local client_frame = assert(ClientWire.decode(item.message))
    equal(client_frame.kind, server_frame.kind, "wire contracts match")
    frames[index] = client_frame
end

local transport = Transport.new()
local complete, received
for index = #frames, 1, -1 do
    complete, received = transport:receive(frames[index])
end
equal(complete, true, "out of order chunks completed")
equal(received.player.name, "Ada", "player reached client")
equal(received.guilds[1].online_count, 2, "guild data reached client")
equal(received.relations[1].actions[1].id,
    "PROPOSE_ALLIANCE", "relation action reached client")

local before_unchanged = #captured
local unchanged, unchanged_reason = publisher:publish(player, false)
equal(unchanged, true, "unchanged snapshot accepted")
equal(unchanged_reason, "unchanged", "unchanged snapshot deduplicated")
equal(#captured, before_unchanged, "unchanged snapshot not resent")

local invalid, _, invalid_error = transport:receive({
    kind = "SNAPSHOT_CHUNK",
    request_id = "bad:0:65",
    payload = "x"
})
equal(invalid, false, "invalid chunk rejected")
equal(invalid_error, "chunk", "invalid chunk error")

local extended, _, extended_error = transport:receive({
    kind = "SNAPSHOT_CHUNK",
    request_id = "extended:1:65",
    payload = "x"
})
equal(extended, false, "extended transfer remains incomplete")
equal(extended_error, nil, "extended transfer accepted")

local oversized_id, _, oversized_id_error = transport:receive({
    kind = "SNAPSHOT_CHUNK",
    request_id = string.rep("x", Transport.MAX_TRANSFER_ID_SIZE + 1)
        .. ":1:1",
    payload = "x"
})
equal(oversized_id, false, "oversized transfer id rejected")
equal(oversized_id_error, "chunk", "oversized transfer id error")

local bounded = Transport.new()
for index = 1, Transport.MAX_ACTIVE_TRANSFERS + 1 do
    bounded:receive({
        kind = "SNAPSHOT_CHUNK",
        request_id = string.format("bounded-%d:1:2", index),
        payload = "x"
    })
end
local active_count = 0
for _ in pairs(bounded.transfers) do active_count = active_count + 1 end
equal(active_count, Transport.MAX_ACTIVE_TRANSFERS,
    "incomplete transfers stay bounded")
equal(bounded.transfers["bounded-1"], nil,
    "oldest incomplete transfer evicted")

print("PALTR_UI_SNAPSHOT_TRANSPORT_TEST_OK")
