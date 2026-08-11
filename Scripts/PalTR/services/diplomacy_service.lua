local Repositories = require("PalTR.storage.repositories")
local PairKey = require("PalTR.domain.pair_key")
local Rules = require("PalTR.domain.relation_rules")
local States = require("PalTR.domain.states")
local Clock = require("PalTR.core.clock")
local FileIO = require("PalTR.storage.file_io")
local TSV = require("PalTR.storage.tsv")
local Result = require("PalTR.core.result")

local Diplomacy = {}
Diplomacy.__index = Diplomacy

function Diplomacy.new(paths, config, logger)
    return setmetatable({
        paths = paths,
        config = config,
        logger = logger,
        relations = Repositories.load_relations(paths.relations)
    }, Diplomacy)
end

function Diplomacy:_event(event_type, relation, detail)
    FileIO.append(self.paths.events, TSV.encode({
        Clock.now(),
        event_type,
        relation and relation.key or "",
        detail or ""
    }))
end

function Diplomacy:_save()
    Repositories.save_relations(
        self.paths.relations,
        self.relations
    )
end

function Diplomacy:get(first, second)
    local pair = PairKey.create(first, second)

    if not pair.ok then
        return nil, pair.error.message
    end

    local relation = self.relations[pair.value.key]

    if relation then
        return relation
    end

    relation = {
        key = pair.value.key,
        guild_a = pair.value.a,
        guild_b = pair.value.b,
        state = States.NEUTRAL,
        previous_state = States.NEUTRAL,
        requested_by = "",
        accepted_by = "",
        created_at = Clock.now(),
        updated_at = Clock.now(),
        active_at = 0,
        expires_at = 0,
        note = ""
    }

    self.relations[relation.key] = relation
    self:_save()

    return relation
end

function Diplomacy:declare_war(own, target, actor)
    local relation, error_message = self:get(own, target)

    if not relation then
        return Result.err("RELATION", error_message)
    end

    local result = Rules.declare_war(
        relation,
        own,
        self.config
    )

    if result.ok then
        relation.note = "Savas ilani: " .. actor
        self:_save()
        self:_event("WAR_DECLARED", relation, actor)
    end

    return result
end

function Diplomacy:request_ceasefire(own, target, actor)
    local relation, error_message = self:get(own, target)

    if not relation then
        return Result.err("RELATION", error_message)
    end

    local result = Rules.request_ceasefire(
        relation,
        own,
        self.config
    )

    if result.ok then
        relation.note = "Ateskes teklifi: " .. actor
        self:_save()
        self:_event(
            "CEASEFIRE_REQUESTED",
            relation,
            actor
        )
    end

    return result
end

function Diplomacy:request_peace(own, target, actor)
    local relation, error_message = self:get(own, target)

    if not relation then
        return Result.err("RELATION", error_message)
    end

    local result = Rules.request_peace(
        relation,
        own,
        self.config
    )

    if result.ok then
        relation.note = "Baris teklifi: " .. actor
        self:_save()
        self:_event(
            "PEACE_REQUESTED",
            relation,
            actor
        )
    end

    return result
end

function Diplomacy:request_alliance(own, target, actor)
    local relation, error_message = self:get(own, target)

    if not relation then
        return Result.err("RELATION", error_message)
    end

    local result = Rules.request_alliance(
        relation,
        own,
        self.config
    )

    if result.ok then
        relation.note = "Ittifak teklifi: " .. actor
        self:_save()
        self:_event(
            "ALLIANCE_REQUESTED",
            relation,
            actor
        )
    end

    return result
end

function Diplomacy:accept(own, target, actor)
    local relation, error_message = self:get(own, target)

    if not relation then
        return Result.err("RELATION", error_message)
    end

    if relation.requested_by ~= target then
        return Result.err(
            "NOT_TARGET",
            "Bu klandan bekleyen teklif yok"
        )
    end

    local result = Rules.accept(
        relation,
        own,
        self.config
    )

    if result.ok then
        relation.note = "Kabul eden: " .. actor
        self:_save()
        self:_event(
            "PROPOSAL_ACCEPTED",
            relation,
            actor
        )
    end

    return result
end

function Diplomacy:reject(own, target, actor)
    local relation, error_message = self:get(own, target)

    if not relation then
        return Result.err("RELATION", error_message)
    end

    if relation.requested_by ~= target then
        return Result.err(
            "NOT_TARGET",
            "Bu klandan bekleyen teklif yok"
        )
    end

    local result = Rules.reject(relation, own)

    if result.ok then
        relation.note = "Reddeden: " .. actor
        self:_save()
        self:_event(
            "PROPOSAL_REJECTED",
            relation,
            actor
        )
    end

    return result
end

function Diplomacy:cancel(own, target, actor)
    local relation, error_message = self:get(own, target)

    if not relation then
        return Result.err("RELATION", error_message)
    end

    local result = Rules.cancel(relation, own)

    if result.ok then
        relation.note = "Teklif iptal edildi: " .. actor
        self:_save()
        self:_event(
            "PROPOSAL_CANCELLED",
            relation,
            actor
        )
    end

    return result
end

function Diplomacy:break_ceasefire(own, target, actor)
    local relation, error_message = self:get(own, target)

    if not relation then
        return Result.err("RELATION", error_message)
    end

    local result = Rules.break_ceasefire(relation)

    if result.ok then
        relation.note = "Ateskesi bozan: " .. actor
        self:_save()
        self:_event(
            "CEASEFIRE_BROKEN",
            relation,
            actor
        )
    end

    return result
end

function Diplomacy:return_neutral(own, target, actor)
    local relation, error_message = self:get(own, target)

    if not relation then
        return Result.err("RELATION", error_message)
    end

    local result = Rules.return_neutral(relation)

    if result.ok then
        relation.note = "Ittifaktan ayrilan: " .. actor
        self:_save()
        self:_event(
            "ALLIANCE_ENDED",
            relation,
            actor
        )
    end

    return result
end

function Diplomacy:resolve_capital_defeat(winner, loser, actor)
    local relation, error_message = self:get(winner, loser)

    if not relation then
        return Result.err("RELATION", error_message)
    end

    local result = Rules.resolve_capital_defeat(relation)

    if result.ok then
        relation.note = "Baskent yenilgisi: " .. tostring(actor or winner)
        self:_save()
        self:_event(
            "CAPITAL_DEFEATED",
            relation,
            tostring(winner) .. ">" .. tostring(loser)
        )
    end

    return result
end

function Diplomacy:tick()
    local changed = 0
    local events = {}

    for _, relation in pairs(self.relations) do
        local event_name = Rules.tick(
            relation,
            self.config
        )

        if event_name then
            changed = changed + 1

            self:_event(
                event_name,
                relation,
                relation.state
            )

            table.insert(events, {
                name = event_name,
                relation = relation
            })
        end
    end

    if changed > 0 then
        self:_save()
    end

    return events
end

function Diplomacy:relations_for(guild_key)
    local result = {}

    for _, relation in pairs(self.relations) do
        if relation.guild_a == guild_key
            or relation.guild_b == guild_key then

            table.insert(result, relation)
        end
    end

    return result
end

return Diplomacy
