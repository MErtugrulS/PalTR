local SnapshotCodec = require("snapshot_codec")

local Transport = {}
Transport.__index = Transport

Transport.MAX_CHUNKS = 512
Transport.MAX_CHUNK_SIZE = 1024
Transport.MAX_PAYLOAD_SIZE = 96 * 1024
Transport.MAX_TRANSFER_ID_SIZE = 96
Transport.MAX_ACTIVE_TRANSFERS = 8

function Transport.new()
    return setmetatable({
        transfers = {},
        transfer_sequence = 0
    }, Transport)
end

function Transport:_discard_oldest_transfer()
    local oldest_id = nil
    local oldest_sequence = nil
    for transfer_id, transfer in pairs(self.transfers) do
        if oldest_sequence == nil or transfer.sequence < oldest_sequence then
            oldest_id = transfer_id
            oldest_sequence = transfer.sequence
        end
    end
    if oldest_id ~= nil then self.transfers[oldest_id] = nil end
end

function Transport:_begin_transfer(transfer_id, total)
    local active_count = 0
    for _ in pairs(self.transfers) do active_count = active_count + 1 end
    if active_count >= Transport.MAX_ACTIVE_TRANSFERS then
        self:_discard_oldest_transfer()
    end

    self.transfer_sequence = self.transfer_sequence + 1
    local transfer = {
        total = total,
        chunks = {},
        received = 0,
        bytes = 0,
        sequence = self.transfer_sequence
    }
    self.transfers[transfer_id] = transfer
    return transfer
end

function Transport:receive(frame)
    if type(frame) ~= "table" or frame.kind ~= "SNAPSHOT_CHUNK" then
        return false, nil, "frame"
    end
    local transfer_id, index_text, total_text =
        tostring(frame.request_id or ""):match("^([^:]+):(%d+):(%d+)$")
    local index = tonumber(index_text)
    local total = tonumber(total_text)
    local chunk = tostring(frame.payload or "")
    if transfer_id == nil or index == nil or total == nil
        or #transfer_id > Transport.MAX_TRANSFER_ID_SIZE
        or total < 1 or total > Transport.MAX_CHUNKS
        or index < 1 or index > total
        or #chunk > Transport.MAX_CHUNK_SIZE then
        return false, nil, "chunk"
    end

    local transfer = self.transfers[transfer_id]
    if transfer == nil or transfer.total ~= total then
        transfer = self:_begin_transfer(transfer_id, total)
    end
    if transfer.chunks[index] == nil then
        transfer.chunks[index] = chunk
        transfer.received = transfer.received + 1
        transfer.bytes = transfer.bytes + #chunk
        if transfer.bytes > Transport.MAX_PAYLOAD_SIZE then
            self.transfers[transfer_id] = nil
            return false, nil, "payload"
        end
    end
    if transfer.received ~= total then return false, nil, nil end

    local parts = {}
    for part_index = 1, total do
        if transfer.chunks[part_index] == nil then return false, nil, nil end
        table.insert(parts, transfer.chunks[part_index])
    end
    self.transfers[transfer_id] = nil
    local snapshot, decode_error = SnapshotCodec.decode(table.concat(parts))
    if snapshot == nil then return false, nil, decode_error end
    return true, snapshot, nil
end

return Transport
