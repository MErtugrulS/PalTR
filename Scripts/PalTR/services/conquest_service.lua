local Clock = require("PalTR.core.clock")
local FileIO = require("PalTR.storage.file_io")
local Result = require("PalTR.core.result")
local TSV = require("PalTR.storage.tsv")
local Text = require("PalTR.core.text")
local PairKey = require("PalTR.domain.pair_key")
local Rules = require("PalTR.domain.conquest_rules")
local RaidWindow = require("PalTR.domain.raid_window")
local States = require("PalTR.domain.conquest_states")
local Repository = require("PalTR.storage.conquest_repository")
local Loot = require("PalTR.services.conquest_loot_service")

local Conquest = {}
Conquest.__index = Conquest

local function number(value)
    return tonumber(value) or 0
end

local function text(value)
    return tostring(value or "")
end

local function copy_record(record)
    local copy = {}
    for key, value in pairs(record or {}) do copy[key] = value end
    return copy
end

local function restore_record(record, snapshot)
    for key in pairs(record or {}) do record[key] = nil end
    for key, value in pairs(snapshot or {}) do record[key] = value end
end

local function flag_bound(node)
    return node ~= nil and node.flag_state == States.FLAG.BOUND
end

local function set_controller(node, guild_key)
    guild_key = text(guild_key)
    if node.current_controller ~= guild_key then
        node.display_name = ""
    end
    node.current_controller = guild_key
    node.guild_key = guild_key
end

local function edge_id(first, second)
    first = text(first)
    second = text(second)

    if first > second then
        first, second = second, first
    end

    return first .. "::" .. second
end

local function is_ceasefire(relation)
    if not relation then return false end

    return relation.state == "CEASEFIRE"
        or (
            relation.state == "PEACE_PENDING"
            and relation.previous_state == "CEASEFIRE"
        )
end

function Conquest.new(paths, config, diplomacy, logger, options)
    options = options or {}
    local repository = options.repository or Repository.new(paths)

    return setmetatable({
        paths = paths,
        config = config.conquest or {},
        diplomacy = diplomacy,
        logger = logger,
        clock = options.clock or Clock,
        random = options.random or math.random,
        repository = repository,
        nodes = repository:load_nodes(),
        edges = repository:load_edges(),
        campaigns = repository:load_campaigns(),
        occupations = repository:load_occupations(),
        loot_manifests = repository:load_loot_manifests(),
        loot_items = repository:load_loot_items(),
        damage_policy_signature = nil,
        zone_policy_signature = nil
    }, Conquest)
end

function Conquest:_now(value)
    return number(value or self.clock.now())
end

function Conquest:_event(marker, detail)
    if self.paths and self.paths.conquest_events then
        local result = FileIO.append(
            self.paths.conquest_events,
            TSV.encode({ self:_now(), marker, detail or "" })
        )
        if not result.ok and self.logger then
            self.logger:error(
                "FAZ05_EVENT_WRITE_FAILED | " ..
                Result.describe(result)
            )
        end
    end

    if self.logger then
        self.logger:info(marker .. " | " .. text(detail))
    end
end

function Conquest:_save_campaigns()
    return self.repository:save_campaigns(self.campaigns)
end

function Conquest:_save_occupations()
    return self.repository:save_occupations(self.occupations)
end

function Conquest:_save_loot()
    local manifests = self.repository:save_loot_manifests(
        self.loot_manifests
    )
    if not manifests.ok then return manifests end
    return self.repository:save_loot_items(self.loot_items)
end

function Conquest:_authorized(role)
    if Rules.can_operate(role, self.config) then
        return Result.ok(true)
    end

    return Result.err(
        "CONQUEST_ROLE_REQUIRED",
        "Lider, yardimci lider veya komutan yetkisi gerekli"
    )
end

function Conquest:_relation(first, second)
    local pair = PairKey.create(first, second)
    if not pair.ok then return nil, pair.error.message end

    local relation = self.diplomacy
        and self.diplomacy.relations
        and self.diplomacy.relations[pair.value.key]

    if not relation then
        return nil, "Aktif diplomasi kaydi bulunamadi"
    end

    return relation, nil, pair.value.key
end

function Conquest:_capital_for(guild_key)
    for _, node in pairs(self.nodes) do
        if node.current_controller == guild_key
            and node.node_type == States.NODE_TYPE.CAPITAL
            and flag_bound(node)
            and node.state ~= States.NODE.CAPITAL_DEFEATED then
            return node
        end
    end

    return nil
end

function Conquest:get_node(node_id)
    return self.nodes[text(node_id)]
end

function Conquest:node_for_flag_reference(reference)
    reference = text(reference)

    for _, node in pairs(self.nodes) do
        if reference ~= "" and node.flag_reference == reference then
            return node
        end
    end

    return nil
end

function Conquest:linked_nodes(node_id)
    local result = {}

    for _, edge in pairs(self.edges) do
        if edge.node_a == node_id and self.nodes[edge.node_b] then
            table.insert(result, self.nodes[edge.node_b])
        elseif edge.node_b == node_id and self.nodes[edge.node_a] then
            table.insert(result, self.nodes[edge.node_a])
        end
    end

    table.sort(result, function(a, b) return a.node_id < b.node_id end)
    return result
end

function Conquest:nodes_for_controller(guild_key)
    local result = {}

    for _, node in pairs(self.nodes) do
        if node.current_controller == text(guild_key) then
            table.insert(result, node)
        end
    end

    table.sort(result, function(first, second)
        return first.node_id < second.node_id
    end)

    return result
end

function Conquest:nearest_controlled_node(guild_key, location)
    local nearest = nil
    local nearest_distance = math.huge

    for _, node in ipairs(self:nodes_for_controller(guild_key)) do
        local expansion_ready = node.state == States.NODE.PROTECTED
            or node.state == States.NODE.RESTORED
            or node.state == States.NODE.CONQUERED
        local current_distance = Rules.distance(node, location or {})

        if expansion_ready and flag_bound(node)
            and current_distance < nearest_distance then
            nearest = node
            nearest_distance = current_distance
        end
    end

    return nearest, nearest_distance
end

function Conquest:active_campaign(attacker_guild, defender_guild)
    local selected = nil

    for _, campaign in pairs(self.campaigns) do
        local open = campaign.state ~= States.CAMPAIGN.PEACE_RESOLVED
            and campaign.state ~= States.CAMPAIGN.CAPITAL_DEFEATED

        if open
            and campaign.attacker_guild == text(attacker_guild)
            and campaign.defender_guild == text(defender_guild)
            and (not selected or campaign.created_at > selected.created_at) then
            selected = campaign
        end
    end

    return selected
end

function Conquest:status_for_guild(guild_key, now)
    guild_key = text(guild_key)
    now = self:_now(now)
    local status = {
        capital_count = 0,
        outpost_count = 0,
        missing_flag_count = 0,
        campaigns = {},
        occupations = {}
    }

    for _, node in ipairs(self:nodes_for_controller(guild_key)) do
        if not flag_bound(node) then
            status.missing_flag_count = status.missing_flag_count + 1
        end
        if node.node_type == States.NODE_TYPE.CAPITAL then
            status.capital_count = status.capital_count + 1
        elseif node.node_type == States.NODE_TYPE.OUTPOST then
            status.outpost_count = status.outpost_count + 1
        end
    end

    for _, campaign in pairs(self.campaigns) do
        local direction = nil
        local opponent = nil
        if campaign.attacker_guild == guild_key then
            direction = "ATTACK"
            opponent = campaign.defender_guild
        elseif campaign.defender_guild == guild_key then
            direction = "DEFENSE"
            opponent = campaign.attacker_guild
        end

        if direction ~= nil
            and campaign.state ~= States.CAMPAIGN.PEACE_RESOLVED
            and campaign.state ~= States.CAMPAIGN.CAPITAL_DEFEATED then
            table.insert(status.campaigns, {
                campaign_id = campaign.campaign_id,
                direction = direction,
                opponent_guild = opponent,
                state = campaign.state,
                active_target_node_id = campaign.active_target_node_id,
                created_at = campaign.created_at
            })
        end
    end

    table.sort(status.campaigns, function(first, second)
        if first.created_at ~= second.created_at then
            return first.created_at > second.created_at
        end
        return first.campaign_id < second.campaign_id
    end)

    for _, occupation in pairs(self.occupations) do
        local ongoing = occupation.state == States.OCCUPATION.OCCUPIED
            or occupation.state == States.OCCUPATION.COUNTER_ATTACK
            or occupation.state == States.OCCUPATION.PAUSED
        if ongoing and (occupation.original_owner == guild_key
            or occupation.occupying_guild == guild_key) then
            local remaining = occupation.remaining_seconds
            if (occupation.state == States.OCCUPATION.OCCUPIED
                or occupation.state == States.OCCUPATION.COUNTER_ATTACK)
                and occupation.last_resumed_at > 0 then
                remaining = math.max(
                    0,
                    remaining - math.max(0, now - occupation.last_resumed_at)
                )
            end
            local counter_remaining = occupation.counter_remaining_seconds
            if occupation.state == States.OCCUPATION.COUNTER_ATTACK
                and occupation.counter_last_resumed_at > 0 then
                counter_remaining = math.max(
                    0,
                    counter_remaining - math.max(
                        0,
                        now - occupation.counter_last_resumed_at
                    )
                )
            end

            table.insert(status.occupations, {
                node_id = occupation.node_id,
                state = occupation.state,
                remaining_seconds = remaining,
                counter_remaining_seconds = counter_remaining,
                original_owner = occupation.original_owner,
                occupying_guild = occupation.occupying_guild,
                updated_at = occupation.updated_at
            })
        end
    end

    table.sort(status.occupations, function(first, second)
        if first.updated_at ~= second.updated_at then
            return first.updated_at > second.updated_at
        end
        return first.node_id < second.node_id
    end)

    return status
end

function Conquest:nearest_initial_target(defender_guild, camp)
    local selected = nil
    local selected_distance = math.huge

    for _, node in pairs(self.nodes) do
        if node.node_type == States.NODE_TYPE.OUTPOST
            and node.current_controller == text(defender_guild)
            and flag_bound(node)
            and (node.state == States.NODE.PROTECTED
                or node.state == States.NODE.RESTORED) then

            local valid = Rules.validate_siege_location(
                node,
                self.nodes,
                camp,
                defender_guild,
                self.config
            )
            local current_distance = Rules.distance(node, camp)

            if valid.allow and current_distance < selected_distance then
                selected = node
                selected_distance = current_distance
            end
        end
    end

    return selected, selected_distance
end

function Conquest:_constructed_outpost_count(guild_key)
    local count = 0

    for _, node in pairs(self.nodes) do
        if node.node_type == States.NODE_TYPE.OUTPOST
            and node.original_owner == guild_key
            and node.current_controller == guild_key then
            count = count + 1
        end
    end

    return count
end

function Conquest:_flag_reference_exists(reference)
    if reference == "" then return false end

    for _, node in pairs(self.nodes) do
        if node.flag_reference == reference
            or node.legacy_flag_reference == reference then
            return true
        end
    end

    for _, occupation in pairs(self.occupations) do
        if text(occupation.counter_flag_reference) == reference then
            return true
        end
    end

    return false
end

function Conquest:register_node(request)
    request = request or {}
    local authorized = self:_authorized(request.actor_role)
    if not authorized.ok then return authorized end

    local node_id = text(request.node_id)
    local guild_key = text(request.guild_key)
    local node_type = text(request.node_type)
    local now = self:_now(request.now)

    if node_id == "" or guild_key == "" then
        return Result.err("NODE_IDENTITY_MISSING", "Node veya klan kimligi yok")
    end

    if self.nodes[node_id] then
        return Result.err("NODE_ALREADY_EXISTS", "Node kimligi zaten kayitli")
    end

    local flag_reference = text(request.flag_reference)
    if self:_flag_reference_exists(flag_reference) then
        return Result.err("FLAG_ALREADY_REGISTERED", "Bayrak referansi zaten kayitli")
    end

    if node_type ~= States.NODE_TYPE.CAPITAL
        and node_type ~= States.NODE_TYPE.OUTPOST then
        return Result.err("INVALID_NODE_TYPE", "Node tipi gecersiz")
    end

    local node = {
        key = node_id,
        node_id = node_id,
        guild_key = guild_key,
        node_type = node_type,
        flag_reference = flag_reference,
        flag_state = States.FLAG.BOUND,
        legacy_flag_reference = "",
        x = number(request.x),
        y = number(request.y),
        z = number(request.z),
        parent_node_id = "",
        state = States.NODE.PROTECTED,
        original_owner = guild_key,
        current_controller = guild_key,
        display_name = text(request.display_name),
        territory_radius_meters = number(
            request.territory_radius_meters
        ),
        created_at = now,
        updated_at = now
    }

    local registered_edge_id = ""
    if node_type == States.NODE_TYPE.CAPITAL then
        if self:_capital_for(guild_key) then
            return Result.err("CAPITAL_ALREADY_EXISTS", "Klanin baskenti zaten var")
        end
    else
        local maximum = math.max(
            0,
            math.floor(number(self.config.max_outposts_per_clan))
        )

        if maximum <= 0
            or self:_constructed_outpost_count(guild_key) >= maximum then
            return Result.err("OUTPOST_LIMIT_REACHED", "Yeni karakol siniri dolu")
        end

        local parent = self.nodes[text(request.parent_node_id)]
        if not parent or parent.current_controller ~= guild_key then
            return Result.err("INVALID_PARENT_NODE", "Ana node klan kontrolunde degil")
        end

        local link = Rules.validate_link(parent, node, self.config)
        if not link.allow then
            return Result.err(link.reason, "Karakol baglanti mesafesi gecersiz")
        end

        node.parent_node_id = parent.node_id
        registered_edge_id = edge_id(parent.node_id, node.node_id)
        self.edges[registered_edge_id] = {
            key = registered_edge_id,
            edge_id = registered_edge_id,
            node_a = parent.node_id,
            node_b = node.node_id,
            created_at = now
        }
    end

    self.nodes[node_id] = node
    local nodes_saved = self.repository:save_nodes(self.nodes)
    if not nodes_saved.ok then
        self.nodes[node_id] = nil
        if registered_edge_id ~= "" then
            self.edges[registered_edge_id] = nil
        end
        return nodes_saved
    end

    if registered_edge_id ~= "" then
        local edges_saved = self.repository:save_edges(self.edges)
        if not edges_saved.ok then
            self.nodes[node_id] = nil
            self.edges[registered_edge_id] = nil

            local rollback = self.repository:save_nodes(self.nodes)
            if not rollback.ok and self.logger then
                self.logger:error(
                    "FAZ05_NODE_ROLLBACK_WRITE_FAILED | " ..
                    Result.describe(rollback)
                )
            end
            return edges_saved
        end
    end

    self:_event("FAZ05_FLAG_REGISTERED", node_id .. "|" .. node_type)
    return Result.ok(node)
end

function Conquest:rename_territory(request)
    request = request or {}
    local authorized = self:_authorized(request.actor_role)
    if not authorized.ok then return authorized end

    local node = self.nodes[text(request.node_id)]
    local guild_key = text(request.guild_key)
    if not node or node.current_controller ~= guild_key then
        return Result.err(
            "TERRITORY_NOT_CONTROLLED",
            "Bolge bu klanin kontrolunde degil"
        )
    end

    local name = Text.clean(request.display_name)
    local maximum = math.max(
        1,
        math.floor(number(self.config.territory_name_max_length))
    )
    if name == "" then
        return Result.err("TERRITORY_NAME_EMPTY", "Bolge adi bos olamaz")
    end
    if #name > maximum then
        return Result.err(
            "TERRITORY_NAME_TOO_LONG",
            "Bolge adi en fazla " .. tostring(maximum) .. " karakter olabilir"
        )
    end

    local previous_name = node.display_name
    local previous_updated_at = node.updated_at
    node.display_name = name
    node.updated_at = self:_now(request.now)
    local saved = self.repository:save_nodes(self.nodes)
    if not saved.ok then
        node.display_name = previous_name
        node.updated_at = previous_updated_at
        return saved
    end
    self:_event("FAZ05_TERRITORY_RENAMED", node.node_id .. "|" .. name)
    return Result.ok(node)
end

function Conquest:set_territory_radius(request)
    request = request or {}
    local authorized = self:_authorized(request.actor_role)
    if not authorized.ok then return authorized end

    local node = self.nodes[text(request.node_id)]
    local guild_key = text(request.guild_key)
    if not node or node.current_controller ~= guild_key then
        return Result.err(
            "TERRITORY_NOT_CONTROLLED",
            "Bolge bu klanin kontrolunde degil"
        )
    end

    local radius = number(request.radius_meters)
    local minimum = number(self.config.territory_min_radius_meters)
    local maximum = number(self.config.territory_max_radius_meters)
    if minimum <= 0 or maximum < minimum
        or radius < minimum or radius > maximum then
        return Result.err(
            "TERRITORY_RADIUS_OUT_OF_RANGE",
            string.format(
                "Bolge siniri %.0f-%.0f metre arasinda olmali",
                minimum,
                maximum
            )
        )
    end

    local previous_radius = node.territory_radius_meters
    local previous_updated_at = node.updated_at
    node.territory_radius_meters = radius
    node.updated_at = self:_now(request.now)
    local saved = self.repository:save_nodes(self.nodes)
    if not saved.ok then
        node.territory_radius_meters = previous_radius
        node.updated_at = previous_updated_at
        return saved
    end
    self:_event(
        "FAZ05_TERRITORY_RADIUS_CHANGED",
        node.node_id .. "|" .. tostring(radius)
    )
    return Result.ok(node)
end

function Conquest:rebind_missing_flag(request)
    request = request or {}
    local authorized = self:_authorized(request.actor_role)
    if not authorized.ok then return authorized end

    local guild_key = text(request.guild_key)
    local flag = request.flag or {}
    local reference = text(flag.flag_reference)
    local now = self:_now(request.now)

    if guild_key == "" or reference == "" then
        return Result.err("FLAG_REBIND_IDENTITY_MISSING", "Klan veya bayrak kimligi yok")
    end
    if text(flag.guild_key) ~= guild_key then
        return Result.err("FLAG_REBIND_OWNER_MISMATCH", "Yeni bayrak fetheden klana ait degil")
    end
    if self:_flag_reference_exists(reference) then
        return Result.err("FLAG_ALREADY_REGISTERED", "Bu Klan Bayragi zaten kayitli")
    end

    local nearest = nil
    local nearest_distance = math.huge
    for _, node in pairs(self.nodes) do
        local eligible = node.current_controller == guild_key
            and node.flag_state == States.FLAG.MISSING
            and (node.state == States.NODE.PROTECTED
                or node.state == States.NODE.CONQUERED
                or node.state == States.NODE.RESTORED)
        if eligible then
            local current = Rules.distance(node, flag)
            if current < nearest_distance then
                nearest = node
                nearest_distance = current
            end
        end
    end

    local maximum = number(self.config.flag_rebind_radius_meters)
    if maximum <= 0 or not nearest or nearest_distance > maximum then
        return Result.err(
            "CONQUERED_NODE_NOT_NEAR",
            "Yakinda yeniden bayrak bekleyen kontrollu stratejik node yok"
        )
    end

    local previous = {
        flag_reference = nearest.flag_reference,
        flag_state = nearest.flag_state,
        x = nearest.x,
        y = nearest.y,
        z = nearest.z,
        updated_at = nearest.updated_at
    }

    nearest.flag_reference = reference
    nearest.flag_state = States.FLAG.BOUND
    nearest.x = number(flag.x)
    nearest.y = number(flag.y)
    nearest.z = number(flag.z)
    nearest.updated_at = now

    local saved = self.repository:save_nodes(self.nodes)
    if not saved.ok then
        nearest.flag_reference = previous.flag_reference
        nearest.flag_state = previous.flag_state
        nearest.x = previous.x
        nearest.y = previous.y
        nearest.z = previous.z
        nearest.updated_at = previous.updated_at
        return saved
    end

    self:_event("FAZ05_FLAG_REBOUND", nearest.node_id .. "|" .. reference)
    return Result.ok(nearest)
end

function Conquest:start_campaign(attacker, defender, actor_role, now)
    local authorized = self:_authorized(actor_role)
    if not authorized.ok then return authorized end

    local relation, error_message, pair_key = self:_relation(attacker, defender)
    if not relation then return Result.err("RELATION", error_message) end
    if not Rules.is_effective_war(relation) then
        return Result.err("NO_ACTIVE_WAR", "Fetih kampanyasi icin aktif savas gerekli")
    end

    if not self:_capital_for(defender) then
        return Result.err("DEFENDER_CAPITAL_MISSING", "Savunmacinin baskenti yok")
    end

    now = self:_now(now)
    local war_id = pair_key .. "@" .. tostring(number(relation.active_at))
    local campaign_id = war_id .. "::" .. text(attacker)

    local existing = self.campaigns[campaign_id]
    if existing
        and existing.state ~= States.CAMPAIGN.PEACE_RESOLVED
        and existing.state ~= States.CAMPAIGN.CAPITAL_DEFEATED then
        return Result.err("CAMPAIGN_ALREADY_ACTIVE", "Aktif kampanya zaten var")
    end

    local campaign = {
        key = campaign_id,
        campaign_id = campaign_id,
        war_id = war_id,
        attacker_guild = text(attacker),
        defender_guild = text(defender),
        state = States.CAMPAIGN.ACTIVE,
        active_target_node_id = "",
        siege_camp_reference = "",
        siege_x = 0,
        siege_y = 0,
        siege_z = 0,
        rearm_until = 0,
        previous_relation_state = relation.state,
        created_at = now,
        updated_at = now
    }

    local previous_campaign = self.campaigns[campaign_id]
    self.campaigns[campaign_id] = campaign
    local saved = self:_save_campaigns()
    if not saved.ok then
        self.campaigns[campaign_id] = previous_campaign
        return saved
    end
    return Result.ok(campaign)
end

function Conquest:_captured_frontline(campaign)
    local result = {}

    for _, node in pairs(self.nodes) do
        if node.original_owner == campaign.defender_guild
            and node.current_controller == campaign.attacker_guild
            and flag_bound(node)
            and node.state == States.NODE.CONQUERED then
            result[node.node_id] = true
        end
    end

    return result
end

function Conquest:_reachable(campaign, target)
    if not target
        or target.current_controller ~= campaign.defender_guild then
        return false
    end

    local frontline = self:_captured_frontline(campaign)

    for _, edge in pairs(self.edges) do
        if edge.node_a == target.node_id and frontline[edge.node_b] then
            return true
        end

        if edge.node_b == target.node_id and frontline[edge.node_a] then
            return true
        end
    end

    if next(frontline) ~= nil
        or target.node_type == States.NODE_TYPE.CAPITAL
        or campaign.siege_camp_reference == "" then
        return false
    end

    local distance = Rules.distance(target, {
        x = campaign.siege_x,
        y = campaign.siege_y,
        z = campaign.siege_z
    })

    return distance >= number(
        self.config.siege_min_distance_from_target_meters
    ) and distance <= number(
        self.config.siege_max_distance_from_target_meters
    )
end

function Conquest:_set_target(campaign, target, now)
    if campaign.active_target_node_id ~= "" then
        return Result.err("TARGET_ALREADY_SELECTED", "Aktif hedef degistirilemez")
    end

    if target.state ~= States.NODE.PROTECTED
        and target.state ~= States.NODE.RESTORED then
        return Result.err("TARGET_STATE_BLOCKED", "Node hedeflenebilir durumda degil")
    end

    if not flag_bound(target) then
        return Result.err("TARGET_FLAG_MISSING", "Hedefin fiziksel Klan Bayragi eksik")
    end

    if not self:_reachable(campaign, target) then
        return Result.err("TARGET_NOT_FRONTLINE_REACHABLE", "Fetih hatti hedefe ulasmiyor")
    end

    local previous_target_state = target.state
    local previous_target_updated_at = target.updated_at
    local previous_target_node_id = campaign.active_target_node_id
    local previous_campaign_updated_at = campaign.updated_at

    target.state = target.node_type == States.NODE_TYPE.CAPITAL
        and States.NODE.CAPITAL_TARGETABLE
        or States.NODE.TARGETABLE
    target.updated_at = now
    campaign.active_target_node_id = target.node_id
    campaign.updated_at = now

    local nodes = self.repository:save_nodes(self.nodes)
    if not nodes.ok then
        target.state = previous_target_state
        target.updated_at = previous_target_updated_at
        campaign.active_target_node_id = previous_target_node_id
        campaign.updated_at = previous_campaign_updated_at
        return nodes
    end
    local campaigns = self:_save_campaigns()
    if not campaigns.ok then
        target.state = previous_target_state
        target.updated_at = previous_target_updated_at
        campaign.active_target_node_id = previous_target_node_id
        campaign.updated_at = previous_campaign_updated_at

        local rollback = self.repository:save_nodes(self.nodes)
        if not rollback.ok and self.logger then
            self.logger:error(
                "FAZ05_TARGET_ROLLBACK_WRITE_FAILED | " ..
                Result.describe(rollback)
            )
        end
        return campaigns
    end

    self:_event("FAZ05_TARGET_SELECTED", campaign.campaign_id .. "|" .. target.node_id)
    return Result.ok(target)
end

function Conquest:establish_siege(
    campaign_id,
    actor_role,
    target_node_id,
    camp,
    now
)
    local authorized = self:_authorized(actor_role)
    if not authorized.ok then return authorized end

    local campaign = self.campaigns[text(campaign_id)]
    local target = self.nodes[text(target_node_id)]
    now = self:_now(now)

    if not campaign or campaign.state ~= States.CAMPAIGN.ACTIVE then
        return Result.err("CAMPAIGN_NOT_ACTIVE", "Aktif kampanya yok")
    end

    if campaign.siege_camp_reference ~= "" then
        return Result.err("SIEGE_CAMP_ALREADY_EXISTS", "Savas icin kamp zaten var")
    end

    if not target
        or target.node_type ~= States.NODE_TYPE.OUTPOST
        or target.current_controller ~= campaign.defender_guild then
        return Result.err("INVALID_INITIAL_TARGET", "Ilk hedef dusman karakolu olmali")
    end

    camp = camp or {}
    local location = Rules.validate_siege_location(
        target,
        self.nodes,
        camp,
        campaign.defender_guild,
        self.config
    )
    if not location.allow then
        return Result.err(location.reason, "Kusatma kampi konumu gecersiz")
    end

    local previous_siege = {
        reference = campaign.siege_camp_reference,
        x = campaign.siege_x,
        y = campaign.siege_y,
        z = campaign.siege_z,
        updated_at = campaign.updated_at
    }

    campaign.siege_camp_reference = text(camp.reference)
    if campaign.siege_camp_reference == "" then
        return Result.err("SIEGE_REFERENCE_MISSING", "Kusatma kampi referansi yok")
    end

    campaign.siege_x = number(camp.x)
    campaign.siege_y = number(camp.y)
    campaign.siege_z = number(camp.z)
    campaign.updated_at = now

    local selected = self:_set_target(campaign, target, now)
    if not selected.ok then
        campaign.siege_camp_reference = previous_siege.reference
        campaign.siege_x = previous_siege.x
        campaign.siege_y = previous_siege.y
        campaign.siege_z = previous_siege.z
        campaign.updated_at = previous_siege.updated_at
    end

    return selected
end

function Conquest:select_target(campaign_id, actor_role, target_node_id, now)
    local authorized = self:_authorized(actor_role)
    if not authorized.ok then return authorized end

    local campaign = self.campaigns[text(campaign_id)]
    local target = self.nodes[text(target_node_id)]

    if not campaign or campaign.state ~= States.CAMPAIGN.ACTIVE then
        return Result.err("CAMPAIGN_NOT_ACTIVE", "Aktif kampanya yok")
    end

    if not target or target.current_controller ~= campaign.defender_guild then
        return Result.err("INVALID_TARGET", "Hedef savunmaci kontrolunde degil")
    end

    return self:_set_target(campaign, target, self:_now(now))
end

function Conquest:select_next_target(campaign_id, actor_role, now)
    local authorized = self:_authorized(actor_role)
    if not authorized.ok then return authorized end

    local campaign = self.campaigns[text(campaign_id)]
    if not campaign or campaign.state ~= States.CAMPAIGN.ACTIVE then
        return Result.err("CAMPAIGN_NOT_ACTIVE", "Aktif kampanya yok")
    end
    if campaign.active_target_node_id ~= "" then
        return Result.err("TARGET_ALREADY_SELECTED", "Aktif hedef degistirilemez")
    end

    local frontline = self:_captured_frontline(campaign)
    local origin = {
        x = campaign.siege_x,
        y = campaign.siege_y,
        z = campaign.siege_z
    }
    local selected = nil
    local selected_distance = math.huge

    for _, candidate in pairs(self.nodes) do
        local available = candidate.current_controller == campaign.defender_guild
            and (candidate.state == States.NODE.PROTECTED
                or candidate.state == States.NODE.RESTORED)
            and self:_reachable(campaign, candidate)

        if available then
            local candidate_distance = Rules.distance(candidate, origin)

            if next(frontline) ~= nil then
                candidate_distance = math.huge
                for _, edge in pairs(self.edges) do
                    local source_id = nil
                    if edge.node_a == candidate.node_id
                        and frontline[edge.node_b] then
                        source_id = edge.node_b
                    elseif edge.node_b == candidate.node_id
                        and frontline[edge.node_a] then
                        source_id = edge.node_a
                    end

                    local source = source_id and self.nodes[source_id] or nil
                    if source ~= nil then
                        candidate_distance = math.min(
                            candidate_distance,
                            Rules.distance(candidate, source)
                        )
                    end
                end
            end

            if candidate_distance < selected_distance
                or (candidate_distance == selected_distance
                    and (not selected or candidate.node_id < selected.node_id)) then
                selected = candidate
                selected_distance = candidate_distance
            end
        end
    end

    if not selected then
        return Result.err(
            "NO_REACHABLE_CONQUEST_TARGET",
            "Fetih hattindan erisilebilen yeni hedef yok"
        )
    end

    return self:_set_target(campaign, selected, self:_now(now))
end

function Conquest:can_damage_flag(campaign_id, target_node_id, attacker, now)
    local campaign = self.campaigns[text(campaign_id)]
    local target = self.nodes[text(target_node_id)]
    now = self:_now(now)

    if not campaign then
        return Rules.can_damage_flag({ now = now })
    end

    local relation = self:_relation(
        campaign.attacker_guild,
        campaign.defender_guild
    )
    local raid_open = RaidWindow.is_open(now, self.config)

    return Rules.can_damage_flag({
        relation = relation,
        campaign = campaign,
        target = target,
        attacker_guild = text(attacker),
        raid_open = raid_open,
        reachable = self:_reachable(campaign, target),
        now = now
    })
end

function Conquest:write_damage_policy(now)
    now = self:_now(now)
    local lines = {
        "flag_reference\tnode_id\towner_guild\tallowed_attacker_guild"
    }
    local zone_lines = {
        "node_id\towner_guild\tallowed_attacker_guild\tcenter_x_world\tcenter_y_world\tcenter_z_world\tradius_world"
    }
    local units_per_meter = tonumber(self.config.world_units_per_meter) or 100
    local zone_radius = tonumber(
        self.config.conquest_zone_radius_meters
    ) or 0

    local nodes = {}
    for _, node in pairs(self.nodes) do table.insert(nodes, node) end
    table.sort(nodes, function(first, second)
        return first.node_id < second.node_id
    end)

    for _, node in ipairs(nodes) do
        if node.flag_reference ~= "" and flag_bound(node) then
            local allowed = {}

            for _, campaign in pairs(self.campaigns) do
                if campaign.active_target_node_id == node.node_id then
                    local decision = self:can_damage_flag(
                        campaign.campaign_id,
                        node.node_id,
                        campaign.attacker_guild,
                        now
                    )

                    if decision.allow then
                        allowed[campaign.attacker_guild] = true
                    end
                end
            end

            local attackers = {}
            for attacker in pairs(allowed) do table.insert(attackers, attacker) end
            table.sort(attackers)

            if #attackers == 0 then attackers = { "" } end

            for _, attacker in ipairs(attackers) do
                table.insert(lines, TSV.encode({
                    node.flag_reference,
                    node.node_id,
                    node.current_controller,
                    attacker
                }))
                if attacker ~= "" and zone_radius > 0 then
                    table.insert(zone_lines, TSV.encode({
                        node.node_id,
                        node.current_controller,
                        attacker,
                        node.x * units_per_meter,
                        node.y * units_per_meter,
                        node.z * units_per_meter,
                        zone_radius * units_per_meter
                    }))
                end
            end
        end

        local cleanup_reference = text(node.legacy_flag_reference)
        if cleanup_reference ~= ""
            and node.current_controller ~= node.original_owner then
            table.insert(lines, TSV.encode({
                cleanup_reference,
                node.node_id,
                node.original_owner,
                node.current_controller
            }))
        end
    end

    local occupations = {}
    for _, occupation in pairs(self.occupations) do
        if occupation.state == States.OCCUPATION.COUNTER_ATTACK
            and text(occupation.counter_flag_reference) ~= "" then
            table.insert(occupations, occupation)
        end
    end
    table.sort(occupations, function(first, second)
        return first.node_id < second.node_id
    end)
    for _, occupation in ipairs(occupations) do
        table.insert(lines, TSV.encode({
            occupation.counter_flag_reference,
            occupation.node_id,
            occupation.original_owner,
            occupation.occupying_guild
        }))
    end

    local zone_signature = table.concat(zone_lines, "\n")
    if zone_signature ~= self.zone_policy_signature
        or not FileIO.exists(self.paths.conquest_zone_policy) then
        local zone_result = FileIO.overwrite(
            self.paths.conquest_zone_policy,
            zone_lines
        )
        if not zone_result.ok then return zone_result end
        self.zone_policy_signature = zone_signature
    end

    local damage_signature = table.concat(lines, "\n")
    if damage_signature ~= self.damage_policy_signature
        or not FileIO.exists(self.paths.conquest_damage_policy) then
        local damage_result = FileIO.overwrite(
            self.paths.conquest_damage_policy,
            lines
        )
        if not damage_result.ok then return damage_result end
        self.damage_policy_signature = damage_signature
    end

    return Result.ok(true)
end

function Conquest:_cancel_counter_attack(occupation, now)
    occupation.state = States.OCCUPATION.OCCUPIED
    occupation.frontline_state = "HELD"
    occupation.counter_flag_reference = ""
    occupation.counter_remaining_seconds = 0
    occupation.counter_last_resumed_at = 0
    occupation.counter_flag_x = 0
    occupation.counter_flag_y = 0
    occupation.counter_flag_z = 0
    occupation.updated_at = now
    self:_event("FAZ05_COUNTER_ATTACK_FAILED", occupation.node_id)
end

function Conquest:process_runtime_events(now)
    local path = self.paths.conquest_runtime_events
    local processing_path = path .. ".processing"

    if not FileIO.exists(processing_path) then
        if not FileIO.exists(path) then
            local initialized = FileIO.append(
                path,
                "timestamp\tmarker\tflag_reference"
            )
            if not initialized.ok then return initialized end
            return Result.ok(0)
        end

        local moved = FileIO.move(path, processing_path)
        if not moved.ok then return moved end

        local reopened = FileIO.append(
            path,
            "timestamp\tmarker\tflag_reference"
        )
        if not reopened.ok then return reopened end
    elseif not FileIO.exists(path) then
        local reopened = FileIO.append(
            path,
            "timestamp\tmarker\tflag_reference"
        )
        if not reopened.ok then return reopened end
    end

    local loaded = FileIO.read_lines(processing_path)
    if not loaded.ok then return loaded end
    local runtime_lines = loaded.value or {}
    if #runtime_lines == 0
        or runtime_lines[1] ~= "timestamp\tmarker\tflag_reference" then

        return Result.err(
            "INVALID_RUNTIME_EVENT_HEADER",
            "Fetih runtime event basligi gecersiz"
        )
    end

    local processed = 0
    local cleared_legacy_reference = false
    local changed_occupations = false
    local changed_nodes = false

    for index, line in ipairs(runtime_lines) do
        if index > 1 and line ~= "" then
            local columns = TSV.decode(line)
            local event_at = number(columns[1])
            local marker = text(columns[2])
            local reference = text(columns[3])

            if marker == "FLAG_DISPOSED" and reference ~= "" then
                for _, occupation in pairs(self.occupations) do
                    if occupation.state == States.OCCUPATION.COUNTER_ATTACK
                        and text(occupation.counter_flag_reference) == reference then
                        self:_cancel_counter_attack(
                            occupation,
                            event_at > 0 and event_at or now
                        )
                        changed_occupations = true
                        processed = processed + 1
                        break
                    end
                end

                local node = self:node_for_flag_reference(reference)

                if node then
                    for _, campaign in pairs(self.campaigns) do
                        if campaign.active_target_node_id == node.node_id then
                            local event_time = event_at > 0 and event_at or now
                            local attacker = campaign.attacker_guild
                            local decision = self:can_damage_flag(
                                campaign.campaign_id,
                                node.node_id,
                                attacker,
                                event_time
                            )

                            if decision.allow then
                                local fallen = self:flag_fallen(
                                    campaign.campaign_id,
                                    node.node_id,
                                    attacker,
                                    event_time
                                )
                                if not fallen.ok then return fallen end
                                processed = processed + 1
                                break
                            end
                        end
                    end

                    if flag_bound(node) then
                        node.flag_state = States.FLAG.MISSING
                        node.updated_at = event_at > 0 and event_at or now
                        changed_nodes = true
                        self:_event("FAZ05_FLAG_MISSING", node.node_id)
                    end
                end

                for _, current in pairs(self.nodes) do
                    if text(current.legacy_flag_reference) == reference then
                        current.legacy_flag_reference = ""
                        current.updated_at = event_at > 0 and event_at or now
                        cleared_legacy_reference = true
                    end
                end
            end
        end
    end

    if cleared_legacy_reference or changed_nodes then
        local saved = self.repository:save_nodes(self.nodes)
        if not saved.ok then return saved end
    end
    if changed_occupations then
        local saved = self:_save_occupations()
        if not saved.ok then return saved end
    end

    local removed = FileIO.remove(processing_path)
    if not removed.ok then return removed end

    return Result.ok(processed)
end

function Conquest:can_damage_conquest_zone(
    campaign_id,
    attacker,
    location,
    now
)
    local campaign = self.campaigns[text(campaign_id)]
    if not campaign then
        return {
            allow = false,
            block = true,
            reason = "NO_ACTIVE_CAMPAIGN",
            offline_exception = false
        }
    end

    local target = self.nodes[campaign.active_target_node_id]
    local flag_policy = self:can_damage_flag(
        campaign_id,
        campaign.active_target_node_id,
        attacker,
        now
    )
    if not flag_policy.allow then return flag_policy end

    return Rules.validate_conquest_zone(target, location, self.config)
end

function Conquest:record_target_damage(campaign_id, target_node_id, attacker, now)
    local result = self:can_damage_flag(
        campaign_id,
        target_node_id,
        attacker,
        now
    )
    if not result.allow then return Result.err(result.reason, "Bayrak hasari engellendi") end

    local target = self.nodes[target_node_id]
    local next_state = target.node_type == States.NODE_TYPE.CAPITAL
        and States.NODE.CAPITAL_UNDER_ATTACK
        or States.NODE.UNDER_ATTACK

    if target.state ~= next_state then
        local previous = copy_record(target)
        target.state = next_state
        target.updated_at = self:_now(now)
        local saved = self.repository:save_nodes(self.nodes)
        if not saved.ok then
            restore_record(target, previous)
            return saved
        end
        self:_event("FAZ05_TARGET_DAMAGE_ALLOW", target.node_id)
    end

    return Result.ok(result)
end

function Conquest:_create_occupation(campaign, node, now)
    local loot = Loot.create(
        node,
        campaign,
        self.config,
        now,
        self.random
    )
    if not loot.ok then return loot end

    local manifest = loot.value.manifest
    self.loot_manifests[manifest.manifest_id] = manifest
    for key, item in pairs(loot.value.items) do self.loot_items[key] = item end

    local occupation = {
        key = node.node_id,
        node_id = node.node_id,
        original_owner = node.original_owner,
        occupying_guild = campaign.attacker_guild,
        war_id = campaign.war_id,
        state = States.OCCUPATION.OCCUPIED,
        previous_state = "",
        occupation_started_at = now,
        remaining_seconds = number(self.config.occupation_hold_seconds),
        last_resumed_at = now,
        loot_manifest_id = manifest.manifest_id,
        frontline_state = "HELD",
        updated_at = now,
        counter_flag_reference = "",
        counter_remaining_seconds = 0,
        counter_last_resumed_at = 0,
        counter_flag_x = 0,
        counter_flag_y = 0,
        counter_flag_z = 0
    }

    self.occupations[node.node_id] = occupation
    node.state = States.NODE.OCCUPIED
    node.legacy_flag_reference = node.flag_reference
    node.flag_state = States.FLAG.MISSING
    set_controller(node, campaign.attacker_guild)
    node.updated_at = now
    campaign.active_target_node_id = ""
    campaign.updated_at = now

    local nodes = self.repository:save_nodes(self.nodes)
    if not nodes.ok then return nodes end
    local occupations = self:_save_occupations()
    if not occupations.ok then return occupations end
    local loot_saved = self:_save_loot()
    if not loot_saved.ok then return loot_saved end
    local campaigns = self:_save_campaigns()
    if not campaigns.ok then return campaigns end

    self:_event("FAZ05_OUTPOST_FALLEN", node.node_id)
    self:_event("FAZ05_OCCUPATION_STARTED", node.node_id)
    self:_event("FAZ05_LOOT_CREATED", manifest.manifest_id)
    return Result.ok(occupation)
end

function Conquest:_capital_defeated(campaign, capital, now)
    if self.config.capital_defeat_resolution ~= "TRANSFER_ALL_NODES" then
        return Result.err(
            "UNSUPPORTED_CAPITAL_DEFEAT_RESOLUTION",
            "Baskent yenilgisi kurali desteklenmiyor"
        )
    end

    for _, node in pairs(self.nodes) do
        if node.current_controller == campaign.defender_guild then
            node.legacy_flag_reference = node.flag_reference
            set_controller(node, campaign.attacker_guild)
            node.state = States.NODE.CONQUERED
            node.flag_state = States.FLAG.MISSING
            node.updated_at = now

            if node.node_type == States.NODE_TYPE.CAPITAL then
                node.node_type = States.NODE_TYPE.OUTPOST
            end
        end
    end

    for _, occupation in pairs(self.occupations) do
        if occupation.war_id == campaign.war_id
            and occupation.state ~= States.OCCUPATION.RESTORED then
            occupation.state = States.OCCUPATION.CONQUERED
            occupation.previous_state = ""
            occupation.remaining_seconds = 0
            occupation.last_resumed_at = 0
            occupation.frontline_state = "FINALIZED"
            occupation.updated_at = now
            occupation.counter_flag_reference = ""
            occupation.counter_remaining_seconds = 0
            occupation.counter_last_resumed_at = 0
            occupation.counter_flag_x = 0
            occupation.counter_flag_y = 0
            occupation.counter_flag_z = 0
        end
    end

    for _, current in pairs(self.campaigns) do
        if current.war_id == campaign.war_id then
            current.state = States.CAMPAIGN.CAPITAL_DEFEATED
            current.active_target_node_id = ""
            current.siege_camp_reference = ""
            current.rearm_until = 0
            current.updated_at = now
        end
    end

    local nodes = self.repository:save_nodes(self.nodes)
    if not nodes.ok then return nodes end
    local occupations = self:_save_occupations()
    if not occupations.ok then return occupations end
    local campaigns = self:_save_campaigns()
    if not campaigns.ok then return campaigns end

    if self.diplomacy and self.diplomacy.resolve_capital_defeat then
        local resolved = self.diplomacy:resolve_capital_defeat(
            campaign.attacker_guild,
            campaign.defender_guild,
            "PalTR Conquest"
        )
        if not resolved.ok then return resolved end
    end

    self:_event("FAZ05_CAPITAL_UNLOCKED", capital.node_id)
    self:_event("FAZ05_CONQUEST_FINALIZED", "CAPITAL|" .. capital.node_id)
    return Result.ok(capital)
end

function Conquest:flag_fallen(campaign_id, target_node_id, attacker, now)
    local policy = self:can_damage_flag(
        campaign_id,
        target_node_id,
        attacker,
        now
    )
    if not policy.allow then return Result.err(policy.reason, "Bayrak dusurulemez") end

    local campaign = self.campaigns[campaign_id]
    local target = self.nodes[target_node_id]
    now = self:_now(now)

    if target.node_type == States.NODE_TYPE.CAPITAL then
        return self:_capital_defeated(campaign, target, now)
    end

    return self:_create_occupation(campaign, target, now)
end

function Conquest:_pause_occupations(war_id, now)
    for _, occupation in pairs(self.occupations) do
        if occupation.war_id == war_id
            and (occupation.state == States.OCCUPATION.OCCUPIED
                or occupation.state == States.OCCUPATION.COUNTER_ATTACK) then
            local elapsed = math.max(0, now - occupation.last_resumed_at)
            occupation.remaining_seconds = math.max(
                0,
                occupation.remaining_seconds - elapsed
            )
            if occupation.state == States.OCCUPATION.COUNTER_ATTACK
                and occupation.counter_last_resumed_at > 0 then
                local counter_elapsed = math.max(
                    0,
                    now - occupation.counter_last_resumed_at
                )
                occupation.counter_remaining_seconds = math.max(
                    0,
                    occupation.counter_remaining_seconds - counter_elapsed
                )
                occupation.counter_last_resumed_at = 0
            end
            occupation.previous_state = occupation.state
            occupation.state = States.OCCUPATION.PAUSED
            occupation.last_resumed_at = 0
            occupation.frontline_state = "PAUSED"
            occupation.updated_at = now
        end
    end
end

function Conquest:_resume_occupations(war_id, now)
    for _, occupation in pairs(self.occupations) do
        if occupation.war_id == war_id
            and occupation.state == States.OCCUPATION.PAUSED then
            occupation.state = occupation.previous_state ~= ""
                and occupation.previous_state
                or States.OCCUPATION.OCCUPIED
            occupation.previous_state = ""
            occupation.last_resumed_at = now
            if occupation.state == States.OCCUPATION.COUNTER_ATTACK then
                occupation.counter_last_resumed_at = now
                occupation.frontline_state = "COUNTER_ATTACK"
            else
                occupation.frontline_state = "HELD"
            end
            occupation.updated_at = now
        end
    end
end

function Conquest:_finalize_occupation(occupation, now)
    local node = self.nodes[occupation.node_id]
    if not node then return Result.err("NODE_NOT_FOUND", "Isgal node'u yok") end

    occupation.state = States.OCCUPATION.CONQUERED
    occupation.previous_state = ""
    occupation.remaining_seconds = 0
    occupation.last_resumed_at = 0
    occupation.frontline_state = "FINALIZED"
    occupation.updated_at = now
    occupation.counter_flag_reference = ""
    occupation.counter_remaining_seconds = 0
    occupation.counter_last_resumed_at = 0
    occupation.counter_flag_x = 0
    occupation.counter_flag_y = 0
    occupation.counter_flag_z = 0
    node.state = States.NODE.CONQUERED
    set_controller(node, occupation.occupying_guild)
    node.updated_at = now

    self:_event("FAZ05_CONQUEST_FINALIZED", node.node_id)
    self:_event("FAZ05_FRONTLINE_ADVANCED", node.node_id)
    return Result.ok(node)
end

function Conquest:_resolve_peace(campaign, now)
    for _, occupation in pairs(self.occupations) do
        local unresolved = occupation.war_id == campaign.war_id
            and occupation.state ~= States.OCCUPATION.CONQUERED
            and occupation.state ~= States.OCCUPATION.RESTORED
        if unresolved and not self.nodes[occupation.node_id] then
            return Result.err(
                "NODE_NOT_FOUND",
                "Barisla cozulmesi gereken isgal node'u yok"
            )
        end
    end

    for _, occupation in pairs(self.occupations) do
        if occupation.war_id == campaign.war_id
            and occupation.state ~= States.OCCUPATION.CONQUERED
            and occupation.state ~= States.OCCUPATION.RESTORED then
            if self.config.peace_occupation_resolution == "OCCUPIER_WINS" then
                local finalized = self:_finalize_occupation(occupation, now)
                if not finalized.ok then return finalized end
            else
                local node = self.nodes[occupation.node_id]
                set_controller(node, occupation.original_owner)
                node.state = States.NODE.RESTORED
                if text(occupation.counter_flag_reference) ~= "" then
                    node.flag_reference = occupation.counter_flag_reference
                    node.flag_state = States.FLAG.BOUND
                    node.x = number(occupation.counter_flag_x)
                    node.y = number(occupation.counter_flag_y)
                    node.z = number(occupation.counter_flag_z)
                end
                node.updated_at = now
                occupation.state = States.OCCUPATION.RESTORED
                occupation.remaining_seconds = 0
                occupation.last_resumed_at = 0
                occupation.frontline_state = "RESTORED"
                occupation.updated_at = now
                occupation.counter_flag_reference = ""
                occupation.counter_remaining_seconds = 0
                occupation.counter_last_resumed_at = 0
                occupation.counter_flag_x = 0
                occupation.counter_flag_y = 0
                occupation.counter_flag_z = 0
            end
        end
    end

    local target = self.nodes[campaign.active_target_node_id]
    if target and target.current_controller == campaign.defender_guild then
        target.state = States.NODE.PROTECTED
        target.updated_at = now
    end

    campaign.state = States.CAMPAIGN.PEACE_RESOLVED
    campaign.active_target_node_id = ""
    campaign.siege_camp_reference = ""
    campaign.rearm_until = 0
    campaign.updated_at = now
    return Result.ok(true)
end

function Conquest:_campaign_for_occupation(occupation)
    for _, current in pairs(self.campaigns) do
        if current.war_id == occupation.war_id
            and current.attacker_guild == occupation.occupying_guild then
            return current
        end
    end
    return nil
end

function Conquest:_counter_attack_window(occupation, now)
    local elapsed = math.max(0, now - occupation.last_resumed_at)
    if occupation.last_resumed_at <= 0
        or elapsed >= occupation.remaining_seconds then
        return Result.err("OCCUPATION_EXPIRED", "Isgal suresi tamamlandi")
    end

    local campaign = self:_campaign_for_occupation(occupation)
    if not campaign or campaign.state ~= States.CAMPAIGN.ACTIVE then
        return Result.err("CAMPAIGN_NOT_ACTIVE", "Karsi saldiri su an baslatilamaz")
    end

    local relation = self:_relation(
        campaign.attacker_guild,
        campaign.defender_guild
    )
    if not Rules.is_effective_war(relation) then
        return Result.err("WAR_NOT_ACTIVE", "Karsi saldiri savas disinda ilerlemez")
    end

    if not RaidWindow.is_open(now, self.config) then
        return Result.err("RAID_WINDOW_CLOSED", "Karsi saldiri raid saati disinda")
    end

    return Result.ok(campaign)
end

function Conquest:nearest_counter_attack_node(guild_key, location)
    local nearest = nil
    local nearest_distance = math.huge
    for _, occupation in pairs(self.occupations) do
        if occupation.original_owner == text(guild_key)
            and occupation.state == States.OCCUPATION.OCCUPIED then
            local node = self.nodes[occupation.node_id]
            if node then
                local current = Rules.distance(node, location or {})
                if current < nearest_distance then
                    nearest = node
                    nearest_distance = current
                end
            end
        end
    end
    return nearest, nearest_distance
end

function Conquest:start_counter_attack(node_id, guild_key, actor_role, flag, now)
    local authorized = self:_authorized(actor_role)
    if not authorized.ok then return authorized end

    local occupation = self.occupations[text(node_id)]
    if not occupation or occupation.state ~= States.OCCUPATION.OCCUPIED then
        return Result.err("NO_ACTIVE_OCCUPATION", "Karsi saldiri icin aktif isgal yok")
    end

    if occupation.original_owner ~= guild_key then
        return Result.err("NOT_ORIGINAL_OWNER", "Karsi saldiriyi eski sahip baslatabilir")
    end

    now = self:_now(now)
    local window = self:_counter_attack_window(occupation, now)
    if not window.ok then return window end

    flag = flag or {}
    local reference = text(flag.flag_reference)
    if reference == "" or text(flag.guild_key) ~= guild_key then
        return Result.err(
            "COUNTER_FLAG_OWNER_MISMATCH",
            "Karsi saldiri bayragi eski sahibi klana ait olmali"
        )
    end
    if self:_flag_reference_exists(reference) then
        return Result.err(
            "FLAG_ALREADY_REGISTERED",
            "Bu Klan Bayragi zaten fetih sistemine kayitli"
        )
    end

    local node = self.nodes[occupation.node_id]
    local maximum = number(self.config.counter_attack_flag_radius_meters)
    if maximum <= 0 or not node or Rules.distance(node, flag) > maximum then
        return Result.err(
            "COUNTER_FLAG_NOT_NEAR",
            "Karsi saldiri bayragi isgal noktasina yeterince yakin degil"
        )
    end

    local hold_seconds = number(self.config.counter_attack_hold_seconds)
    if hold_seconds <= 0 then
        return Result.err(
            "COUNTER_HOLD_INVALID",
            "Karsi saldiri koruma suresi gecersiz"
        )
    end
    local raid_remaining = RaidWindow.remaining_open_seconds(
        now,
        self.config
    )
    if raid_remaining < hold_seconds then
        return Result.err(
            "COUNTER_HOLD_EXCEEDS_RAID_WINDOW",
            "Karsi saldiri suresi kalan baskin penceresine sigmiyor"
        )
    end
    local occupation_elapsed = math.max(
        0,
        now - occupation.last_resumed_at
    )
    local occupation_remaining = math.max(
        0,
        occupation.remaining_seconds - occupation_elapsed
    )
    if hold_seconds >= occupation_remaining then
        return Result.err(
            "COUNTER_HOLD_EXCEEDS_OCCUPATION",
            "Karsi saldiri isgal bitmeden tamamlanamaz"
        )
    end

    local previous = copy_record(occupation)
    occupation.state = States.OCCUPATION.COUNTER_ATTACK
    occupation.frontline_state = "COUNTER_ATTACK"
    occupation.counter_flag_reference = reference
    occupation.counter_remaining_seconds = hold_seconds
    occupation.counter_last_resumed_at = now
    occupation.counter_flag_x = number(flag.x)
    occupation.counter_flag_y = number(flag.y)
    occupation.counter_flag_z = number(flag.z)
    occupation.updated_at = now
    local saved = self:_save_occupations()
    if not saved.ok then
        restore_record(occupation, previous)
        return saved
    end
    self:_event("FAZ05_COUNTER_ATTACK", node_id .. "|" .. reference)
    return Result.ok(occupation)
end

function Conquest:_apply_occupation_restore(occupation, now)
    local node = self.nodes[occupation.node_id]
    if not node then return Result.err("NODE_NOT_FOUND", "Isgal node'u yok") end

    local replacement = text(occupation.counter_flag_reference)
    set_controller(node, occupation.original_owner)
    node.state = States.NODE.RESTORED
    node.flag_reference = replacement
    node.flag_state = States.FLAG.BOUND
    node.x = number(occupation.counter_flag_x)
    node.y = number(occupation.counter_flag_y)
    node.z = number(occupation.counter_flag_z)
    node.updated_at = now
    occupation.state = States.OCCUPATION.RESTORED
    occupation.previous_state = ""
    occupation.remaining_seconds = 0
    occupation.last_resumed_at = 0
    occupation.frontline_state = "RESTORED"
    occupation.updated_at = now
    occupation.counter_flag_reference = ""
    occupation.counter_remaining_seconds = 0
    occupation.counter_last_resumed_at = 0
    occupation.counter_flag_x = 0
    occupation.counter_flag_y = 0
    occupation.counter_flag_z = 0

    local manifest = self.loot_manifests[occupation.loot_manifest_id]
    if manifest and manifest.state ~= States.LOOT.EXTRACTED then
        local recovered = Loot.recover(
            manifest,
            occupation.original_owner,
            occupation.original_owner
        )
        if not recovered.ok then return recovered end
    end

    for _, campaign in pairs(self.campaigns) do
        if campaign.war_id == occupation.war_id
            and campaign.active_target_node_id ~= "" then
            local target = self.nodes[campaign.active_target_node_id]
            if target and not self:_reachable(campaign, target) then
                target.state = States.NODE.PROTECTED
                target.updated_at = now
                campaign.active_target_node_id = ""
                campaign.updated_at = now
            end
        end
    end

    self:_event("FAZ05_OCCUPATION_RESTORED", occupation.node_id)
    return Result.ok(node)
end

function Conquest:restore_occupation(node_id, guild_key, actor_role, now)
    local authorized = self:_authorized(actor_role)
    if not authorized.ok then return authorized end

    local occupation = self.occupations[text(node_id)]
    if not occupation or occupation.state ~= States.OCCUPATION.COUNTER_ATTACK then
        return Result.err("COUNTER_ATTACK_NOT_ACTIVE", "Aktif karsi saldiri yok")
    end
    if occupation.original_owner ~= guild_key then
        return Result.err("NOT_ORIGINAL_OWNER", "Karakolu eski sahibi geri alabilir")
    end

    now = self:_now(now)
    local window = self:_counter_attack_window(occupation, now)
    if not window.ok then return window end
    local elapsed = math.max(0, now - occupation.counter_last_resumed_at)
    if occupation.counter_last_resumed_at <= 0
        or elapsed < occupation.counter_remaining_seconds then
        return Result.err(
            "COUNTER_ATTACK_HOLD_ACTIVE",
            "Karsi saldiri bayragi henuz yeterince korunmadi"
        )
    end

    local restored = self:_apply_occupation_restore(occupation, now)
    if not restored.ok then return restored end

    local nodes = self.repository:save_nodes(self.nodes)
    if not nodes.ok then return nodes end
    local occupations = self:_save_occupations()
    if not occupations.ok then return occupations end
    local campaigns = self:_save_campaigns()
    if not campaigns.ok then return campaigns end
    local loot = self:_save_loot()
    if not loot.ok then return loot end
    return restored
end

function Conquest:mark_loot_in_transit(manifest_id, guild_key)
    local manifest = self.loot_manifests[text(manifest_id)]
    if not manifest or manifest.owner_guild ~= guild_key then
        return Result.err("WRONG_LOOT_OWNER", "Loot sahibi farkli")
    end

    local previous = copy_record(manifest)
    local result = Loot.mark_in_transit(manifest)
    if not result.ok then return result end
    local saved = self:_save_loot()
    if not saved.ok then
        restore_record(manifest, previous)
        local rollback = self:_save_loot()
        if not rollback.ok and self.logger then
            self.logger:error(
                "FAZ05_LOOT_ROLLBACK_WRITE_FAILED | " ..
                Result.describe(rollback)
            )
        end
        return saved
    end
    return result
end

function Conquest:extract_loot(manifest_id, guild_key, now)
    local manifest = self.loot_manifests[text(manifest_id)]
    if not manifest then return Result.err("LOOT_NOT_FOUND", "Loot bulunamadi") end

    local campaign
    for _, current in pairs(self.campaigns) do
        if current.war_id == manifest.war_id
            and current.attacker_guild == manifest.owner_guild then
            campaign = current
            break
        end
    end

    local extraction_open = campaign
        and (
            campaign.state == States.CAMPAIGN.ACTIVE
            or campaign.state == States.CAMPAIGN.PEACE_RESOLVED
            or campaign.state == States.CAMPAIGN.CAPITAL_DEFEATED
        )
    if not extraction_open then
        return Result.err(
            "LOOT_EXTRACTION_PAUSED",
            "Ateskes veya yeniden silahlanmada loot cikarilamaz"
        )
    end

    local previous = copy_record(manifest)
    local result = Loot.extract(manifest, guild_key, self:_now(now))
    if not result.ok then return result end
    local saved = self:_save_loot()
    if not saved.ok then
        restore_record(manifest, previous)
        local rollback = self:_save_loot()
        if not rollback.ok and self.logger then
            self.logger:error(
                "FAZ05_LOOT_ROLLBACK_WRITE_FAILED | " ..
                Result.describe(rollback)
            )
        end
        return saved
    end
    self:_event("FAZ05_LOOT_EXTRACTED", manifest_id)
    return result
end

function Conquest:tick(now)
    now = self:_now(now)
    local changed = false

    for _, campaign in pairs(self.campaigns) do
        if campaign.state == States.CAMPAIGN.CAPITAL_DEFEATED then
            local relation = self:_relation(
                campaign.attacker_guild,
                campaign.defender_guild
            )
            if Rules.is_effective_war(relation)
                and self.diplomacy
                and self.diplomacy.resolve_capital_defeat then
                local relation_state = relation.state
                local resolved = self.diplomacy:resolve_capital_defeat(
                    campaign.attacker_guild,
                    campaign.defender_guild,
                    "PalTR Conquest Recovery"
                )
                if not resolved.ok then return resolved end
                campaign.previous_relation_state = relation_state
                campaign.updated_at = now
                changed = true
            end
        elseif campaign.state ~= States.CAMPAIGN.PEACE_RESOLVED then
            local relation = self:_relation(
                campaign.attacker_guild,
                campaign.defender_guild
            )

            if is_ceasefire(relation) then
                if campaign.state ~= States.CAMPAIGN.CEASEFIRE_PAUSED then
                    self:_pause_occupations(campaign.war_id, now)
                    campaign.state = States.CAMPAIGN.CEASEFIRE_PAUSED
                    campaign.rearm_until = 0
                    campaign.updated_at = now
                    changed = true
                end
            elseif Rules.is_effective_war(relation) then
                if campaign.state == States.CAMPAIGN.CEASEFIRE_PAUSED then
                    campaign.state = States.CAMPAIGN.REARMING
                    campaign.rearm_until = now + number(
                        self.diplomacy.config.diplomacy.ceasefire_rearm_seconds
                    )
                    campaign.updated_at = now
                    changed = true
                elseif campaign.state == States.CAMPAIGN.REARMING
                    and now >= campaign.rearm_until then
                    campaign.state = States.CAMPAIGN.ACTIVE
                    campaign.rearm_until = 0
                    campaign.updated_at = now
                    self:_resume_occupations(campaign.war_id, now)
                    changed = true
                end
            else
                local resolved = self:_resolve_peace(campaign, now)
                if not resolved.ok then return resolved end
                changed = true
            end

            campaign.previous_relation_state = relation and relation.state or ""
        end
    end

    for _, occupation in pairs(self.occupations) do
        if occupation.state == States.OCCUPATION.OCCUPIED
            or occupation.state == States.OCCUPATION.COUNTER_ATTACK then
            local occupation_deadline = occupation.last_resumed_at
                + occupation.remaining_seconds
            local occupation_expired = now >= occupation_deadline
            local counter_wins = false

            if occupation.state == States.OCCUPATION.COUNTER_ATTACK
                and occupation.counter_last_resumed_at > 0 then
                local counter_deadline = occupation.counter_last_resumed_at
                    + occupation.counter_remaining_seconds
                counter_wins = now >= counter_deadline
                    and (
                        not occupation_expired
                        or counter_deadline < occupation_deadline
                    )
            end

            if counter_wins then
                local restored = self:_apply_occupation_restore(
                    occupation,
                    now
                )
                if not restored.ok then return restored end
                changed = true
            elseif occupation_expired then
                local finalized = self:_finalize_occupation(occupation, now)
                if not finalized.ok then return finalized end
                changed = true
            end
        end
    end

    if changed then
        local nodes = self.repository:save_nodes(self.nodes)
        if not nodes.ok then return nodes end
        local occupations = self:_save_occupations()
        if not occupations.ok then return occupations end
        local campaigns = self:_save_campaigns()
        if not campaigns.ok then return campaigns end
        local loot = self:_save_loot()
        if not loot.ok then return loot end
    end

    return Result.ok(changed)
end

return Conquest
