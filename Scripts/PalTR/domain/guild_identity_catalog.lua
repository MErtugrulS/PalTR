local Catalog = {}

Catalog.PALETTE_VERSION = 1

Catalog.COLORS = {
    { id = "azure", hex = "#2F80ED" },
    { id = "cyan", hex = "#19B8C9" },
    { id = "teal", hex = "#13A68A" },
    { id = "green", hex = "#39A852" },
    { id = "lime", hex = "#8BBF32" },
    { id = "gold", hex = "#E0B341" },
    { id = "amber", hex = "#E59A24" },
    { id = "orange", hex = "#D8672B" },
    { id = "red", hex = "#D94A4A" },
    { id = "crimson", hex = "#B9345A" },
    { id = "magenta", hex = "#C04DA5" },
    { id = "purple", hex = "#844FD1" },
    { id = "violet", hex = "#6255D9" },
    { id = "steel", hex = "#6C8DA6" },
    { id = "ivory", hex = "#D3C6A1" },
    { id = "rose", hex = "#D96B86" }
}

Catalog.EMBLEMS = {
    { id = "wolf", name = "Kurt" },
    { id = "eagle", name = "Kartal" },
    { id = "stag", name = "Geyik" },
    { id = "lion", name = "Aslan" },
    { id = "raven", name = "Kuzgun" },
    { id = "serpent", name = "Yilan" },
    { id = "bear", name = "Ayi" },
    { id = "boar", name = "Yaban Domuzu" },
    { id = "dragon", name = "Ejder" },
    { id = "sun", name = "Gunes" },
    { id = "moon", name = "Ay" },
    { id = "tower", name = "Kule" }
}

local function index(values)
    local result = {}
    for _, value in ipairs(values) do result[value.id] = value end
    return result
end

Catalog.COLOR_BY_ID = index(Catalog.COLORS)
Catalog.EMBLEM_BY_ID = index(Catalog.EMBLEMS)

return Catalog
