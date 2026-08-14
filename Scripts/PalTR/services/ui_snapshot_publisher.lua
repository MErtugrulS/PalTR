local UIWire = require("PalTR.core.ui_wire")
local SnapshotCodec = require("PalTR.core.ui_snapshot_codec")
local PrivateMessenger = require("PalTR.runtime.private_messenger")

local Publisher = {}
Publisher.__index = Publisher

Publisher.CHUNK_SIZE = 180
Publisher.MAX_CHUNKS = 512

local function identity(player)
    return tostring(player and (player.key or player.uid or player.name) or "")
end

local function fingerprint(payload)
    return (payload:gsub("generated_at\t[^\n]*", "generated_at\t", 1))
end

local function warn(publisher, message)
    local logger = publisher and publisher.logger
    if logger == nil then return end
    pcall(function() logger:warn(message) end)
end

function Publisher.new(snapshot_service, logger)
    return setmetatable({
        snapshot_service = snapshot_service,
        logger = logger,
        last_fingerprints = {},
        next_transfer_id = 0
    }, Publisher)
end

function Publisher:publish(player, force)
    if type(player) ~= "table" or player.controller == nil then
        return false, "player"
    end
    local snapshot = self.snapshot_service:build(player)
    local payload, encode_error = SnapshotCodec.encode(snapshot)
    if payload == nil then
        warn(self, "UI_SNAPSHOT_ENCODE_HATA | " .. tostring(encode_error))
        return false, encode_error
    end

    local player_id = identity(player)
    local current_fingerprint = fingerprint(payload)
    if force ~= true and self.last_fingerprints[player_id] == current_fingerprint then
        return true, "unchanged"
    end

    local total = math.max(1, math.ceil(#payload / Publisher.CHUNK_SIZE))
    if total > Publisher.MAX_CHUNKS then
        warn(self, string.format(
            "UI_SNAPSHOT_KAPASITE_HATA | bytes=%d | chunks=%d | limit=%d",
            #payload,
            total,
            Publisher.MAX_CHUNKS
        ))
        return false, "snapshot_too_large"
    end
    self.next_transfer_id = self.next_transfer_id + 1
    local transfer_id = table.concat({
        tostring(snapshot.generated_at),
        tostring(self.next_transfer_id)
    }, "-")
    local frames = {}
    for index = 1, total do
        local first = (index - 1) * Publisher.CHUNK_SIZE + 1
        local chunk = payload:sub(first, first + Publisher.CHUNK_SIZE - 1)
        frames[index] = UIWire.encode(
            "SNAPSHOT_CHUNK",
            table.concat({ transfer_id, index, total }, ":"),
            chunk
        )
    end
    if not PrivateMessenger.send_many(
        player.controller,
        player,
        frames,
        self.logger
    ) then
        warn(self, string.format(
            "UI_SNAPSHOT_GONDERIM_HATA | player=%s | chunks=%d",
            player_id,
            total
        ))
        return false, "send"
    end
    self.last_fingerprints[player_id] = current_fingerprint
    return true, total
end

function Publisher:publish_all(runtime_players)
    local published = 0
    for _, player in pairs(runtime_players or {}) do
        if player.online == true and player.controller ~= nil then
            local ok, result = self:publish(player, false)
            if ok and result ~= "unchanged" then published = published + 1 end
        end
    end
    return published
end

return Publisher
