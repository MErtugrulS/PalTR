local Text = require("PalTR.core.text")
local Result = require("PalTR.core.result")

local Parser = {}

local aliases = {
    ["!durum"] = "STATUS",
    ["!klanlar"] = "GUILDS",
    ["!iliskiler"] = "RELATIONS",
    ["!yardim"] = "HELP",
    ["!fetihdurum"] = "CONQUEST_STATUS",
    ["!baskent"] = "REGISTER_CAPITAL",
    ["!karakol"] = "REGISTER_OUTPOST",
    ["!bolgeadi"] = "RENAME_TERRITORY",
    ["!bolgesinir"] = "SET_TERRITORY_RADIUS",
    ["!fetih"] = "START_CONQUEST",
    ["!kusatmakampi"] = "ESTABLISH_SIEGE",
    ["!fetihedef"] = "SELECT_CONQUEST_TARGET",
    ["!bayrakaday"] = "FLAG_CANDIDATE",
    ["!fetihbayragi"] = "REBIND_MISSING_FLAG",
    ["!bayrakyenile"] = "REBIND_MISSING_FLAG",
    ["!karsisaldiri"] = "START_COUNTER_ATTACK",
    ["!savas"] = "DECLARE_WAR",
    ["!ateskes"] = "CEASEFIRE",
    ["!ateskesboz"] = "BREAK_CEASEFIRE",
    ["!baris"] = "PEACE",

    ["!ittifak"] = "ALLIANCE",
    ["!kabul"] = "ACCEPT",
    ["!reddet"] = "REJECT",
    ["!iptal"] = "CANCEL",
    ["!tarafsiz"] = "NEUTRALIZE"
}

function Parser.parse(message)
    local words = Text.split_words(message)

    if #words == 0 then
        return Result.err("EMPTY", "Bos mesaj")
    end

    local action = aliases[Text.lower_ascii(words[1])]

    if not action then
        return Result.err(
            "NOT_COMMAND",
            "PalTR komutu degil"
        )
    end

    return Result.ok({
        action = action,
        target = Text.join_from(words, 2),
        raw = Text.clean(message)
    })
end

return Parser
