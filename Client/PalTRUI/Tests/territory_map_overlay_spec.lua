local Overlay = require("territory_map_overlay")

local function near(actual, expected, label)
    if math.abs(actual - expected) > 0.001 then
        error(string.format(
            "%s | expected=%s actual=%s",
            label,
            tostring(expected),
            tostring(actual)
        ))
    end
end

local horizontal = Overlay.segment_layout(
    { x = 10, y = 20 },
    { x = 110, y = 20 },
    4
)
near(horizontal.x, 10, "horizontal left")
near(horizontal.y, 18, "horizontal top")
near(horizontal.width, 100, "horizontal width")
near(horizontal.angle, 0, "horizontal angle")

local vertical = Overlay.segment_layout(
    { x = 50, y = 25 },
    { x = 50, y = 125 },
    3
)
near(vertical.width, 100, "vertical width")
near(vertical.angle, 90, "vertical angle")
near(Overlay.BORDER_THICKNESS, 3.2, "strategy border stays restrained")
near(Overlay.Z_ORDER, 10000, "map overlay stays above Palworld map layers")

local anchored = Overlay.segment_layout(
    { x = 0.2, y = 0.4, normalized = true },
    { x = 0.4, y = 0.6, normalized = true },
    3
)
if anchored.normalized ~= true then
    error("normalized segment uses anchor fallback")
end
near(anchored.anchor_x, 0.3, "normalized segment anchor x")
near(anchored.anchor_y, 0.5, "normalized segment anchor y")
near(anchored.width, 0.8, "normalized boundary marker width")
near(Overlay.NORMALIZED_CAPITAL_SIZE, 2.4, "normalized capital stays compact")
near(Overlay.NORMALIZED_OUTPOST_SIZE, 1.4, "normalized outpost stays compact")
local capital_label_layout = Overlay.node_label_layout(
    { node_type = "CAPITAL" },
    1,
    { x = 0.5, y = 0.5, normalized = true },
    { x = 0.5, y = 0.5, normalized = true }
)
near(capital_label_layout.x, 0, "capital label stays centered")
near(capital_label_layout.y, -3.6, "capital label stays above marker")
near(capital_label_layout.width, 108, "label uses high-resolution layout width")
near(capital_label_layout.height, 19.2, "label uses high-resolution layout height")
near(capital_label_layout.render_scale, 1 / 6, "label counter-scales map zoom")
local outpost_label_layout = Overlay.node_label_layout(
    { node_type = "OUTPOST" },
    2,
    { x = 0.7, y = 0.5, normalized = true },
    { x = 0.5, y = 0.5, normalized = true }
)
near(outpost_label_layout.x, 11, "outpost label fans out from cluster")
near(outpost_label_layout.y, 0, "horizontal outpost label keeps y")
if Overlay.node_label_text({
    display_name = "NWO Başkenti", node_type = "CAPITAL"
}) ~= "NWO Başkenti" then
    error("snapshot display name is preserved")
end
if Overlay.node_label_text({
    controller_name = "Exceed", node_type = "OUTPOST"
}) ~= "Exceed Karakolu" then
    error("missing display name gets a useful fallback")
end

local projected_input = nil
local projected_minimum = nil
local projected_maximum = nil
local projected_relative = nil

local function object(fields)
    fields = fields or {}
    function fields:IsValid() return true end
    function fields:GetFullName() return fields.name or "test" end
    return fields
end

local function widget_object(fields)
    fields = object(fields)
    local children = fields.children or {}
    function fields:GetFName()
        return { ToString = function() return fields.widget_name or "" end }
    end
    function fields:GetClass()
        return {
            GetFName = function()
                return {
                    ToString = function() return fields.class_name or "" end
                }
            end
        }
    end
    function fields:GetChildrenCount() return #children end
    function fields:GetChildAt(index) return children[index + 1] end
    return fields
end

local projection_target = object({
    name = "BP_PalUIFunctionLibrary_C TestDefault",
    WorldLocationToWidgetOffset = function(
        _, minimum, maximum, location, relative, output
    )
        projected_input = location
        projected_minimum = minimum
        projected_maximum = maximum
        projected_relative = relative
        output.X = location.X / 10000
        output.Y = location.Y / 10000
    end
})
local projection_overlay = Overlay.new({
    log = function() end,
    find_projection_target = function() return projection_target end,
    get_local_size = function() return { x = 1000, y = 1000 } end
})
local projection_image = object({ name = "Image_MapBody TestImage" })
projection_overlay.parent_canvas = object({ name = "Canvas MapCanvas" })
projection_overlay.map_body = object({
    MinLandScapePosition = { X = -100000, Y = -200000 },
    MaxLandScapePosition = { X = 300000, Y = 400000 },
    Image_MapBody = projection_image
})
local projected = projection_overlay:_world_to_widget({
    x = 1200, y = 3400, z = 500
})
near(projected.x, 120, "normalized projection x uses canvas width")
near(projected.y, 340, "normalized projection y uses canvas height")
near(projected_input.X, 1200, "centimeter x is not scaled twice")
near(projected_input.Y, 3400, "centimeter y is not scaled twice")
near(projected_minimum.X, -100000, "landscape minimum is forwarded")
near(projected_maximum.Y, 400000, "landscape maximum is forwarded")
if projection_overlay.map_body.MinLandscapePositionXY ~= nil
    or projection_overlay.map_body.MapProperty ~= nil then
    error("projection test must use WBP_Map_Body persistent bounds")
end
if projected_relative ~= projection_image then
    error("map image is used as the relative projection widget")
end
if projection_overlay.projection_strategy.name ~= "map_image_cm" then
    error("verified five-parameter map projection strategy selected")
end

local anchor_projection_overlay = Overlay.new({
    log = function() end,
    find_projection_target = function() return projection_target end,
    get_local_size = function() return nil end
})
anchor_projection_overlay.parent_canvas = object({ name = "Canvas Anchored" })
anchor_projection_overlay.map_body = projection_overlay.map_body
local anchor_projected = anchor_projection_overlay:_world_to_widget({
    x = 1200, y = 3400, z = 500
})
if anchor_projected.normalized ~= true then
    error("missing map size preserves normalized anchor coordinates")
end
near(anchor_projected.x, 0.12, "anchor projection x")
near(anchor_projected.y, 0.34, "anchor projection y")

local function canvas_slot_probe()
    local state = {}
    local slot = object({})
    function slot:SetAnchors(value) state.anchors = value end
    function slot:SetAlignment(value) state.alignment = value end
    function slot:SetPosition(value) state.position = value end
    function slot:SetSize(value) state.size = value end
    function slot:SetZOrder(value) state.z_order = value end
    local control = object({ Slot = slot })
    function control:SetRenderTransformPivot() end
    function control:SetRenderTransformAngle() end
    function control:SetRenderScale(value) state.render_scale = value end
    function control:SetBrushColor(value) state.color = value end
    function control:SetVisibility(value) state.visibility = value end
    return control, state
end

local segment_control, segment_slot = canvas_slot_probe()
local segment_inner_color = nil
local segment_inner = object({
    SetBrushColor = function(_, value) segment_inner_color = value end
})
local node_control, node_slot = canvas_slot_probe()
local node_label, node_label_slot = canvas_slot_probe()
local node_label_value = nil
local node_label_text = object({
    SetText = function(_, value) node_label_value = value end
})
local anchor_render_overlay = Overlay.new({
    log = function() end,
    make_text = function(value) return "FText:" .. value end
})
anchor_render_overlay.controls = {
    TerritorySegment001 = segment_control,
    TerritorySegmentInner001 = segment_inner,
    TerritoryNode001 = node_control,
    TerritoryNodeLabel001 = node_label,
    TerritoryNodeLabelText001 = node_label_text
}
anchor_render_overlay.model = {
    segments = {
        {
            first = { id = "first" },
            second = { id = "second" },
            color = { r = 0.7, g = 0.5, b = 0.2, a = 1 }
        }
    },
    nodes = {
        {
            world = { id = "node" },
            color = {},
            size = 18,
            angle = 45,
            node_type = "CAPITAL",
            display_name = "NWO Başkenti"
        }
    },
    segment_count = 1,
    node_count = 1
}
anchor_render_overlay._project_cached = function(_, world)
    if world.id == "first" then
        return { x = 0.2, y = 0.4, normalized = true }
    end
    if world.id == "second" then
        return { x = 0.4, y = 0.6, normalized = true }
    end
    return { x = 0.7, y = 0.8, normalized = true }
end
local anchored_segments, anchored_segment_stats =
    anchor_render_overlay:_render_segments()
local anchored_nodes, anchored_node_stats = anchor_render_overlay:_render_nodes()
near(anchored_segments, 1, "normalized segment renders")
near(anchored_segment_stats.slots, 1, "normalized segment configures slot")
near(segment_slot.anchors.Minimum.X, 0.3, "segment slot anchor x")
near(segment_slot.anchors.Minimum.Y, 0.5, "segment slot anchor y")
near(segment_slot.color.R, 0.7, "normalized boundary uses clan color")
near(segment_inner_color.G, 0.5, "normalized boundary inner keeps clan color")
near(anchored_nodes, 1, "normalized node renders")
near(anchored_node_stats.slots, 1, "normalized node configures slot")
near(node_slot.anchors.Minimum.X, 0.7, "node slot anchor x")
near(node_slot.anchors.Minimum.Y, 0.8, "node slot anchor y")
near(node_slot.alignment.X, 0.5, "node anchor centers marker")
near(node_slot.size.X, 2.4, "normalized capital avoids map zoom magnification")
near(node_slot.z_order, 40, "capital stays above overlapping outposts")
near(node_label_slot.anchors.Minimum.X, 0.7, "label shares node anchor x")
near(node_label_slot.position.Y, -3.6, "capital label is offset above marker")
near(node_label_slot.size.X, 108, "label slot preserves font resolution")
near(node_label_slot.render_scale.X, 1 / 6, "label is counter-scaled")
near(node_label_slot.z_order, 41, "capital label stays above marker")
if node_label_value ~= "FText:NWO Başkenti" then
    error("node label receives snapshot display name")
end
near(anchored_node_stats.label_slots, 1, "normalized node label renders")

local cached_projection_calls = 0
projection_overlay.projected_points = {}
projection_overlay._world_to_widget = function(_, world)
    cached_projection_calls = cached_projection_calls + 1
    return { x = world.x, y = world.y }
end
projection_overlay:_project_cached({ x = 10, y = 20, z = 30 })
projection_overlay:_project_cached({ x = 10, y = 20, z = 30 })
near(cached_projection_calls, 1, "shared boundary points are projected once")

local loaded_projection_target = object({
    name = "Default__BP_PalUIFunctionLibrary_C"
})
local projection_class = object({
    GetCDO = function() return loaded_projection_target end
})
local resolver_overlay = Overlay.new({
    find_object = function(path)
        if path == Overlay.PAL_UI_LIBRARY_CLASS_PATH then
            return projection_class
        end
        return nil
    end,
    log = function() end
})
if resolver_overlay:_find_projection_target() ~= loaded_projection_target then
    error("projection uses Pal UI function library default object")
end
resolver_overlay.projection_target = nil
if resolver_overlay:_find_projection_target() ~= nil then
    error("completed projection lookup is not repeated for every segment")
end

local body = object({ name = "WBP_Map_Body_C TestBody" })
local canvas = object({ name = "CanvasPanel TestCanvas" })
local base = object({
    name = "WBP_Map_Base_C TestBase",
    MapBody = body,
    CanvasPanel_MapBody = canvas
})
local base_overlay = Overlay.new({
    find_all = function(class_name)
        return class_name == "WBP_Map_Base_C" and { base } or {}
    end,
    now = function() return 0 end,
    log = function() end
})
local base_found = base_overlay:_discover_map()
near(base_found and 1 or 0, 1, "map base discovery succeeds")
if base_overlay.attachment_strategy ~= "base_canvas" then
    error("map base canvas is preferred")
end

local hidden_base = object({
    name = "WBP_Map_Base_C HiddenBase",
    MapBody = body,
    CanvasPanel_MapBody = canvas,
    rendered = false
})
function hidden_base:IsRendered() return self.rendered end
local visible_base = object({
    name = "WBP_Map_Base_C VisibleBase",
    MapBody = body,
    CanvasPanel_MapBody = canvas,
    rendered = true
})
function visible_base:IsRendered() return self.rendered end
local visible_overlay = Overlay.new({
    find_all = function(class_name)
        if class_name == "WBP_Map_Base_C" then
            return { hidden_base, visible_base }
        end
        return {}
    end,
    log = function() end
})
local visible_found = visible_overlay:_discover_map(true)
near(visible_found and 1 or 0, 1, "visible map discovery succeeds")
if visible_overlay.map_base ~= visible_base then
    error("map discovery prefers the currently rendered instance")
end

local body_canvas = object({ name = "Canvas_MapBody TestCanvas" })
local fallback_body = object({
    name = "WBP_Map_Body_C FallbackBody",
    Canvas_MapBody = body_canvas
})
local body_overlay = Overlay.new({
    find_all = function(class_name)
        return class_name == "WBP_Map_Body_C" and { fallback_body } or {}
    end,
    now = function() return 0 end,
    log = function() end
})
local body_found = body_overlay:_discover_map()
near(body_found and 1 or 0, 1, "map body fallback succeeds")
if body_overlay.attachment_strategy ~= "body_canvas" then
    error("map body canvas fallback selected")
end

local tree_canvas = widget_object({
    name = "CanvasPanel Canvas_MapBody",
    widget_name = "Canvas_MapBody",
    class_name = "CanvasPanel"
})
local tree_image = widget_object({
    name = "Image Image_MapBody",
    widget_name = "Image_MapBody",
    class_name = "Image"
})
local tree_root = widget_object({
    name = "Overlay MapRoot",
    widget_name = "MapRoot",
    class_name = "Overlay",
    children = { tree_image, tree_canvas }
})
local tree_body = widget_object({
    name = "WBP_Map_Body_C TreeBody",
    widget_name = "TreeBody",
    class_name = "WBP_Map_Body_C",
    WidgetTree = object({ RootWidget = tree_root }),
    MinLandScapePosition = { X = -100000, Y = -200000 },
    MaxLandScapePosition = { X = 300000, Y = 400000 }
})
local tree_body_overlay = Overlay.new({
    find_all = function(class_name)
        return class_name == "WBP_Map_Body_C" and { tree_body } or {}
    end,
    log = function() end
})
if not tree_body_overlay:_discover_map()
    or tree_body_overlay.parent_canvas ~= tree_canvas
    or tree_body_overlay.attachment_strategy ~= "body_widget_tree" then
    error("map body canvas is resolved through WidgetTree.RootWidget")
end

local base_root = widget_object({
    name = "Overlay BaseRoot",
    widget_name = "BaseRoot",
    class_name = "Overlay",
    children = { tree_body }
})
local tree_base = widget_object({
    name = "WBP_Map_Base_C TreeBase",
    widget_name = "TreeBase",
    class_name = "WBP_Map_Base_C",
    WidgetTree = object({ RootWidget = base_root })
})
local tree_base_overlay = Overlay.new({
    find_all = function(class_name)
        return class_name == "WBP_Map_Base_C" and { tree_base } or {}
    end,
    log = function() end
})
if not tree_base_overlay:_discover_map()
    or tree_base_overlay.map_body ~= tree_body
    or tree_base_overlay.parent_canvas ~= tree_canvas then
    error("map base resolves nested body and canvas without blueprint fields")
end

projected_relative = nil
local tree_projection_overlay = Overlay.new({
    find_projection_target = function() return projection_target end,
    get_local_size = function() return { x = 1000, y = 1000 } end,
    log = function() end
})
tree_projection_overlay.map_body = tree_body
tree_projection_overlay.parent_canvas = tree_canvas
local tree_projected = tree_projection_overlay:_world_to_widget({
    x = 2200, y = 4400, z = 0
})
near(tree_projected.x, 220, "tree projection x")
near(tree_projected.y, 440, "tree projection y")
if projected_relative ~= tree_image then
    error("projection relative widget is resolved through WidgetTree")
end

local outer_canvas = object({ name = "CanvasPanel_MapBody OuterCanvas" })
local outer_base = object({
    name = "WBP_Map_Base_C OuterBase",
    CanvasPanel_MapBody = outer_canvas
})
local outer_tree = object({
    name = "WidgetTree OuterTree",
    GetOuter = function() return outer_base end
})
local nested_body = object({
    name = "WBP_Map_Body_C NestedBody",
    Canvas_MapBody = body_canvas,
    GetOuter = function() return outer_tree end
})
local outer_overlay = Overlay.new({
    find_all = function(class_name)
        return class_name == "WBP_Map_Body_C" and { nested_body } or {}
    end,
    now = function() return 0 end,
    log = function() end
})
near(outer_overlay:_discover_map() and 1 or 0, 1,
    "nested map body discovers enclosing base")
if outer_overlay.attachment_strategy ~= "outer_base_canvas"
    or outer_overlay.parent_canvas ~= outer_canvas
    or outer_overlay.map_base ~= outer_base then
    error("nested map overlay attaches above the map body")
end

local invalid_class = { IsValid = function() return false end }
local loaded_class = object({ name = "WBP_PalTRMapOverlay_C TestClass" })
local find_calls = 0
local registry_calls = {}
local class_overlay = Overlay.new({
    find_object = function(path)
        if path ~= Overlay.CLASS_PATH then error("unexpected class path") end
        find_calls = find_calls + 1
        return find_calls < 3 and invalid_class or loaded_class
    end,
    load_asset = function(path)
        if path ~= Overlay.ASSET_PATH then error("unexpected asset path") end
    end,
    load_registered_asset = function(package_name, asset_name)
        table.insert(registry_calls, {
            package_name = package_name,
            asset_name = asset_name
        })
        return true
    end,
    log = function() end
})
local resolved_class, class_source = class_overlay:_load_class()
if resolved_class ~= loaded_class then error("registry class is returned") end
if class_source ~= "asset_registry" then error("registry source is reported") end
near(#registry_calls, 1, "asset registry fallback called once")
if registry_calls[1].package_name ~= Overlay.PACKAGE_NAME then
    error("overlay registry package name")
end
if registry_calls[1].asset_name ~= Overlay.ASSET_NAME then
    error("overlay registry generated class name")
end

local snapshot_requests = 0
local request_overlay = Overlay.new({
    request_snapshot = function()
        snapshot_requests = snapshot_requests + 1
        return true
    end,
    log = function() end
})
request_overlay:_request_snapshot(10)
request_overlay:_request_snapshot(12)
near(snapshot_requests, 1, "snapshot request is rate limited")
request_overlay:_request_snapshot(16)
near(snapshot_requests, 2, "missing snapshot is retried")
request_overlay:set_snapshot({ territories = { boundaries = {} } })
request_overlay:_request_snapshot(22)
near(snapshot_requests, 2, "received snapshot stops retries")

local registered_paths = {}
local registered_callbacks = {}
local registered_map_key = nil
local registered_map_key_callback = nil
local overlay = Overlay.new({
    register_hook = function(path, callback)
        registered_paths[path] = true
        registered_callbacks[path] = callback
        return 1, 2
    end,
    register_key_bind = function(key, callback)
        registered_map_key = key
        registered_map_key_callback = callback
    end,
    map_key = "M",
    now = function() return 0 end
})
local registered = overlay:register()
near(registered and 1 or 0, 1, "overlay hook registers")
for _, path in ipairs({
    Overlay.TICK_HOOK,
    Overlay.WIDGET_CONSTRUCT_HOOK,
    Overlay.WIDGET_DESTRUCT_HOOK
}) do
    if registered_paths[path] ~= true then
        error("overlay hook missing: " .. path)
    end
end
if registered_map_key ~= "M"
    or type(registered_map_key_callback) ~= "function" then
    error("overlay registers the map-key discovery signal")
end
registered_map_key_callback()
if overlay.discovery_pending ~= true then
    error("map key queues bounded discovery when no map is cached")
end
if overlay.map_expected_open ~= true then
    error("map key records the explicit open signal")
end
registered_map_key_callback()
if overlay.map_expected_open == true or overlay.discovery_pending == true then
    error("second map key records close and cancels discovery")
end


local event_body = object({
    name = "WBP_Map_Body_C EventBody",
    Canvas_MapBody = body_canvas
})
local event_base = object({
    name = "WBP_Map_Base_C EventBase",
    MapBody = event_body,
    CanvasPanel_MapBody = canvas,
    rendered = false
})
function event_base:IsRendered() return self.rendered end
registered_callbacks[Overlay.WIDGET_CONSTRUCT_HOOK](event_base)
if overlay.known_map_base ~= event_base then
    error("map construct remembers the concrete map widget")
end
if overlay.map_expected_open ~= true then
    error("map construct resynchronizes the explicit open state")
end
local cloud_widget = object({
    name = "WBP_Map_Body_Cloud_1_C DecorativeCloud"
})
registered_callbacks[Overlay.WIDGET_CONSTRUCT_HOOK](cloud_widget)
if overlay.known_map_body ~= nil then
    error("map construct ignores similarly named child widgets")
end
registered_callbacks[Overlay.WIDGET_DESTRUCT_HOOK](event_base)
if overlay.known_map_base ~= nil then
    error("map destruct forgets stale map widgets")
end
if overlay.map_expected_open == true then
    error("map destruct resynchronizes the closed state")
end

local explicit_now = 0
local explicit_attach_calls = 0
local explicit_hidden_base = object({
    name = "WBP_Map_Base_C ExplicitHiddenBase",
    MapBody = event_body,
    CanvasPanel_MapBody = canvas,
    rendered = false
})
function explicit_hidden_base:IsRendered() return self.rendered end
local explicit_overlay = Overlay.new({
    find_all = function(class_name)
        if class_name == "WBP_Map_Base_C" then
            return { explicit_hidden_base }
        end
        return {}
    end,
    now = function() return explicit_now end,
    log = function() end
})
explicit_overlay.initial_discovery_attempted = true
local explicit_visibility = nil
explicit_overlay._create_widget = function(self)
    explicit_attach_calls = explicit_attach_calls + 1
    self.widget = object({
        name = "WBP_PalTRMapOverlay_C ExplicitOpen",
        RemoveFromParent = function() end,
        SetVisibility = function(_, value) explicit_visibility = value end
    })
    return true, "explicit_open"
end
explicit_overlay:set_map_expected_open(true, "test_key")
explicit_now = Overlay.DISCOVERY_INITIAL_DELAY_SECONDS
explicit_overlay:_tick()
near(explicit_attach_calls, 1,
    "explicit map open accepts structurally valid IsRendered=false base")
if explicit_overlay.map_base ~= explicit_hidden_base
    or explicit_overlay.widget == nil then
    error("explicit map open reaches the verified base canvas")
end
explicit_overlay:set_map_expected_open(false, "test_key")
if explicit_overlay.widget == nil or explicit_visibility ~= 1
    or explicit_overlay.discovery_pending == true then
    error("explicit map close caches the widget and stops discovery")
end
local reopened, reopen_result = explicit_overlay:set_map_expected_open(
    true,
    "test_key"
)
if reopened ~= true or reopen_result ~= "cached_widget"
    or explicit_visibility ~= 3 or explicit_attach_calls ~= 1 then
    error("explicit map reopen reuses the cached overlay widget")
end

local scan_calls = 0
local scan_now = 0
local idle_overlay = Overlay.new({
    find_all = function()
        scan_calls = scan_calls + 1
        return {}
    end,
    now = function() return scan_now end,
    log = function() end
})
idle_overlay:_tick()
local initial_scan_calls = scan_calls
scan_now = 1
idle_overlay:_tick()
scan_now = 2
idle_overlay:_tick()
near(scan_calls, initial_scan_calls, "idle map discovery is attempted only once")

local retry_now = 0
local retry_overlay = Overlay.new({
    now = function() return retry_now end,
    log = function() end
})
retry_overlay.map_body = object({ name = "WBP_Map_Body_C RetryBody" })
retry_overlay.parent_canvas = canvas
retry_overlay.widget = object({ name = "WBP_PalTRMapOverlay_C Retry" })
retry_overlay.snapshot = {}
retry_overlay.model = {
    segments = { { first = {}, second = {} } },
    nodes = {},
    segment_count = 1,
    node_count = 0
}
retry_overlay.map_expected_open = true
retry_overlay._map_is_rendered = function() return true end
retry_overlay._render_segments = function()
    return 0, { controls = 1, inners = 1, projected = 1, slots = 0 }
end
retry_overlay._render_nodes = function()
    return 0, { controls = 0, projected = 0, slots = 0 }
end
retry_overlay:_tick()
if retry_overlay.render_dirty ~= true or retry_overlay.render_attempts ~= 1 then
    error("zero-length first render schedules a bounded geometry retry")
end
retry_now = 0.25
retry_overlay:_tick()
near(retry_overlay.render_attempts, 1,
    "geometry retry respects its interval")
retry_now = 0.5
retry_overlay:_tick()
near(retry_overlay.render_attempts, 2,
    "geometry retry runs after layout settles")

local discovery_now = 0
local discovery_calls = 0
local discovery_overlay = Overlay.new({
    now = function() return discovery_now end,
    log = function() end
})
discovery_overlay.initial_discovery_attempted = true
discovery_overlay._discover_map = function(self)
    discovery_calls = discovery_calls + 1
    if discovery_calls < 2 then return false, "not_ready" end
    self.map_base = event_base
    self.map_body = event_body
    self.parent_canvas = canvas
    self.attachment_strategy = "base_canvas"
    return true, "eventual"
end
discovery_overlay._create_widget = function(self)
    self.widget = object({ name = "WBP_PalTRMapOverlay_C Discovered" })
    return true, "created"
end
discovery_overlay:request_discovery("test")
discovery_overlay:_tick()
near(discovery_calls, 0, "map-key discovery waits for map construction")
discovery_now = Overlay.DISCOVERY_INITIAL_DELAY_SECONDS
discovery_overlay:_tick()
near(discovery_calls, 1, "map-key discovery begins after initial delay")
discovery_now = discovery_overlay.next_discovery_at
discovery_overlay:_tick()
near(discovery_calls, 2, "map-key discovery retries only while opening")
discovery_now = discovery_now + 4
discovery_overlay:_tick()
near(discovery_calls, 2, "cached map stops discovery scans")

local capped_now = 0
local capped_calls = 0
local capped_times = {}
local capped_overlay = Overlay.new({
    now = function() return capped_now end,
    log = function() end
})
capped_overlay.initial_discovery_attempted = true
capped_overlay._discover_map = function()
    capped_calls = capped_calls + 1
    table.insert(capped_times, capped_now)
    return false, "missing"
end
capped_overlay:request_discovery("test")
for _ = 1, Overlay.DISCOVERY_MAX_ATTEMPTS do
    capped_now = capped_overlay.next_discovery_at
    capped_overlay:_tick()
end
near(capped_calls, Overlay.DISCOVERY_MAX_ATTEMPTS,
    "map-key discovery attempts are capped")
near(capped_times[1], Overlay.DISCOVERY_INITIAL_DELAY_SECONDS,
    "map discovery avoids the keypress race")
near(capped_times[2] - capped_times[1], 0.5,
    "first discovery retry stays responsive")
near(capped_times[3] - capped_times[2], 1.0,
    "discovery retry backs off")
near(capped_times[#capped_times], 7.9,
    "sparse discovery window covers slow map construction")
if capped_overlay.discovery_pending == true then
    error("capped discovery does not keep scanning while idle")
end


local stale_overlay = Overlay.new({ log = function() end })
stale_overlay.known_map_base = hidden_base
local stale_queued, stale_result = stale_overlay:request_discovery("test")
if stale_queued ~= true or stale_result ~= "queued"
    or stale_overlay.discovery_pending ~= true then
    error("hidden cached map queues a fresh bounded discovery")
end
if stale_overlay.known_map_base ~= nil then
    error("hidden cached map is discarded before discovery")
end

local visible_cached_body = object({
    name = "WBP_Map_Body_C VisibleCachedBody",
    Canvas_MapBody = body_canvas,
    rendered = true
})
function visible_cached_body:IsRendered() return self.rendered end
local mixed_cache_overlay = Overlay.new({ log = function() end })
mixed_cache_overlay.known_map_base = hidden_base
mixed_cache_overlay.known_map_body = visible_cached_body
mixed_cache_overlay.map_base = hidden_base
mixed_cache_overlay.map_body = body
mixed_cache_overlay.parent_canvas = canvas
local mixed_cached, mixed_result = mixed_cache_overlay:request_discovery("test")
if mixed_cached ~= true or mixed_result ~= "cached" then
    error("rendered cached body avoids an unnecessary discovery scan")
end
if mixed_cache_overlay.map_base ~= nil
    or mixed_cache_overlay.map_body ~= visible_cached_body then
    error("rendered cache replaces stale active map references")
end

local render_now = 0
local render_calls = 0
local render_base = object({
    name = "WBP_Map_Base_C RenderBase",
    MapBody = event_body,
    CanvasPanel_MapBody = canvas,
    rendered = true
})
function render_base:IsRendered() return self.rendered end
local render_overlay = Overlay.new({
    now = function() return render_now end,
    log = function() end
})
render_overlay.snapshot = { territories = { boundaries = {} } }
render_overlay.known_map_base = render_base
render_overlay.map_base = render_base
render_overlay.map_body = event_body
render_overlay.parent_canvas = canvas
render_overlay.widget = object({ name = "WBP_PalTRMapOverlay_C Runtime" })
render_overlay.map_expected_open = true
render_overlay._render_segments = function()
    render_calls = render_calls + 1
    return 0, { controls = 0, inners = 0, projected = 0, slots = 0 }
end
render_overlay._render_nodes = function()
    return 0, { controls = 0, projected = 0, slots = 0 }
end
render_overlay:_tick()
render_now = 1
render_overlay:_tick()
near(render_calls, 1, "unchanged visible map is not redrawn")
render_overlay:set_snapshot({ territories = { boundaries = {} } })
render_now = 2
render_overlay:_tick()
near(render_calls, 2, "snapshot change redraws the map once")
render_now = 3
render_overlay:set_map_expected_open(false, "test")
render_overlay:_tick()
if render_overlay.widget == nil then
    error("closed map retains the runtime overlay for reuse")
end
if render_overlay.known_map_base ~= render_base then
    error("hidden map keeps the cached map reference for reopening")
end

local retry_now = 0
local attach_calls = 0
render_base.rendered = true
local retry_overlay = Overlay.new({
    now = function() return retry_now end,
    log = function() end
})
retry_overlay.known_map_base = render_base
retry_overlay.map_base = render_base
retry_overlay.map_body = event_body
retry_overlay.parent_canvas = canvas
retry_overlay.map_expected_open = true
retry_overlay._create_widget = function(self)
    attach_calls = attach_calls + 1
    if attach_calls == 1 then return false, "temporary" end
    self.widget = object({ name = "WBP_PalTRMapOverlay_C Retried" })
    return true, "retried"
end
retry_overlay:_tick()
retry_now = 0.5
retry_overlay:_tick()
near(attach_calls, 1, "temporary attach failure observes retry delay")
retry_now = 1
retry_overlay:_tick()
near(attach_calls, 2, "temporary attach failure is retried once")
if retry_overlay.widget == nil then
    error("delayed attach retry recovers while map remains visible")
end

print("PALTR_UI_TERRITORY_MAP_OVERLAY_TEST_OK")
