local Rules = require("PalTR.domain.relation_rules")

local Actions = {}
Actions.__index = Actions

local definitions = {
    { id = "DECLARE_WAR", label = "Savas Ilan Et", test = function(r, own, c) return Rules.declare_war(r, own, c) end },
    { id = "ALLIANCE", label = "Ittifak Teklif Et", test = function(r, own, c) return Rules.request_alliance(r, own, c) end },
    { id = "CEASEFIRE", label = "Ateskes Teklif Et", test = function(r, own, c) return Rules.request_ceasefire(r, own, c) end },
    { id = "PEACE", label = "Baris Teklif Et", test = function(r, own, c) return Rules.request_peace(r, own, c) end },
    { id = "BREAK_CEASEFIRE", label = "Ateskesi Boz", test = function(r) return Rules.break_ceasefire(r) end },
    { id = "ACCEPT", label = "Kabul Et", test = function(r, own, c) return Rules.accept(r, own, c) end },
    { id = "REJECT", label = "Reddet", test = function(r, own) return Rules.reject(r, own) end },
    { id = "CANCEL", label = "Teklifi Iptal Et", test = function(r, own) return Rules.cancel(r, own) end },
    { id = "RETURN_NEUTRAL", label = "Ittifaktan Ayril", test = function(r) return Rules.return_neutral(r) end }
}

local function clone_relation(source)
    local copy = {}
    for key, value in pairs(source or {}) do
        copy[key] = value
    end
    return copy
end

function Actions.new(config)
    return setmetatable({ config = config }, Actions)
end

function Actions:for_relation(player, relation)
    local result = {
        can_manage = false,
        reason = "",
        actions = {}
    }

    if not player or not player.is_master then
        result.reason = "Diplomasi islemlerini yalnizca klan lideri yonetebilir."
        return result
    end

    local own = player.guild_key or ""
    if own == "" or relation == nil then
        result.reason = "Klan veya diplomasi kaydi bulunamadi."
        return result
    end

    result.can_manage = true

    for _, definition in ipairs(definitions) do
        local copy = clone_relation(relation)
        local ok, rule_result = pcall(definition.test, copy, own, self.config)

        if ok and rule_result and rule_result.ok == true then
            table.insert(result.actions, {
                id = definition.id,
                label = definition.label
            })
        end
    end

    return result
end

return Actions
