local Text = require("PalTR.core.text")
local Result = require("PalTR.core.result")

local Parser = {}

local aliases = {
    ["!test"] = "TEST",
    ["/paltr"] = "PALTR",
    ["!paltr"] = "PALTR",
    ["/savas"] = "DECLARE_WAR",
    ["!savas"] = "DECLARE_WAR",
    ["/ateskes"] = "CEASEFIRE",
    ["!ateskes"] = "CEASEFIRE",
    ["/ittifak"] = "ALLIANCE",
    ["!ittifak"] = "ALLIANCE",
    ["/kabul"] = "ACCEPT",
    ["!kabul"] = "ACCEPT",
    ["/reddet"] = "REJECT",
    ["!reddet"] = "REJECT"
}

function Parser.parse(message)
    local words = Text.split_words(message)
    if #words == 0 then
        return Result.err("EMPTY", "Bos mesaj")
    end

    local action = aliases[Text.lower_ascii(words[1])]
    if not action then
        return Result.err("NOT_COMMAND", "PalTR komutu degil")
    end

    local target_start = 2

    if action == "PALTR" then
        local sub = Text.lower_ascii(words[2] or "durum")
        target_start = 3

        if sub == "durum" then
            action = "STATUS"
        elseif sub == "klanlar" then
            action = "GUILDS"
        elseif sub == "yardim" then
            action = "HELP"
        else
            return Result.err(
                "UNKNOWN_SUBCOMMAND",
                "Bilinmeyen /paltr komutu"
            )
        end
    end

    return Result.ok({
        action = action,
        target = Text.join_from(words, target_start),
        raw = Text.clean(message)
    })
end

return Parser
