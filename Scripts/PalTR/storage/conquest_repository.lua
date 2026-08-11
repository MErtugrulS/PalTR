local FileIO = require("PalTR.storage.file_io")
local TSV = require("PalTR.storage.tsv")
local Tables = require("PalTR.core.table_utils")

local Repository = {}
Repository.__index = Repository

local function number(value)
    return tonumber(value) or 0
end

local function load_table(path, mapper)
    local records = {}
    local result = FileIO.read_lines(path)

    if not result.ok then
        return records
    end

    for index, line in ipairs(result.value or {}) do
        if index > 1 and line ~= "" then
            local record = mapper(TSV.decode(line))

            if record and record.key and record.key ~= "" then
                records[record.key] = record
            end
        end
    end

    return records
end

local function save_table(path, header, records, serializer)
    local lines = { header }

    for _, key in ipairs(Tables.sorted_keys(records)) do
        table.insert(lines, TSV.encode(serializer(records[key])))
    end

    return FileIO.overwrite(path, lines)
end

function Repository.new(paths)
    return setmetatable({ paths = paths }, Repository)
end

function Repository:load_nodes()
    return load_table(self.paths.conquest_nodes, function(c)
        local flag_state = c[14]
        if flag_state == nil or flag_state == "" then
            local fallen = c[9] == "OCCUPIED"
                or c[9] == "CONQUERED"
                or c[9] == "RESTORED"
            flag_state = fallen and "MISSING" or "BOUND"
        end
        local legacy_flag_reference = c[15] or ""
        if legacy_flag_reference == ""
            and flag_state == "MISSING"
            and c[10] ~= c[11] then
            legacy_flag_reference = c[4] or ""
        end

        return {
            key = c[1],
            node_id = c[1],
            guild_key = c[2],
            node_type = c[3],
            flag_reference = c[4],
            x = number(c[5]),
            y = number(c[6]),
            z = number(c[7]),
            parent_node_id = c[8],
            state = c[9],
            original_owner = c[10],
            current_controller = c[11],
            created_at = number(c[12]),
            updated_at = number(c[13]),
            flag_state = flag_state,
            legacy_flag_reference = legacy_flag_reference
        }
    end)
end

function Repository:save_nodes(records)
    return save_table(
        self.paths.conquest_nodes,
        "node_id\tguild_key\tnode_type\tflag_reference\tlocation_x\tlocation_y\tlocation_z\tparent_node_id\tstate\toriginal_owner\tcurrent_controller\tcreated_at\tupdated_at\tflag_state\tlegacy_flag_reference",
        records,
        function(r)
            return {
                r.node_id, r.guild_key, r.node_type,
                r.flag_reference, r.x, r.y, r.z,
                r.parent_node_id, r.state,
                r.original_owner, r.current_controller,
                r.created_at, r.updated_at, r.flag_state,
                r.legacy_flag_reference
            }
        end
    )
end

function Repository:load_edges()
    return load_table(self.paths.conquest_edges, function(c)
        return {
            key = c[1],
            edge_id = c[1],
            node_a = c[2],
            node_b = c[3],
            created_at = number(c[4])
        }
    end)
end

function Repository:save_edges(records)
    return save_table(
        self.paths.conquest_edges,
        "edge_id\tnode_a\tnode_b\tcreated_at",
        records,
        function(r)
            return { r.edge_id, r.node_a, r.node_b, r.created_at }
        end
    )
end

function Repository:load_campaigns()
    return load_table(self.paths.conquest_campaigns, function(c)
        return {
            key = c[1],
            campaign_id = c[1],
            war_id = c[2],
            attacker_guild = c[3],
            defender_guild = c[4],
            state = c[5],
            active_target_node_id = c[6],
            siege_camp_reference = c[7],
            siege_x = number(c[8]),
            siege_y = number(c[9]),
            siege_z = number(c[10]),
            rearm_until = number(c[11]),
            previous_relation_state = c[12],
            created_at = number(c[13]),
            updated_at = number(c[14])
        }
    end)
end

function Repository:save_campaigns(records)
    return save_table(
        self.paths.conquest_campaigns,
        "campaign_id\twar_id\tattacker_guild\tdefender_guild\tstate\tactive_target_node_id\tsiege_camp_reference\tsiege_x\tsiege_y\tsiege_z\trearm_until\tprevious_relation_state\tcreated_at\tupdated_at",
        records,
        function(r)
            return {
                r.campaign_id, r.war_id,
                r.attacker_guild, r.defender_guild,
                r.state, r.active_target_node_id,
                r.siege_camp_reference,
                r.siege_x, r.siege_y, r.siege_z,
                r.rearm_until, r.previous_relation_state,
                r.created_at, r.updated_at
            }
        end
    )
end

function Repository:load_occupations()
    return load_table(self.paths.conquest_occupations, function(c)
        local state = c[5]
        local previous_state = c[6]
        local counter_flag_reference = c[13] or ""
        if counter_flag_reference == "" then
            if state == "COUNTER_ATTACK" then state = "OCCUPIED" end
            if previous_state == "COUNTER_ATTACK" then
                previous_state = "OCCUPIED"
            end
        end
        return {
            key = c[1],
            node_id = c[1],
            original_owner = c[2],
            occupying_guild = c[3],
            war_id = c[4],
            state = state,
            previous_state = previous_state,
            occupation_started_at = number(c[7]),
            remaining_seconds = number(c[8]),
            last_resumed_at = number(c[9]),
            loot_manifest_id = c[10],
            frontline_state = c[11],
            updated_at = number(c[12]),
            counter_flag_reference = counter_flag_reference,
            counter_remaining_seconds = number(c[14]),
            counter_last_resumed_at = number(c[15]),
            counter_flag_x = number(c[16]),
            counter_flag_y = number(c[17]),
            counter_flag_z = number(c[18])
        }
    end)
end

function Repository:save_occupations(records)
    return save_table(
        self.paths.conquest_occupations,
        "node_id\toriginal_owner\toccupying_guild\twar_id\tstate\tprevious_state\toccupation_started_at\tremaining_seconds\tlast_resumed_at\tloot_manifest_id\tfrontline_state\tupdated_at\tcounter_flag_reference\tcounter_remaining_seconds\tcounter_last_resumed_at\tcounter_flag_x\tcounter_flag_y\tcounter_flag_z",
        records,
        function(r)
            return {
                r.node_id, r.original_owner,
                r.occupying_guild, r.war_id,
                r.state, r.previous_state,
                r.occupation_started_at,
                r.remaining_seconds, r.last_resumed_at,
                r.loot_manifest_id, r.frontline_state,
                r.updated_at, r.counter_flag_reference,
                r.counter_remaining_seconds,
                r.counter_last_resumed_at,
                r.counter_flag_x, r.counter_flag_y,
                r.counter_flag_z
            }
        end
    )
end

function Repository:load_loot_manifests()
    return load_table(self.paths.conquest_loot, function(c)
        return {
            key = c[1],
            manifest_id = c[1],
            node_id = c[2],
            war_id = c[3],
            owner_guild = c[4],
            state = c[5],
            created_at = number(c[6]),
            extracted_at = number(c[7])
        }
    end)
end

function Repository:save_loot_manifests(records)
    return save_table(
        self.paths.conquest_loot,
        "manifest_id\tnode_id\twar_id\towner_guild\tstate\tcreated_at\textracted_at",
        records,
        function(r)
            return {
                r.manifest_id, r.node_id, r.war_id,
                r.owner_guild, r.state,
                r.created_at, r.extracted_at
            }
        end
    )
end

function Repository:load_loot_items()
    return load_table(self.paths.conquest_loot_items, function(c)
        return {
            key = c[1],
            item_key = c[1],
            manifest_id = c[2],
            item_id = c[3],
            item_selector = c[4],
            quantity = number(c[5]),
            tier = c[6],
            category = c[7]
        }
    end)
end

function Repository:save_loot_items(records)
    return save_table(
        self.paths.conquest_loot_items,
        "item_key\tmanifest_id\titem_id\titem_selector\tquantity\ttier\tcategory",
        records,
        function(r)
            return {
                r.item_key, r.manifest_id,
                r.item_id, r.item_selector,
                r.quantity, r.tier, r.category
            }
        end
    )
end

return Repository
