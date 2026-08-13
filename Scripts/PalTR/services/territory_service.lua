local FileIO = require("PalTR.storage.file_io")
local TSV = require("PalTR.storage.tsv")
local Tables = require("PalTR.core.table_utils")
local States = require("PalTR.domain.conquest_states")
local Rules = require("PalTR.domain.territory_rules")
local PlayerLocation = require("PalTR.runtime.player_location_adapter")
local Announcer = require("PalTR.runtime.announcer")

local Territory = {}
Territory.__index = Territory

local SNAPSHOT_HEADER =
    "node_id\tdisplay_name\tnode_type\tcontroller_guild\tcontroller_name\tcenter_x_meters\tcenter_y_meters\tcenter_z_meters\tradius_meters\tstate\tflag_state"
local BOUNDARY_SNAPSHOT_HEADER =
    "boundary_id\tcontroller_guild\tcontroller_name\tcomponent_index\tmin_x_meters\tmin_y_meters\tmax_x_meters\tmax_y_meters\tpoint_count\tboundary_points"

local function text(value)
    return tostring(value or "")
end

local function ordered_outposts(nodes, guild_key)
    local result = {}
    for _, node in pairs(nodes or {}) do
        if node.node_type == States.NODE_TYPE.OUTPOST
            and node.current_controller == guild_key then
            table.insert(result, node)
        end
    end
    table.sort(result, function(first, second)
        if first.created_at ~= second.created_at then
            return (tonumber(first.created_at) or 0)
                < (tonumber(second.created_at) or 0)
        end
        return text(first.node_id) < text(second.node_id)
    end)
    return result
end

function Territory.new(paths, config, registry, conquest, logger, options)
    options = options or {}
    return setmetatable({
        paths = paths,
        config = config.conquest or {},
        registry = registry,
        conquest = conquest,
        logger = logger,
        position_reader = options.position_reader or PlayerLocation.read,
        announce = options.announce or Announcer.send,
        terrain_sampler = options.terrain_sampler,
        player_nodes = {},
        snapshot_signature = nil,
        boundary_snapshot_signature = nil,
        atlas_signature = nil,
        atlas = nil
    }, Territory)
end

function Territory:set_world_context(context)
    local sampler = self.terrain_sampler
    if sampler == nil or type(sampler.set_context) ~= "function" then
        return false
    end
    local before = tonumber(sampler.revision) or 0
    local ready = sampler:set_context(context)
    if ready and (tonumber(sampler.revision) or 0) ~= before then
        self.atlas = nil
        self.atlas_signature = nil
    end
    return ready
end

function Territory:_guild_name(guild_key)
    local guild = self.registry.guilds
        and self.registry.guilds[text(guild_key)]
    if guild and text(guild.name) ~= "" then return text(guild.name) end
    return text(guild_key)
end

function Territory:display_name(node)
    if text(node and node.display_name) ~= "" then
        return text(node.display_name)
    end

    local guild_key = text(node and node.current_controller)
    local guild_name = self:_guild_name(guild_key)
    if node and node.node_type == States.NODE_TYPE.CAPITAL then
        return guild_name .. " Baskenti"
    end

    for index, candidate in ipairs(
        ordered_outposts(self.conquest.nodes, guild_key)
    ) do
        if candidate.node_id == node.node_id then
            return guild_name .. " " .. tostring(index) .. ". Karakolu"
        end
    end

    return guild_name .. " Karakolu"
end

function Territory:_snapshot_lines()
    local lines = { SNAPSHOT_HEADER }
    for _, node_id in ipairs(Tables.sorted_keys(self.conquest.nodes)) do
        local node = self.conquest.nodes[node_id]
        local radius = Rules.radius_for(node, self.config)
        if text(node.current_controller) ~= "" and radius > 0 then
            table.insert(lines, TSV.encode({
                node.node_id,
                self:display_name(node),
                node.node_type,
                node.current_controller,
                self:_guild_name(node.current_controller),
                node.x,
                node.y,
                node.z,
                radius,
                node.state,
                node.flag_state
            }))
        end
    end
    return lines
end

function Territory:_geometry_signature()
    local values = {
        text(self.config.territory_border_irregularity),
        text(self.config.territory_boundary_sample_meters),
        text(self.config.territory_boundary_max_cells),
        text(self.config.territory_boundary_min_component_area_square_meters)
    }
    table.insert(values, text(
        self.terrain_sampler and self.terrain_sampler.revision or 0
    ))
    for _, node_id in ipairs(Tables.sorted_keys(self.conquest.nodes)) do
        local node = self.conquest.nodes[node_id]
        table.insert(values, table.concat({
            text(node.node_id),
            text(node.node_type),
            text(node.current_controller),
            text(node.x),
            text(node.y),
            text(Rules.radius_for(node, self.config))
        }, "|"))
    end
    return table.concat(values, "\n")
end

function Territory:_ensure_atlas()
    local signature = self:_geometry_signature()
    if self.atlas == nil or self.atlas_signature ~= signature then
        self.atlas = Rules.build_atlas(
            self.conquest.nodes,
            self.config,
            self.terrain_sampler
        )
        self.atlas_signature = signature
    end
    return self.atlas
end

local function encode_points(points)
    local encoded = {}
    for _, value in ipairs(points or {}) do
        table.insert(encoded, string.format("%.3f,%.3f", value.x, value.y))
    end
    return table.concat(encoded, ";")
end

function Territory:_boundary_snapshot_lines(atlas)
    local lines = { BOUNDARY_SNAPSHOT_HEADER }
    for _, component in ipairs(atlas and atlas.components or {}) do
        local bounds = component.bounds
        table.insert(lines, TSV.encode({
            component.boundary_id,
            component.controller_guild,
            self:_guild_name(component.controller_guild),
            component.component_index,
            string.format("%.3f", bounds.min_x),
            string.format("%.3f", bounds.min_y),
            string.format("%.3f", bounds.max_x),
            string.format("%.3f", bounds.max_y),
            #component.points,
            encode_points(component.points)
        }))
    end
    return lines
end

function Territory:write_snapshot()
    local atlas = self:_ensure_atlas()
    local lines = self:_snapshot_lines()
    local signature = table.concat(lines, "\n")
    if signature ~= self.snapshot_signature
        or not FileIO.exists(self.paths.territory_snapshot) then
        local result = FileIO.overwrite(self.paths.territory_snapshot, lines)
        if not result.ok then return result end
        self.snapshot_signature = signature
    end

    local boundary_path = self.paths.territory_boundaries
    if text(boundary_path) ~= "" then
        local boundary_lines = self:_boundary_snapshot_lines(atlas)
        local boundary_signature = table.concat(boundary_lines, "\n")
        if boundary_signature ~= self.boundary_snapshot_signature
            or not FileIO.exists(boundary_path) then
            local result = FileIO.overwrite(boundary_path, boundary_lines)
            if not result.ok then return result end
            self.boundary_snapshot_signature = boundary_signature
        end
    end

    return { ok = true }
end

function Territory:_refresh_player(player)
    local location = self.position_reader(player, self.config)
    if location == nil then return end

    local previous = self.player_nodes[player.key]
    local node = Rules.resolve(
        location,
        self.conquest.nodes,
        self.config,
        previous,
        self:_ensure_atlas()
    )
    local current = node and node.node_id or nil
    self.player_nodes[player.key] = current

    if current ~= nil and current ~= previous then
        self.announce(
            player.controller,
            self:display_name(node) .. " bolgesine girdiniz.",
            self.logger
        )
    end
end

function Territory:refresh()
    self:_ensure_atlas()
    local active = {}
    for key, player in pairs(self.registry.runtime_players or {}) do
        if player.online and player.controller ~= nil and player.pawn ~= nil then
            active[key] = true
            self:_refresh_player(player)
        end
    end

    for key in pairs(self.player_nodes) do
        if not active[key] then self.player_nodes[key] = nil end
    end

    return self:write_snapshot()
end

return Territory
