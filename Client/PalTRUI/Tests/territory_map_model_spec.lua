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
    relations = {
        { guild_key = "ally", state = "ALLIANCE" },
        { guild_key = "enemy", state = "WAR" }
    },
    territories = {
        boundaries = {
            {
                boundary_id = "own::001", controller_guild = "own",
                points = {
                    { x = 1, y = 2 }, { x = 3, y = 2 }, { x = 3, y = 4 }
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
                node_id = "CAP", node_type = "CAPITAL",
                controller_guild = "ally", x = 10, y = 20, z = 1
            },
            {
                node_id = "OUT", node_type = "OUTPOST",
                controller_guild = "enemy", x = 30, y = 40, z = 2
            }
        }
    }
})

equal(model.segment_count, 6, "closed polygons produce all segments")
equal(model.segments[1].status, "OWN", "own border color status")
equal(model.segments[4].status, "WAR", "enemy border color status")
equal(model.segments[1].first.x, 100, "meters convert to world centimeters")
equal(model.node_count, 2, "node markers built")
equal(model.nodes[1].status, "ALLIANCE", "allied capital status")
equal(model.nodes[1].size, 18, "capital marker is prominent")
equal(model.nodes[2].size, 11, "outpost marker is compact")

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
}, { max_segments = 2 })
equal(limited.segment_count, 2, "segment pool limit is enforced")

print("PALTR_UI_TERRITORY_MAP_MODEL_TEST_OK")
