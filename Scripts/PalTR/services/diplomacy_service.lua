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

local function copy_record(record)
    local copy = {}
    for key, value in pairs(record or {}) do copy[key] = value end
    return copy
end

local function restore_record(record, snapshot)
    for key in pairs(record or {}) do record[key] = nil end
    for key, value in pairs(snapshot or {}) do record[key] = value end
end

function Diplomacy.new(paths, config, logger)
    return setmetatable({
        paths = paths,
        config = config,
        logger = logger,
        relations = Repositories.load_relations(paths.relations)
    }, Diplomacy)
end

function Diplomacy:_event(event_type, relation, detail)
    local result = FileIO.append(self.paths.events, TSV.encode({
        Clock.now(),
        event_type,
        relation and relation.key or "",
        detail or ""
    }))
    if not result.ok and self.logger then
        self.logger:error(
            "Diplomasi olayi yazilamadi: " ..
            tostring(result.error and result.error.message or "")
        )
    end
    return result
end

function Diplomacy:_save()
    return Repositories.save_relations(
        self.paths.relations,
        self.relations
    )
end

function Diplomacy:_commit_transition(
    relation,
    snapshot,
    result,
    note,
    event_type,
    detail
)
    if not result.ok then return result end

    relation.note = note
    local saved = self:_save()
    if not saved.ok then
        restore_record(relation, snapshot)
        return saved
    end

    self:_event(event_type, relation, detail)
    return result
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
    local saved = self:_save()
    if not saved.ok then
        self.relations[relation.key] = nil
        return nil, saved.error.message
    end

    return relation
end

function Diplomacy:declare_war(own, target, actor)
    local relation, error_message = self:get(own, target)

    if not relation then
        return Result.err("RELATION", error_message)
    end

    local snapshot = copy_record(relation)
    local result = Rules.declare_war(
        relation,
        own,
        self.config
    )
    return self:_commit_transition(
        relation, snapshot, result,
        "Savas ilani: " .. actor,
        "WAR_DECLARED", actor
    )
end

function Diplomacy:request_ceasefire(own, target, actor)
    local relation, error_message = self:get(own, target)

    if not relation then
        return Result.err("RELATION", error_message)
    end

    local snapshot = copy_record(relation)
    local result = Rules.request_ceasefire(
        relation,
        own,
        self.config
    )

    return self:_commit_transition(
        relation, snapshot, result,
        "Ateskes teklifi: " .. actor,
        "CEASEFIRE_REQUESTED", actor
    )
end

function Diplomacy:request_peace(own, target, actor)
    local relation, error_message = self:get(own, target)

    if not relation then
        return Result.err("RELATION", error_message)
    end

    local snapshot = copy_record(relation)
    local result = Rules.request_peace(
        relation,
        own,
        self.config
    )

    return self:_commit_transition(
        relation, snapshot, result,
        "Baris teklifi: " .. actor,
        "PEACE_REQUESTED", actor
    )
end

function Diplomacy:request_alliance(own, target, actor)
    local relation, error_message = self:get(own, target)

    if not relation then
        return Result.err("RELATION", error_message)
    end

    local snapshot = copy_record(relation)
    local result = Rules.request_alliance(
        relation,
        own,
        self.config
    )

    return self:_commit_transition(
        relation, snapshot, result,
        "Ittifak teklifi: " .. actor,
        "ALLIANCE_REQUESTED", actor
    )
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

    local snapshot = copy_record(relation)
    local result = Rules.accept(
        relation,
        own,
        self.config
    )
    return self:_commit_transition(
        relation, snapshot, result,
        "Kabul eden: " .. actor,
        "PROPOSAL_ACCEPTED", actor
    )
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

    local snapshot = copy_record(relation)
    local result = Rules.reject(relation, own)
    return self:_commit_transition(
        relation, snapshot, result,
        "Reddeden: " .. actor,
        "PROPOSAL_REJECTED", actor
    )
end

function Diplomacy:cancel(own, target, actor)
    local relation, error_message = self:get(own, target)

    if not relation then
        return Result.err("RELATION", error_message)
    end

    local snapshot = copy_record(relation)
    local result = Rules.cancel(relation, own)
    return self:_commit_transition(
        relation, snapshot, result,
        "Teklif iptal edildi: " .. actor,
        "PROPOSAL_CANCELLED", actor
    )
end

function Diplomacy:break_ceasefire(own, target, actor)
    local relation, error_message = self:get(own, target)

    if not relation then
        return Result.err("RELATION", error_message)
    end

    local snapshot = copy_record(relation)
    local result = Rules.break_ceasefire(relation)
    return self:_commit_transition(
        relation, snapshot, result,
        "Ateskesi bozan: " .. actor,
        "CEASEFIRE_BROKEN", actor
    )
end

function Diplomacy:return_neutral(own, target, actor)
    local relation, error_message = self:get(own, target)

    if not relation then
        return Result.err("RELATION", error_message)
    end

    local snapshot = copy_record(relation)
    local result = Rules.return_neutral(relation)
    return self:_commit_transition(
        relation, snapshot, result,
        "Ittifaktan ayrilan: " .. actor,
        "ALLIANCE_ENDED", actor
    )
end

function Diplomacy:resolve_capital_defeat(winner, loser, actor)
    local relation, error_message = self:get(winner, loser)

    if not relation then
        return Result.err("RELATION", error_message)
    end

    local snapshot = copy_record(relation)
    local result = Rules.resolve_capital_defeat(relation)
    return self:_commit_transition(
        relation, snapshot, result,
        "Baskent yenilgisi: " .. tostring(actor or winner),
        "CAPITAL_DEFEATED",
        tostring(winner) .. ">" .. tostring(loser)
    )
end

function Diplomacy:tick()
    local changed = 0
    local events = {}
    local snapshots = {}

    for _, relation in pairs(self.relations) do
        snapshots[relation.key] = copy_record(relation)
        local event_name = Rules.tick(
            relation,
            self.config
        )

        if event_name then
            changed = changed + 1
            table.insert(events, {
                name = event_name,
                relation = relation,
                detail = relation.state
            })
        end
    end

    if changed > 0 then
        local saved = self:_save()
        if not saved.ok then
            for key, snapshot in pairs(snapshots) do
                local relation = self.relations[key]
                if relation then restore_record(relation, snapshot) end
            end
            if self.logger then
                self.logger:error(
                    "Diplomasi tick kaydedilemedi: " ..
                    tostring(saved.error and saved.error.message or "")
                )
            end
            return {}
        end

        for _, event in ipairs(events) do
            self:_event(
                event.name,
                event.relation,
                event.detail
            )
        end
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
