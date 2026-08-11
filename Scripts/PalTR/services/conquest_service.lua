local Clock = require("PalTR.core.clock")
local FileIO = require("PalTR.storage.file_io")
local Result = require("PalTR.core.result")
local TSV = require("PalTR.storage.tsv")
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
        loot_items = repository:load_loot_items()
    }, Conquest)
end

function Conquest:_now(value)
    return number(value or self.clock.now())
end

function Conquest:_event(marker, detail)
    if self.paths and self.paths.conquest_events then
        FileIO.append(
            self.paths.conquest_events,
            TSV.encode({ self:_now(), marker, detail or "" })
        )
    end

    if self.logger then
        self.logger:info(marker .. " | " .. text(detail))
    end
end

function Conquest:_save_nodes_and_edges()
    local nodes = self.repository:save_nodes(self.nodes)
    if not nodes.ok then return nodes end
    return self.repository:save_edges(self.edges)
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
        local current_distance = Rules.distance(node, location or {})

        if current_distance < nearest_distance then
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
        campaigns = {},
        occupations = {}
    }

    for _, node in ipairs(self:nodes_for_controller(guild_key)) do
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

            table.insert(status.occupations, {
                node_id = occupation.node_id,
                state = occupation.state,
                remaining_seconds = remaining,
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
        if node.flag_reference == reference then return true end
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
        x = number(request.x),
        y = number(request.y),
        z = number(request.z),
        parent_node_id = "",
        state = States.NODE.PROTECTED,
        original_owner = guild_key,
        current_controller = guild_key,
        created_at = now,
        updated_at = now
    }

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
        local id = edge_id(parent.node_id, node.node_id)
        self.edges[id] = {
            key = id,
            edge_id = id,
            node_a = parent.node_id,
            node_b = node.node_id,
            created_at = now
        }
    end

    self.nodes[node_id] = node
    local saved = self:_save_nodes_and_edges()
    if not saved.ok then return saved end

    self:_event("FAZ05_FLAG_REGISTERED", node_id .. "|" .. node_type)
    return Result.ok(node)
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

    self.campaigns[campaign_id] = campaign
    local saved = self:_save_campaigns()
    if not saved.ok then return saved end
    return Result.ok(campaign)
end

function Conquest:_captured_frontline(campaign)
    local result = {}

    for _, node in pairs(self.nodes) do
        if node.original_owner == campaign.defender_guild
            and node.current_controller == campaign.attacker_guild
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

    if not self:_reachable(campaign, target) then
        return Result.err("TARGET_NOT_FRONTLINE_REACHABLE", "Fetih hatti hedefe ulasmiyor")
    end

    target.state = target.node_type == States.NODE_TYPE.CAPITAL
        and States.NODE.CAPITAL_TARGETABLE
        or States.NODE.TARGETABLE
    target.updated_at = now
    campaign.active_target_node_id = target.node_id
    campaign.updated_at = now

    local nodes = self.repository:save_nodes(self.nodes)
    if not nodes.ok then return nodes end
    local campaigns = self:_save_campaigns()
    if not campaigns.ok then return campaigns end

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
        campaign.siege_camp_reference = ""
        campaign.siege_x = 0
        campaign.siege_y = 0
        campaign.siege_z = 0
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

    local nodes = {}
    for _, node in pairs(self.nodes) do table.insert(nodes, node) end
    table.sort(nodes, function(first, second)
        return first.node_id < second.node_id
    end)

    for _, node in ipairs(nodes) do
        if node.flag_reference ~= "" then
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
            end
        end
    end

    return FileIO.overwrite(self.paths.conquest_damage_policy, lines)
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

    local processed = 0

    for index, line in ipairs(loaded.value or {}) do
        if index > 1 and line ~= "" then
            local columns = TSV.decode(line)
            local event_at = number(columns[1])
            local marker = text(columns[2])
            local reference = text(columns[3])

            if marker == "FLAG_DISPOSED" and reference ~= "" then
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
                end
            end
        end
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
        target.state = next_state
        target.updated_at = self:_now(now)
        local saved = self.repository:save_nodes(self.nodes)
        if not saved.ok then return saved end
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
        updated_at = now
    }

    self.occupations[node.node_id] = occupation
    node.state = States.NODE.OCCUPIED
    node.current_controller = campaign.attacker_guild
    node.guild_key = campaign.attacker_guild
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
            node.current_controller = campaign.attacker_guild
            node.guild_key = campaign.attacker_guild
            node.state = States.NODE.CONQUERED
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
            occupation.frontline_state = "HELD"
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
    node.state = States.NODE.CONQUERED
    node.current_controller = occupation.occupying_guild
    node.guild_key = occupation.occupying_guild
    node.updated_at = now

    self:_event("FAZ05_CONQUEST_FINALIZED", node.node_id)
    self:_event("FAZ05_FRONTLINE_ADVANCED", node.node_id)
    return Result.ok(node)
end

function Conquest:_resolve_peace(campaign, now)
    for _, occupation in pairs(self.occupations) do
        if occupation.war_id == campaign.war_id
            and occupation.state ~= States.OCCUPATION.CONQUERED
            and occupation.state ~= States.OCCUPATION.RESTORED then
            if self.config.peace_occupation_resolution == "OCCUPIER_WINS" then
                self:_finalize_occupation(occupation, now)
            else
                local node = self.nodes[occupation.node_id]
                if node then
                    node.current_controller = occupation.original_owner
                    node.guild_key = occupation.original_owner
                    node.state = States.NODE.RESTORED
                    node.updated_at = now
                end
                occupation.state = States.OCCUPATION.RESTORED
                occupation.remaining_seconds = 0
                occupation.last_resumed_at = 0
                occupation.frontline_state = "RESTORED"
                occupation.updated_at = now
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
end

function Conquest:start_counter_attack(node_id, guild_key, actor_role, now)
    local authorized = self:_authorized(actor_role)
    if not authorized.ok then return authorized end

    local occupation = self.occupations[text(node_id)]
    if not occupation or occupation.state ~= States.OCCUPATION.OCCUPIED then
        return Result.err("NO_ACTIVE_OCCUPATION", "Karsi saldiri icin aktif isgal yok")
    end

    if occupation.original_owner ~= guild_key then
        return Result.err("NOT_ORIGINAL_OWNER", "Karsi saldiriyi eski sahip baslatabilir")
    end

    local campaign
    for _, current in pairs(self.campaigns) do
        if current.war_id == occupation.war_id
            and current.attacker_guild == occupation.occupying_guild then
            campaign = current
            break
        end
    end

    if not campaign or campaign.state ~= States.CAMPAIGN.ACTIVE then
        return Result.err("CAMPAIGN_NOT_ACTIVE", "Karsi saldiri su an baslatilamaz")
    end

    local raid_open = RaidWindow.is_open(self:_now(now), self.config)
    if not raid_open then
        return Result.err("RAID_WINDOW_CLOSED", "Karsi saldiri raid saati disinda")
    end

    occupation.state = States.OCCUPATION.COUNTER_ATTACK
    occupation.frontline_state = "COUNTER_ATTACK"
    occupation.updated_at = self:_now(now)
    local saved = self:_save_occupations()
    if not saved.ok then return saved end
    self:_event("FAZ05_COUNTER_ATTACK", node_id)
    return Result.ok(occupation)
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
    local node = self.nodes[occupation.node_id]
    node.current_controller = occupation.original_owner
    node.guild_key = occupation.original_owner
    node.state = States.NODE.RESTORED
    node.updated_at = now
    occupation.state = States.OCCUPATION.RESTORED
    occupation.previous_state = ""
    occupation.remaining_seconds = 0
    occupation.last_resumed_at = 0
    occupation.frontline_state = "RESTORED"
    occupation.updated_at = now

    local manifest = self.loot_manifests[occupation.loot_manifest_id]
    if manifest and manifest.state ~= States.LOOT.EXTRACTED then
        Loot.recover(manifest, guild_key, occupation.original_owner)
        self:_save_loot()
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

    local nodes = self.repository:save_nodes(self.nodes)
    if not nodes.ok then return nodes end
    local occupations = self:_save_occupations()
    if not occupations.ok then return occupations end
    self:_save_campaigns()
    self:_event("FAZ05_OCCUPATION_RESTORED", node_id)
    return Result.ok(node)
end

function Conquest:mark_loot_in_transit(manifest_id, guild_key)
    local manifest = self.loot_manifests[text(manifest_id)]
    if not manifest or manifest.owner_guild ~= guild_key then
        return Result.err("WRONG_LOOT_OWNER", "Loot sahibi farkli")
    end

    local result = Loot.mark_in_transit(manifest)
    if not result.ok then return result end
    local saved = self:_save_loot()
    if not saved.ok then return saved end
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

    if not campaign or campaign.state ~= States.CAMPAIGN.ACTIVE then
        return Result.err("LOOT_EXTRACTION_PAUSED", "Ateskes veya rearm sirasinda loot cikarilamaz")
    end

    local result = Loot.extract(manifest, guild_key, self:_now(now))
    if not result.ok then return result end
    local saved = self:_save_loot()
    if not saved.ok then return saved end
    self:_event("FAZ05_LOOT_EXTRACTED", manifest_id)
    return result
end

function Conquest:tick(now)
    now = self:_now(now)
    local changed = false

    for _, campaign in pairs(self.campaigns) do
        if campaign.state ~= States.CAMPAIGN.PEACE_RESOLVED
            and campaign.state ~= States.CAMPAIGN.CAPITAL_DEFEATED then
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
                self:_resolve_peace(campaign, now)
                changed = true
            end

            campaign.previous_relation_state = relation and relation.state or ""
        end
    end

    for _, occupation in pairs(self.occupations) do
        if occupation.state == States.OCCUPATION.OCCUPIED
            or occupation.state == States.OCCUPATION.COUNTER_ATTACK then
            local elapsed = math.max(0, now - occupation.last_resumed_at)
            if elapsed >= occupation.remaining_seconds then
                self:_finalize_occupation(occupation, now)
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
