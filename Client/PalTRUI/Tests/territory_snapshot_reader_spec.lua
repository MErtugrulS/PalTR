local Reader = require("PalTR.services.territory_snapshot_reader")

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

local stamp = tostring(os.time()) .. "-" .. tostring(math.random(100000, 999999))
local node_path = "territory-reader-nodes-" .. stamp .. ".tsv"
local boundary_path = "territory-reader-boundaries-" .. stamp .. ".tsv"

local node_file = assert(io.open(node_path, "w"))
node_file:write(
    "header\n",
    "CAP\tAnka Baskenti\tCAPITAL\town\tAnka\t-100.5\t200.25\t3\t250\tPROTECTED\tBOUND\n"
)
node_file:close()

local boundary_file = assert(io.open(boundary_path, "w"))
boundary_file:write(
    "header\n",
    "own::001\town\tAnka\t1\t-200\t100\t0\t300\t3\t-200.125,100.5;0,100.5;0,300.75\n"
)
boundary_file:close()

local snapshot = Reader.read({
    territory_snapshot = node_path,
    territory_boundaries = boundary_path
})
equal(#snapshot.nodes, 1, "territory node decoded")
equal(snapshot.nodes[1].node_type, "CAPITAL", "node type decoded")
equal(#snapshot.boundaries, 1, "territory boundary decoded")
equal(snapshot.boundaries[1].points[3].y, 300.75,
    "boundary point decoded")

os.remove(node_path)
os.remove(boundary_path)

print("PALTR_UI_TERRITORY_SNAPSHOT_READER_TEST_OK")
