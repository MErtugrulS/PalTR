local Result = require("PalTR.core.result")
local States = require("PalTR.domain.conquest_states")

local Loot = {}

local function number(value)
    return tonumber(value) or 0
end

local function enabled_entries(config)
    local entries = {}

    for _, entry in ipairs(config and config.loot_table or {}) do
        local has_identity = tostring(entry.item_id or "") ~= ""
            or tostring(entry.item_selector or "") ~= ""
        local weight = math.max(0, number(entry.weight))

        if entry.enabled == true and has_identity and weight > 0 then
            table.insert(entries, {
                source = entry,
                weight = weight
            })
        end
    end

    return entries
end

local function choose(entries, random)
    local total = 0

    for _, entry in ipairs(entries) do
        total = total + entry.weight
    end

    if total <= 0 then
        return nil
    end

    local roll = math.max(0, math.min(0.999999, random())) * total

    for _, entry in ipairs(entries) do
        roll = roll - entry.weight

        if roll < 0 then
            return entry.source
        end
    end

    return entries[#entries].source
end

local function quantity(entry, random)
    local minimum = math.max(0, math.floor(number(entry.min_quantity)))
    local maximum = math.max(minimum, math.floor(number(entry.max_quantity)))

    if maximum == minimum then
        return minimum
    end

    local roll = math.max(
        0,
        math.min(0.999999, tonumber(random()) or 0)
    )
    return minimum + math.floor(roll * (maximum - minimum + 1))
end

function Loot.create(node, campaign, config, now, random)
    random = random or math.random
    now = number(now)

    if not node or not campaign then
        return Result.err("LOOT_CONTEXT_MISSING", "Node veya campaign yok")
    end

    local entries = enabled_entries(config)
    local selected = choose(entries, random)

    if not selected then
        return Result.err("LOOT_TABLE_EMPTY", "Etkin loot girdisi yok")
    end

    local count = quantity(selected, random)

    if count <= 0 then
        return Result.err("LOOT_QUANTITY_ZERO", "Loot miktari sifir")
    end

    local manifest_id = table.concat({
        campaign.war_id,
        node.node_id,
        tostring(now)
    }, "::")

    local manifest = {
        key = manifest_id,
        manifest_id = manifest_id,
        node_id = node.node_id,
        war_id = campaign.war_id,
        owner_guild = campaign.attacker_guild,
        state = States.LOOT.CREATED,
        created_at = now,
        extracted_at = 0
    }

    local item_key = manifest_id .. "::1"
    local item = {
        key = item_key,
        item_key = item_key,
        manifest_id = manifest_id,
        item_id = tostring(selected.item_id or ""),
        item_selector = tostring(selected.item_selector or ""),
        quantity = count,
        tier = tostring(selected.tier or ""),
        category = tostring(selected.category or "")
    }

    return Result.ok({
        manifest = manifest,
        items = { [item_key] = item },
        physical_item_resolved = item.item_id ~= ""
    })
end

function Loot.mark_in_transit(manifest)
    if not manifest or manifest.state ~= States.LOOT.CREATED then
        return Result.err("LOOT_NOT_AVAILABLE", "Loot tasinmaya hazir degil")
    end

    manifest.state = States.LOOT.IN_TRANSIT
    return Result.ok(manifest)
end

function Loot.extract(manifest, guild_key, now)
    if not manifest
        or (manifest.state ~= States.LOOT.CREATED
            and manifest.state ~= States.LOOT.IN_TRANSIT) then
        return Result.err("LOOT_NOT_EXTRACTABLE", "Loot cikarilamaz")
    end

    if manifest.owner_guild ~= guild_key then
        return Result.err("WRONG_LOOT_OWNER", "Loot sahibi farkli")
    end

    manifest.state = States.LOOT.EXTRACTED
    manifest.extracted_at = number(now)
    return Result.ok(manifest)
end

function Loot.recover(manifest, guild_key, original_owner)
    if not manifest or manifest.state == States.LOOT.EXTRACTED then
        return Result.err("LOOT_NOT_RECOVERABLE", "Loot geri alinamaz")
    end

    if guild_key ~= original_owner then
        return Result.err("WRONG_RECOVERY_GUILD", "Yalniz eski sahip geri alabilir")
    end

    manifest.state = States.LOOT.RECOVERED
    return Result.ok(manifest)
end

return Loot
