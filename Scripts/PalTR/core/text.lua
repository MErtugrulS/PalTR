local Text = {}

function Text.clean(value)
    local text = tostring(value or "")
    text = text:gsub("[\r\n\t|]", " ")
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    if #text > 1500 then text = text:sub(1, 1500) .. "<kesildi>" end
    return text
end

function Text.lower_ascii(value)
    return string.lower(Text.clean(value))
end

function Text.starts_with(value, prefix)
    value = tostring(value or "")
    prefix = tostring(prefix or "")
    return value:sub(1, #prefix) == prefix
end

function Text.split_words(value)
    local words = {}
    for word in Text.clean(value):gmatch("%S+") do
        table.insert(words, word)
    end
    return words
end

function Text.join_from(words, start_index)
    local parts = {}
    for index = start_index, #words do
        table.insert(parts, words[index])
    end
    return table.concat(parts, " ")
end

return Text
