local FileIO = require("PalTR.storage.file_io")
local TSV = require("PalTR.storage.tsv")
local Tables = require("PalTR.core.table_utils")

local Repositories = {}

local function load_table(path, mapper)
    local result = {}
    local lines = FileIO.read_lines(path)
    if not lines.ok then return result end
    for index, line in ipairs(lines.value) do
        if index > 1 and line ~= "" then
            local record = mapper(TSV.decode(line))
            if record and record.key then result[record.key] = record end
        end
    end
    return result
end

local function save_table(path, header, records, serializer)
    local lines = { header }
    for _, key in ipairs(Tables.sorted_keys(records)) do
        table.insert(lines, TSV.encode(serializer(records[key])))
    end
    return FileIO.overwrite(path, lines)
end

function Repositories.load_guilds(path)
    return load_table(path, function(c)
        return {
            key = c[1],
            name = c[2],
            id = c[3],
            object_path = c[4],
            first_seen = tonumber(c[5]) or 0,
            last_seen = tonumber(c[6]) or 0
        }
    end)
end

function Repositories.save_guilds(path, records)
    return save_table(
        path,
        "guild_key\tguild_name\tguild_id\tobject_path\tfirst_seen\tlast_seen",
        records,
        function(r)
            return {
                r.key, r.name, r.id, r.object_path,
                r.first_seen, r.last_seen
            }
        end
    )
end

function Repositories.load_players(path)
    return load_table(path, function(c)
        return {
            key = c[1],
            name = c[2],
            player_id = c[3],
            uid = c[4],
            guild_key = c[5],
            role = tonumber(c[6]) or -1,
            is_master = c[7] == "true",
            player_state_path = c[8],
            pawn_path = c[9],
            first_seen = tonumber(c[10]) or 0,
            last_seen = tonumber(c[11]) or 0
        }
    end)
end

function Repositories.save_players(path, records)
    return save_table(
        path,
        "player_key\tplayer_name\tplayer_id\tplayer_uid\tguild_key\trole\tis_master\tplayer_state_path\tpawn_path\tfirst_seen\tlast_seen",
        records,
        function(r)
            return {
                r.key, r.name, r.player_id, r.uid, r.guild_key,
                r.role, tostring(r.is_master), r.player_state_path,
                r.pawn_path, r.first_seen, r.last_seen
            }
        end
    )
end

function Repositories.load_relations(path)
    return load_table(path, function(c)
        return {
            key = c[1],
            guild_a = c[2],
            guild_b = c[3],
            state = c[4],
            previous_state = c[5],
            requested_by = c[6],
            accepted_by = c[7],
            created_at = tonumber(c[8]) or 0,
            updated_at = tonumber(c[9]) or 0,
            active_at = tonumber(c[10]) or 0,
            expires_at = tonumber(c[11]) or 0,
            note = c[12] or ""
        }
    end)
end

function Repositories.save_relations(path, records)
    return save_table(
        path,
        "pair_key\tguild_a\tguild_b\tstate\tprevious_state\trequested_by\taccepted_by\tcreated_at\tupdated_at\tactive_at\texpires_at\tnote",
        records,
        function(r)
            return {
                r.key, r.guild_a, r.guild_b, r.state,
                r.previous_state, r.requested_by, r.accepted_by,
                r.created_at, r.updated_at, r.active_at,
                r.expires_at, r.note
            }
        end
    )
end

return Repositories
