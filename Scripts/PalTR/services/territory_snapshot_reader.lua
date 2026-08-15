local FileIO = require("PalTR.storage.file_io")
local TSV = require("PalTR.storage.tsv")

local Reader = {}

Reader.MAX_NODES = 512
Reader.MAX_BOUNDARIES = 64
Reader.MAX_POINTS_PER_BOUNDARY = 256
Reader.MAX_TOTAL_POINTS = 2048
Reader.MAX_INPUT_POINTS_PER_BOUNDARY = 4096

local function text(value)
    return tostring(value or "")
end

local function finite_number(value)
    value = tonumber(value)
    if value == nil or value ~= value
        or value == math.huge or value == -math.huge then
        return nil
    end
    return value
end

local function read_rows(path, limit)
    if text(path) == "" then return {} end
    local result = FileIO.read_lines(path)
    if result.ok ~= true then return {} end

    local rows = {}
    for index, line in ipairs(result.value or {}) do
        if index > 1 and line ~= "" and #rows < limit then
            table.insert(rows, TSV.decode(line))
        end
    end
    return rows
end

local function decode_points(value)
    local points = {}
    for encoded in (text(value) .. ";"):gmatch("(.-);") do
        if encoded ~= "" then
            local x, y = encoded:match("^([^,]+),([^,]+)$")
            x, y = finite_number(x), finite_number(y)
            if x == nil or y == nil then return nil end
            table.insert(points, { x = x, y = y })
            if #points > Reader.MAX_INPUT_POINTS_PER_BOUNDARY then return nil end
        end
    end
    return points
end

local function decimate(points, maximum)
    if #points <= maximum then return points end
    local result = {}
    for index = 0, maximum - 1 do
        local source_index = math.floor(index * #points / maximum) + 1
        table.insert(result, points[source_index])
    end
    return result
end

function Reader.read(paths)
    paths = paths or {}
    local nodes = {}
    for _, columns in ipairs(read_rows(
        paths.territory_snapshot,
        Reader.MAX_NODES
    )) do
        local x = finite_number(columns[6])
        local y = finite_number(columns[7])
        local z = finite_number(columns[8])
        local radius = finite_number(columns[9])
        if text(columns[1]) ~= "" and x ~= nil and y ~= nil
            and z ~= nil and radius ~= nil and radius > 0 then
            table.insert(nodes, {
                node_id = text(columns[1]),
                display_name = text(columns[2]),
                node_type = text(columns[3]),
                controller_guild = text(columns[4]),
                controller_name = text(columns[5]),
                x = x,
                y = y,
                z = z,
                radius = radius,
                state = text(columns[10]),
                flag_state = text(columns[11])
            })
        end
    end

    local boundaries = {}
    local total_points = 0
    for _, columns in ipairs(read_rows(
        paths.territory_boundaries,
        Reader.MAX_BOUNDARIES
    )) do
        local points = decode_points(columns[10])
        local declared_count = finite_number(columns[9])
        local decoded_count = points and #points or 0
        if points ~= nil then
            points = decimate(points, Reader.MAX_POINTS_PER_BOUNDARY)
        end
        if text(columns[1]) ~= "" and text(columns[2]) ~= ""
            and points ~= nil and #points >= 3
            and declared_count == decoded_count then
            if total_points + #points > Reader.MAX_TOTAL_POINTS then break end
            table.insert(boundaries, {
                boundary_id = text(columns[1]),
                controller_guild = text(columns[2]),
                controller_name = text(columns[3]),
                component_index = finite_number(columns[4]) or 0,
                min_x = finite_number(columns[5]) or 0,
                min_y = finite_number(columns[6]) or 0,
                max_x = finite_number(columns[7]) or 0,
                max_y = finite_number(columns[8]) or 0,
                points = points
            })
            total_points = total_points + #points
        end
    end

    return { nodes = nodes, boundaries = boundaries }
end

return Reader
