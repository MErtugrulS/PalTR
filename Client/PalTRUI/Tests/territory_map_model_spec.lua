local Model = require("territory_map_model")

local function equal(actual, expected, label)
    if actual ~= expected then
        error(string.format(
            "%s | expected=%s actual=%s",
            label,
            tostring(expected),
            tostring(actual)
        ))
    end
end

local model = Model.build({
    player = { guild_key = "own" },
    guild = {
        key = "own", name = "NWO", color_id = "azure",
        emblem_id = "wolf"
    },
    guilds = {
        { key = "ally", name = "Dost", color_id = "teal", emblem_id = "eagle" },
        { key = "enemy", name = "Rakip", color_id = "red", emblem_id = "dragon" }
    },
    guild_identity = {
        colors = {
            { id = "azure", hex = "#2F80ED" },
            { id = "teal", hex = "#13A68A" },
            { id = "red", hex = "#D94A4A" }
        }
    },
    relations = {
        { guild_key = "ally", state = "ALLIANCE" },
        { guild_key = "enemy", state = "WAR" }
    },
    territories = {
        boundaries = {
            {
                boundary_id = "own::001", controller_guild = "own",
                controller_name = "NWO",
                points = {
                    { x = 0, y = 0 }, { x = 8, y = 0 },
                    { x = 8, y = 8 }, { x = 0, y = 8 }
                }
            },
            {
                boundary_id = "enemy::001", controller_guild = "enemy",
                points = {
                    { x = 5, y = 6 }, { x = 7, y = 6 }, { x = 7, y = 8 }
                }
            }
        },
        nodes = {
            {
                node_id = "CAP", node_type = "CAPITAL", display_name = "NWO Baskenti",
                controller_guild = "own", x = 4, y = 4, z = 1
            },
            {
                node_id = "OUT", node_type = "OUTPOST",
                controller_guild = "enemy", x = 30, y = 40, z = 2
            }
        }
    }
})

equal(model.segment_count, 7, "closed polygons produce all segments")
equal(model.segments[1].status, "OWN", "own border color status")
equal(model.segments[5].status, "WAR", "enemy relation stays metadata")
equal(model.segments[1].first.x, 0, "meters convert to world centimeters")
equal(math.floor(model.segments[1].color.b * 255 + 0.5), 237,
    "border uses chosen guild color")
equal(model.boundaries[1].fill_color.a, 0.14, "fill opacity is fixed")
equal(model.node_count, 2, "node markers built")
equal(model.nodes[1].status, "OWN", "capital relation metadata")
equal(model.nodes[1].size, 20, "capital marker is prominent")
equal(model.nodes[2].size, 14, "outpost marker is compact")
equal(model.banner_count, 1, "one center banner for guild with a capital")
equal(model.banners[1].guild_name, "NWO", "banner uses guild name")
equal(model.banners[1].emblem_label, "KURT", "banner uses selected emblem")
equal(model.banners[1].region_text, "1 Bolge (1 Baskent, 0 Karakol)",
    "banner uses real node counts")
equal(Model.point_in_polygon({ x = model.banners[1].world.x / 100,
    y = model.banners[1].world.y / 100 }, model.boundaries[1].source_points),
    true, "banner center remains inside polygon")

local limited = Model.build({
    player = { guild_key = "own" }, relations = {},
    territories = {
        nodes = {},
        boundaries = {
            {
                boundary_id = "own::001", controller_guild = "own",
                points = {
                    { x = 0, y = 0 }, { x = 1, y = 0 },
                    { x = 1, y = 1 }, { x = 0, y = 1 }
                }
            }
        }
    }
}, { max_segments = 3 })
equal(limited.segment_count, 3, "segment pool limit is enforced")
equal(limited.segments[1].second, limited.segments[2].first,
    "simplified boundary remains contiguous")
equal(limited.segments[3].second, limited.segments[1].first,
    "simplified boundary remains closed")

local spans = Model.scanline_spans({
    { x = 0, y = 0 }, { x = 100, y = 0 },
    { x = 100, y = 100 }, { x = 0, y = 100 }
}, { spacing = 4, max_spans = 12 })
equal(#spans <= 12, true, "fill pool limit is enforced")
for _, span in ipairs(spans) do
    equal(span.x >= 0 and span.x + span.width <= 100, true,
        "fill span stays inside polygon")
end

local normalized_spans = Model.scanline_spans({
    { x = 0.10, y = 0.10 }, { x = 0.30, y = 0.10 },
    { x = 0.30, y = 0.30 }, { x = 0.10, y = 0.30 }
}, { spacing = 0.003, normalized = true, max_spans = 96 })
equal(#normalized_spans > 0 and #normalized_spans <= 96, true,
    "normalized fill produces a bounded anchor-space scan pool")
for _, span in ipairs(normalized_spans) do
    equal(span.x >= 0.10 and span.x + span.width <= 0.30, true,
        "normalized fill span stays inside polygon")
end

local unknown = Model.build({
    player = { guild_key = "own" }, guild = { key = "own", name = "NWO" },
    territories = { boundaries = {}, nodes = {
        { node_id = "CAP", node_type = "CAPITAL", controller_guild = "own",
            controller_name = "NWO", x = 0, y = 0, z = 0 }
    } }
})
equal(unknown.nodes[1].color.r, Model.NEUTRAL_COLOR.r,
    "unknown identity safely defaults to neutral")

print("PALTR_UI_TERRITORY_MAP_MODEL_TEST_OK")
