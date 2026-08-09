local SnapshotCodec = require("snapshot_codec")

local Transport = {}
Transport.__index = Transport

Transport.MAX_CHUNKS = 64
Transport.MAX_CHUNK_SIZE = 1024

function Transport.new()
    return setmetatable({ transfers = {} }, Transport)
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
        or total < 1 or total > Transport.MAX_CHUNKS
        or index < 1 or index > total
        or #chunk > Transport.MAX_CHUNK_SIZE then
        return false, nil, "chunk"
    end

    local transfer = self.transfers[transfer_id]
    if transfer == nil or transfer.total ~= total then
        transfer = { total = total, chunks = {}, received = 0 }
        self.transfers[transfer_id] = transfer
    end
    if transfer.chunks[index] == nil then
        transfer.chunks[index] = chunk
        transfer.received = transfer.received + 1
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
