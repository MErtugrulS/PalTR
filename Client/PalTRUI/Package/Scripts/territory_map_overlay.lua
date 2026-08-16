local TerritoryMapModel = require("territory_map_model")

local Overlay = {}
Overlay.__index = Overlay

Overlay.TICK_HOOK = "/Script/Pal.PalHUDInGame:TickWorldHUDs"
Overlay.WIDGET_CONSTRUCT_HOOK = "/Script/UMG.UserWidget:Construct"
Overlay.WIDGET_DESTRUCT_HOOK = "/Script/UMG.UserWidget:Destruct"
Overlay.ASSET_PATH =
    "/Game/Mods/PalTRUI/WBP_PalTRMapOverlay.WBP_PalTRMapOverlay"
Overlay.CLASS_PATH =
    "/Game/Mods/PalTRUI/WBP_PalTRMapOverlay.WBP_PalTRMapOverlay_C"
Overlay.PACKAGE_NAME = "/Game/Mods/PalTRUI/WBP_PalTRMapOverlay"
Overlay.ASSET_NAME = "WBP_PalTRMapOverlay_C"
Overlay.ASSET_REGISTRY_HELPERS_PATH =
    "/Script/AssetRegistry.Default__AssetRegistryHelpers"
Overlay.WIDGET_LIBRARY_PATH = "/Script/UMG.Default__WidgetBlueprintLibrary"
Overlay.SLATE_LIBRARY_PATH = "/Script/UMG.Default__SlateBlueprintLibrary"
Overlay.PAL_UI_LIBRARY_ASSET_PATH =
    "/Game/Pal/Blueprint/UI/System/BP_PalUIFunctionLibrary.BP_PalUIFunctionLibrary"
Overlay.PAL_UI_LIBRARY_CLASS_PATH =
    "/Game/Pal/Blueprint/UI/System/BP_PalUIFunctionLibrary.BP_PalUIFunctionLibrary_C"
Overlay.PAL_UI_LIBRARY_DEFAULT_PATH =
    "/Game/Pal/Blueprint/UI/System/BP_PalUIFunctionLibrary.Default__BP_PalUIFunctionLibrary_C"
Overlay.MAP_BASE_CLASSES = { "WBP_Map_Base_C", "WBP_Map_Base" }
Overlay.MAP_BODY_CLASSES = { "WBP_Map_Body_C", "WBP_Map_Body" }
-- Keep the packaged widget tree bounded. The model simplifies safely at these
-- limits and avoids constructing nearly two thousand UMG controls when the map
-- is opened.
Overlay.MAX_SEGMENTS = 128
Overlay.MAX_FILLS = 96
Overlay.MAX_NODES = 32
Overlay.MAX_BANNERS = 8
Overlay.Z_ORDER = 10000
Overlay.BORDER_THICKNESS = 1.8
Overlay.NORMALIZED_SEGMENT_SIZE = 0.45
Overlay.NORMALIZED_CAPITAL_SIZE = 2.4
Overlay.NORMALIZED_OUTPOST_SIZE = 1.4
Overlay.CAPITAL_Z_ORDER = 40
Overlay.OUTPOST_Z_ORDER = 30
Overlay.FILL_Z_ORDER = 10
Overlay.BANNER_Z_ORDER = 40
Overlay.RENDER_BATCH_SIZE = 64
Overlay.NORMALIZED_BANNER_WIDTH = 28
Overlay.NORMALIZED_BANNER_HEIGHT = 13
Overlay.NORMALIZED_BANNER_RENDER_SCALE = 1 / 6
Overlay.NORMALIZED_LABEL_WIDTH = 18.0
Overlay.NORMALIZED_LABEL_HEIGHT = 3.2
Overlay.NORMALIZED_LABEL_GAP = 2.0
Overlay.NORMALIZED_LABEL_RENDER_SCALE = 1 / 6
Overlay.VISIBILITY_CHECK_INTERVAL_SECONDS = 0.20
Overlay.ATTACH_RETRY_INTERVAL_SECONDS = 1.0
Overlay.ATTACH_MAX_ATTEMPTS = 3
Overlay.DISCOVERY_INITIAL_DELAY_SECONDS = 0.4
Overlay.DISCOVERY_RETRY_INTERVAL_SECONDS = 0.5
Overlay.DISCOVERY_MAX_RETRY_INTERVAL_SECONDS = 2.0
Overlay.DISCOVERY_MAX_ATTEMPTS = 6
Overlay.SNAPSHOT_REQUEST_INTERVAL_SECONDS = 5.0
Overlay.RENDER_RETRY_INTERVAL_SECONDS = 0.5
Overlay.INITIAL_RENDER_DELAY_SECONDS = 0.25
-- One layout retry is enough after the map widget settles. Repeating a failed
-- projection six times only stalls the map without creating any geometry.
Overlay.RENDER_MAX_ATTEMPTS = 2
Overlay.NORMALIZED_RENDER_MAX_ATTEMPTS = 2
-- MainWorld5 values from Palworld's WorldMapUIData. They are only used when
-- the live WBP_Map_Body_MW5 instance does not expose its copied bounds to
-- UE4SS. Other map bodies must provide their own runtime bounds.
Overlay.MAIN_WORLD_BOUNDS = {
    minimum = { x = -1099400, y = -724400 },
    maximum = { x = 349400, y = 724400 }
}

PalTRTerritoryMapOverlayCallbacks = PalTRTerritoryMapOverlayCallbacks or {}

local function unwrap(value)
    if value == nil then return nil end
    local ok, result = pcall(function() return value:get() end)
    if ok and result ~= nil then return result end
    return value
end

local function valid_object(value)
    value = unwrap(value)
    if value == nil then return false end
    local checked, valid = pcall(function() return value:IsValid() end)
    if checked then return valid == true end
    return true
end

local function rendered_object(value)
    value = unwrap(value)
    if not valid_object(value) then return false end
    local checked, rendered = pcall(function() return value:IsRendered() end)
    if checked then return rendered == true end
    local visible_checked, visible = pcall(function()
        return value:IsVisible()
    end)
    if visible_checked then return visible == true end
    return true
end

local function full_name(value)
    value = unwrap(value)
    if value == nil then return "" end
    local ok, result = pcall(function() return value:GetFullName() end)
    return ok and tostring(result or "") or ""
end

local function widget_name(widget)
    widget = unwrap(widget)
    if widget == nil then return "" end
    local named, name = pcall(function()
        return widget:GetFName():ToString()
    end)
    return named and tostring(name or "") or ""
end

local function map_widget_kind(widget)
    widget = unwrap(widget)
    local class_name = ""
    pcall(function()
        class_name = tostring(widget:GetClass():GetFName():ToString() or "")
    end)
    if class_name == "" then
        class_name = full_name(widget):match("^([^%s]+)") or ""
    end
    if class_name == "WBP_Map_Base_C" or class_name == "WBP_Map_Base" then
        return "base"
    end
    if class_name == "WBP_Map_Body_C" or class_name == "WBP_Map_Body" then
        return "body"
    end
    return nil
end

local function same_object(first, second)
    first, second = unwrap(first), unwrap(second)
    if first == nil or second == nil then return false end
    if first == second then return true end
    local first_name, second_name = full_name(first), full_name(second)
    return first_name ~= "" and first_name == second_name
end

local property

local function collect_widgets(widget, controls, depth, visited)
    widget = unwrap(widget)
    if widget == nil or depth > 64 then return end
    visited = visited or {}
    if visited[widget] then return end
    visited[widget] = true
    local name = widget_name(widget)
    if name ~= "" then controls[name] = widget end
    local tree = property and property(widget, "WidgetTree") or nil
    local root = valid_object(tree) and property(tree, "RootWidget") or nil
    if valid_object(root) and not same_object(root, widget) then
        collect_widgets(root, controls, depth + 1, visited)
    end
    local counted, count = pcall(function()
        return widget:GetChildrenCount()
    end)
    if not counted or type(count) ~= "number" then return end
    for index = 0, count - 1 do
        local found, child = pcall(function()
            return widget:GetChildAt(index)
        end)
        if found then collect_widgets(child, controls, depth + 1, visited) end
    end
end

property = function(object, name)
    object = unwrap(object)
    if object == nil then return nil end
    local direct, value = pcall(function() return object[name] end)
    if direct and value ~= nil then return unwrap(value) end
    local read, result = pcall(function()
        return object:GetPropertyValue(name)
    end)
    return read and unwrap(result) or nil
end

local function find_widget(widget, predicate)
    local found = nil
    local visited = {}
    local function visit(candidate, depth)
        candidate = unwrap(candidate)
        if found ~= nil or not valid_object(candidate) or depth > 64
            or visited[candidate] then
            return
        end
        visited[candidate] = true
        if predicate(candidate) then
            found = candidate
            return
        end
        local tree = property(candidate, "WidgetTree")
        local root = valid_object(tree) and property(tree, "RootWidget") or nil
        if valid_object(root) and not same_object(root, candidate) then
            visit(root, depth + 1)
        end
        if found ~= nil then return end
        local counted, count = pcall(function()
            return candidate:GetChildrenCount()
        end)
        if not counted or type(count) ~= "number" then return end
        for index = 0, count - 1 do
            local read, child = pcall(function()
                return candidate:GetChildAt(index)
            end)
            if read then visit(child, depth + 1) end
            if found ~= nil then return end
        end
    end
    visit(widget, 0)
    return found
end

local function canvas_from_widget_tree(widget)
    local function is_canvas(candidate)
        local class_name = ""
        pcall(function()
            class_name = tostring(
                candidate:GetClass():GetFName():ToString() or ""
            )
        end)
        return class_name == "CanvasPanel"
            or class_name == "CanvasPanel_C"
    end
    local named = find_widget(widget, function(candidate)
        if not is_canvas(candidate) then return false end
        local name = widget_name(candidate)
        return name == "Canvas_MapBody" or name == "CanvasPanel_MapBody"
    end)
    return named or find_widget(widget, is_canvas)
end

local function map_body_from_widget_tree(widget)
    return find_widget(widget, function(candidate)
        return map_widget_kind(candidate) == "body"
    end)
end

local function body_canvas(body, outer_base)
    if valid_object(outer_base) then
        local outer_property = property(outer_base, "CanvasPanel_MapBody")
        if valid_object(outer_property) then
            return outer_property, "outer_base_canvas"
        end
    end
    local body_property = property(body, "Canvas_MapBody")
    if valid_object(body_property) then
        return body_property, "body_canvas"
    end
    local body_tree = canvas_from_widget_tree(body)
    if valid_object(body_tree) then
        return body_tree, "body_widget_tree"
    end
    if valid_object(outer_base) then
        local outer_tree = canvas_from_widget_tree(outer_base)
        if valid_object(outer_tree) then
            return outer_tree, "outer_widget_tree"
        end
    end
    return nil, nil
end

local function vector(value)
    value = unwrap(value)
    if value == nil then return nil end
    local read, x, y = pcall(function()
        return tonumber(value.X or value.x), tonumber(value.Y or value.y)
    end)
    if read and x ~= nil and y ~= nil then return { x = x, y = y } end
    return nil
end

function Overlay.segment_layout(first, second, thickness)
    if type(first) ~= "table" or type(second) ~= "table" then return nil end
    local first_x, first_y = tonumber(first.x), tonumber(first.y)
    local second_x, second_y = tonumber(second.x), tonumber(second.y)
    if first_x == nil or first_y == nil or second_x == nil or second_y == nil then
        return nil
    end
    if first.normalized == true and second.normalized == true then
        return {
            normalized = true,
            anchor_x = (first_x + second_x) / 2,
            anchor_y = (first_y + second_y) / 2,
            x = 0,
            y = 0,
            width = Overlay.NORMALIZED_SEGMENT_SIZE,
            height = Overlay.NORMALIZED_SEGMENT_SIZE,
            angle = 0
        }
    end
    local dx, dy = second_x - first_x, second_y - first_y
    local length = math.sqrt(dx * dx + dy * dy)
    if length < 0.5 then return nil end
    thickness = math.max(1, tonumber(thickness) or 3)
    return {
        x = (first_x + second_x - length) / 2,
        y = (first_y + second_y - thickness) / 2,
        width = length,
        height = thickness,
        angle = math.deg(math.atan(dy, dx))
    }
end

local function control_name(prefix, index)
    return string.format("%s%03d", prefix, index)
end

local function hide(control)
    if not valid_object(control) then return end
    pcall(function() control:SetVisibility(1) end)
end

local function show(control)
    if not valid_object(control) then return end
    pcall(function() control:SetVisibility(3) end)
end

local function show_interactive(control)
    if not valid_object(control) then return end
    pcall(function() control:SetVisibility(0) end)
end

local function is_hovered(control)
    if not valid_object(control) then return false end
    local ok, hovered = pcall(function() return control:IsHovered() end)
    return ok and hovered == true
end

local function set_color(control, color)
    color = type(color) == "table" and color
        or TerritoryMapModel.COLORS.NEUTRAL
    pcall(function()
        control:SetBrushColor({
            R = color.r, G = color.g, B = color.b, A = color.a
        })
    end)
end

local function set_segment_colors(outline, inner, color)
    set_color(outline, { r = 0.025, g = 0.055, b = 0.075, a = 0.92 })
    set_color(inner, color)
end

local function set_text(control, value, make_text)
    if not valid_object(control) or type(make_text) ~= "function" then
        return false
    end
    local made, unreal_text = pcall(make_text, tostring(value or ""))
    if not made or unreal_text == nil then return false end
    return pcall(function() control:SetText(unreal_text) end)
end

local function configure_canvas_slot(control, layout)
    local slot = property(control, "Slot")
    if not valid_object(slot) then return false end
    local updated = pcall(function()
        if layout.normalized == true then
            slot:SetAnchors({
                Minimum = { X = layout.anchor_x, Y = layout.anchor_y },
                Maximum = { X = layout.anchor_x, Y = layout.anchor_y }
            })
            slot:SetAlignment({
                X = tonumber(layout.alignment_x) or 0.5,
                Y = tonumber(layout.alignment_y) or 0.5
            })
        else
            slot:SetAnchors({
                Minimum = { X = 0, Y = 0 },
                Maximum = { X = 0, Y = 0 }
            })
            slot:SetAlignment({ X = 0, Y = 0 })
        end
        slot:SetPosition({ X = layout.x, Y = layout.y })
        slot:SetSize({ X = layout.width, Y = layout.height })
        if layout.z_order ~= nil then
            slot:SetZOrder(layout.z_order)
        end
        control:SetRenderTransformPivot({ X = 0.5, Y = 0.5 })
        control:SetRenderTransformAngle(layout.angle)
        if layout.render_scale ~= nil then
            control:SetRenderScale({
                X = layout.render_scale,
                Y = layout.render_scale
            })
        end
    end)
    return updated
end

function Overlay.node_label_text(node)
    node = type(node) == "table" and node or {}
    local display_name = tostring(node.display_name or "")
    if display_name ~= "" then return display_name end
    local owner = tostring(node.controller_name or "")
    if owner == "" then owner = "Klan" end
    if tostring(node.node_type or "") == "CAPITAL" then
        return owner .. " Başkenti"
    end
    return owner .. " Karakolu"
end

function Overlay.node_label_layout(node, index, position, centroid)
    if type(position) ~= "table" then return nil end
    node = type(node) == "table" and node or {}
    centroid = type(centroid) == "table" and centroid or position
    local normalized = position.normalized == true
    local width = normalized and Overlay.NORMALIZED_LABEL_WIDTH or 144
    local height = normalized and Overlay.NORMALIZED_LABEL_HEIGHT or 24
    local gap = normalized and Overlay.NORMALIZED_LABEL_GAP or 10
    local render_scale = normalized
        and Overlay.NORMALIZED_LABEL_RENDER_SCALE or 1
    local offset_x, offset_y = 0, 0
    if tostring(node.node_type or "") == "CAPITAL" then
        offset_y = -(height / 2 + gap)
    else
        local dx = (tonumber(position.x) or 0) - (tonumber(centroid.x) or 0)
        local dy = (tonumber(position.y) or 0) - (tonumber(centroid.y) or 0)
        if math.abs(dx) < 0.000001 and math.abs(dy) < 0.000001 then
            local directions = {
                { 1, 0 }, { 0, 1 }, { -1, 0 }, { 0, -1 }
            }
            local direction = directions[((tonumber(index) or 1) - 1) % 4 + 1]
            dx, dy = direction[1], direction[2]
        end
        if math.abs(dx) >= math.abs(dy) then
            offset_x = (dx >= 0 and 1 or -1) * (width / 2 + gap)
        else
            offset_y = (dy >= 0 and 1 or -1) * (height / 2 + gap)
        end
    end
    return {
        normalized = normalized,
        anchor_x = position.x,
        anchor_y = position.y,
        alignment_x = normalized and 0.5 or 0,
        alignment_y = normalized and 0.5 or 0,
        x = normalized and offset_x
            or position.x + offset_x - width / 2,
        y = normalized and offset_y
            or position.y + offset_y - height / 2,
        width = width / render_scale,
        height = height / render_scale,
        angle = 0,
        render_scale = render_scale,
        z_order = tostring(node.node_type or "") == "CAPITAL" and 41 or 31
    }
end

local function default_make_text(value)
    if type(FText) == "function" then
        local created, unreal_text = pcall(FText, value)
        if created then return unreal_text end
    end
    local loaded, UEHelpers = pcall(require, "UEHelpers")
    if not loaded then return nil end
    local found, library = pcall(UEHelpers.GetKismetTextLibrary)
    if not found or not valid_object(library) then return nil end
    local converted, unreal_text = pcall(function()
        return library:Conv_StringToText(value)
    end)
    return converted and unreal_text or nil
end

local function default_load_registered_asset(package_name, asset_name)
    if type(StaticFindObject) ~= "function" then
        return false, "StaticFindObject unavailable"
    end
    local loaded, result = pcall(function()
        local UEHelpers = require("UEHelpers")
        local registry_helpers = StaticFindObject(
            Overlay.ASSET_REGISTRY_HELPERS_PATH
        )
        if not valid_object(registry_helpers) then
            error("AssetRegistryHelpers unavailable")
        end
        local asset = registry_helpers:GetAsset({
            PackageName = UEHelpers.FindOrAddFName(package_name),
            AssetName = UEHelpers.FindOrAddFName(asset_name)
        })
        return valid_object(asset)
    end)
    if not loaded then return false, tostring(result) end
    if result ~= true then return false, "invalid registry asset" end
    return true
end

local function call_vector(callback)
    local results = table.pack(pcall(callback))
    if results[1] ~= true then return nil end
    for index = 2, results.n do
        local converted = vector(results[index])
        if converted ~= nil then return converted end
    end
    return nil
end

local function default_get_local_size(widget)
    widget = unwrap(widget)
    if not valid_object(widget) or type(StaticFindObject) ~= "function" then
        return nil
    end
    local geometry_ok, geometry = pcall(function()
        return widget:GetCachedGeometry()
    end)
    local library_ok, library = pcall(
        StaticFindObject,
        Overlay.SLATE_LIBRARY_PATH
    )
    if geometry_ok and library_ok and valid_object(library) then
        local size = call_vector(function()
            return library:GetLocalSize(geometry)
        end)
        if size ~= nil then return size end
    end
    if geometry_ok then
        local direct = vector(property(geometry, "LocalSize"))
            or vector(property(geometry, "Size"))
        if direct ~= nil then return direct end
    end
    local desired = call_vector(function()
        return widget:GetDesiredSize()
    end)
    if desired ~= nil then return desired end
    local slot = property(widget, "Slot")
    if valid_object(slot) then
        return call_vector(function() return slot:GetSize() end)
    end
    return nil
end

local function default_api()
    return {
        register_hook = type(RegisterHook) == "function" and RegisterHook or nil,
        register_key_bind = type(RegisterKeyBind) == "function"
            and RegisterKeyBind or nil,
        map_key = Key ~= nil and Key.M or nil,
        find_all = type(FindAllOf) == "function" and FindAllOf or nil,
        find_object = type(StaticFindObject) == "function" and StaticFindObject or nil,
        load_asset = type(LoadAsset) == "function" and LoadAsset or nil,
        load_registered_asset = default_load_registered_asset,
        get_local_size = default_get_local_size,
        make_text = default_make_text,
        now = os.clock,
        log = function(message)
            if type(print) == "function" then
                print("[PalTRUI] " .. tostring(message) .. "\n")
            end
        end
    }
end

function Overlay.new(api)
    local resolved_api = default_api()
    if type(api) == "table" then
        for key, value in pairs(api) do resolved_api[key] = value end
    end
    return setmetatable({
        api = resolved_api,
        registered = false,
        known_map_base = nil,
        known_map_body = nil,
        initial_discovery_attempted = false,
        discovery_pending = false,
        discovery_attempts = 0,
        next_discovery_at = nil,
        map_expected_open = false,
        map_was_rendered = false,
        attach_attempts = 0,
        next_attach_at = nil,
        map_base = nil,
        map_body = nil,
        parent_canvas = nil,
        attachment_strategy = nil,
        widget = nil,
        controls = {},
        snapshot = nil,
        model = TerritoryMapModel.build({}),
        node_hover = {},
        render_dirty = true,
        visible_segment_count = 0,
        visible_fill_count = 0,
        visible_node_count = 0,
        visible_banner_count = 0,
        render_attempts = 0,
        next_render_at = nil,
        last_visibility_check_at = nil,
        last_snapshot_request_at = nil,
        projection_strategy = nil,
        projection_target = nil,
        projection_lookup_attempted = false,
        projection_size = nil,
        projected_points = {},
        diagnostics = {}
    }, Overlay)
end

function Overlay:_map_local_size()
    if self.projection_size ~= nil then return self.projection_size end
    if type(self.api.get_local_size) ~= "function"
        or not valid_object(self.parent_canvas) then
        return nil
    end
    local image = property(self.map_body, "Image_MapBody")
    if not valid_object(image) then
        image = find_widget(self.map_body, function(candidate)
            return widget_name(candidate) == "Image_MapBody"
        end)
    end
    local candidates = {}
    if valid_object(image) then table.insert(candidates, image) end
    if valid_object(self.parent_canvas) then
        table.insert(candidates, self.parent_canvas)
    end
    if valid_object(self.map_body) then table.insert(candidates, self.map_body) end
    for _, candidate in ipairs(candidates) do
        if valid_object(candidate) then
            local read, size = pcall(self.api.get_local_size, candidate)
            size = read and vector(size) or nil
            if size ~= nil and size.x > 1 and size.y > 1 then
                self.projection_size = size
                self:_diagnostic("projection_size", string.format(
                    "PALTR_MAP_OVERLAY_LOCAL_SIZE | width=%.2f | height=%.2f"
                        .. " | source=%s",
                    size.x,
                    size.y,
                    widget_name(candidate)
                ))
                return size
            end
        end
    end
    return nil
end

function Overlay:_projection_to_pixels(offset)
    offset = vector(offset)
    if offset == nil then return nil, "invalid normalized offset" end
    local size = self:_map_local_size()
    if size == nil then
        return {
            x = offset.x,
            y = offset.y,
            normalized = true
        }
    end
    return {
        x = offset.x * size.x,
        y = offset.y * size.y
    }
end

local function projection_location(world, scale)
    scale = tonumber(scale) or 1
    return {
        X = (tonumber(world and world.x) or 0) * scale,
        Y = (tonumber(world and world.y) or 0) * scale,
        Z = (tonumber(world and world.z) or 0) * scale
    }
end

local function projection_context(map_body, relative_name)
    -- WBP_Map_Body:Setup copies MapProperty.landScapeRealPositionMin/Max
    -- into these two persistent widget properties. The MapProperty members
    -- are Blueprint temporaries and are not readable from the live widget.
    local minimum = property(map_body, "MinLandScapePosition")
    local maximum = property(map_body, "MaxLandScapePosition")
    if vector(minimum) == nil or vector(maximum) == nil then
        return nil, "landscape bounds unavailable"
    end
    local relative = relative_name == nil
        and map_body or property(map_body, relative_name)
    if not valid_object(relative) and relative_name ~= nil then
        relative = find_widget(map_body, function(candidate)
            return widget_name(candidate) == relative_name
        end)
    end
    if not valid_object(relative) then
        return nil, "relative widget unavailable: "
            .. tostring(relative_name or "map_body")
    end
    return {
        minimum = minimum,
        maximum = maximum,
        relative = relative
    }
end

local function project_with_context(
    projection_target,
    map_body,
    world,
    relative_name,
    scale
)
    local context, context_error = projection_context(map_body, relative_name)
    if context == nil then return nil, context_error end
    local output = { X = 0, Y = 0 }
    local results = { pcall(function()
        return projection_target:WorldLocationToWidgetOffset(
            context.minimum,
            context.maximum,
            projection_location(world, scale),
            context.relative,
            output
        )
    end) }
    if results[1] ~= true then
        local detail = tostring(results[2] or "projection call failed")
        detail = detail:match("^[^\r\n]+") or "projection call failed"
        return nil, detail
    end
    local converted = vector(output)
    if converted ~= nil then return converted end
    for index = 2, #results do
        converted = vector(results[index])
        if converted ~= nil then return converted end
    end
    return nil, "empty offset"
end

local PROJECTION_STRATEGIES = {}
for _, specification in ipairs({
    { name = "map_image_cm", relative = "Image_MapBody", scale = 1 },
    { name = "map_canvas_cm", relative = "Canvas_MapBody", scale = 1 },
    { name = "map_body_cm", relative = nil, scale = 1 },
    {
        name = "map_image_meters_fallback",
        relative = "Image_MapBody",
        scale = 0.01
    }
}) do
    local captured = specification
    table.insert(PROJECTION_STRATEGIES, {
        name = captured.name,
        project = function(projection_target, map_body, world)
            return project_with_context(
                projection_target,
                map_body,
                world,
                captured.relative,
                captured.scale
            )
        end
    })
end

function Overlay:_find_projection_target()
    if self.projection_target ~= nil then return self.projection_target end
    if self.projection_lookup_attempted then return nil end
    self.projection_lookup_attempted = true

    if type(self.api.find_projection_target) == "function" then
        local found, target = pcall(self.api.find_projection_target)
        if found and target ~= nil then
            self.projection_target = target
            return target
        end
    end

    local class = nil
    if type(self.api.find_object) == "function" then
        pcall(function()
            class = self.api.find_object(Overlay.PAL_UI_LIBRARY_CLASS_PATH)
        end)
        if not valid_object(class) and type(self.api.load_asset) == "function" then
            pcall(self.api.load_asset, Overlay.PAL_UI_LIBRARY_ASSET_PATH)
            pcall(function()
                class = self.api.find_object(Overlay.PAL_UI_LIBRARY_CLASS_PATH)
            end)
        end
        if valid_object(class) then
            local got_default, target = pcall(function()
                return class:GetCDO()
            end)
            if got_default and valid_object(target) then
                self.projection_target = target
                self:_diagnostic(
                    "projection_target",
                    "PALTR_MAP_OVERLAY_PROJECTION_TARGET | source=class_default"
                        .. " | " .. full_name(target)
                )
                return target
            end
        end

        local found_default, target = pcall(
            self.api.find_object,
            Overlay.PAL_UI_LIBRARY_DEFAULT_PATH
        )
        if found_default and valid_object(target) then
            self.projection_target = target
            self:_diagnostic(
                "projection_target",
                "PALTR_MAP_OVERLAY_PROJECTION_TARGET | source=default_path"
                    .. " | " .. full_name(target)
            )
            return target
        end
    end

    self:_diagnostic(
        "projection_target",
        "PALTR_MAP_OVERLAY_PROJECTION_TARGET_FAILED"
    )
    return nil
end

local function main_world_bounds(map_body)
    local identity = widget_name(map_body) .. " " .. full_name(map_body)
    if identity:find("WBP_Map_Body_MW5", 1, true) == nil then return nil end
    return Overlay.MAIN_WORLD_BOUNDS.minimum,
        Overlay.MAIN_WORLD_BOUNDS.maximum
end

local function project_from_landscape_bounds(map_body, world)
    local minimum = vector(property(map_body, "MinLandScapePosition"))
    local maximum = vector(property(map_body, "MaxLandScapePosition"))
    local source = "widget"
    if minimum == nil or maximum == nil then
        minimum, maximum = main_world_bounds(map_body)
        source = "main_world_data"
    end
    if minimum == nil or maximum == nil then
        return nil, "landscape bounds unavailable"
    end
    local span_x = maximum.x - minimum.x
    local span_y = maximum.y - minimum.y
    if math.abs(span_x) < 1 or math.abs(span_y) < 1 then
        return nil, "invalid landscape bounds"
    end
    -- Palworld's world map rotates the UE world axes: world Y is the map's
    -- horizontal axis and world X runs bottom-to-top on the map texture.
    -- Returning anchors keeps the overlay inside the same zoom/pan transform
    -- as Canvas_MapBody without depending on a Blueprint function-library CDO.
    return {
        x = ((tonumber(world and world.y) or 0) - minimum.y) / span_y,
        y = 1 - (((tonumber(world and world.x) or 0) - minimum.x) / span_x),
        normalized = true
    }, nil, source
end

function Overlay:_reset_projection_lookup()
    self.projection_strategy = nil
    self.projection_target = nil
    self.projection_lookup_attempted = false
    self.projection_size = nil
    self.projected_points = {}
end

function Overlay:_world_to_widget(world)
    if not valid_object(self.map_body) then
        self:_restore_known_map()
    end
    if not valid_object(self.map_body) then
        self:_diagnostic(
            "projection",
            "PALTR_MAP_OVERLAY_PROJECTION_FAILED | stale_map_body"
        )
        return nil
    end
    local bounds_error = nil
    if self.api.disable_bounds_fallback ~= true then
        local direct, direct_error, bounds_source = project_from_landscape_bounds(
            self.map_body,
            world
        )
        if direct ~= nil then
            local size = self:_map_local_size()
            if size ~= nil then
                direct = {
                    x = direct.x * size.x,
                    y = direct.y * size.y
                }
            end
            self:_diagnostic(
                "projection",
                "PALTR_MAP_OVERLAY_PROJECTION | strategy="
                    .. (size ~= nil
                        and "landscape_bounds_pixels"
                        or "landscape_bounds_anchor")
                    .. " | source=" .. tostring(bounds_source or "")
            )
            return direct
        end
        bounds_error = direct_error
    end
    local projection_target = self:_find_projection_target()
    if projection_target == nil then
        self:_diagnostic(
            "projection",
            "PALTR_MAP_OVERLAY_PROJECTION_FAILED | bounds_direct:"
                .. tostring(bounds_error or "disabled")
                .. " | projection_target:unavailable"
        )
        return nil
    end
    if self.projection_strategy ~= nil then
        local converted = self.projection_strategy.project(
            projection_target,
            self.map_body,
            world
        )
        if converted ~= nil then
            local pixels = self:_projection_to_pixels(converted)
            if pixels ~= nil then return pixels end
        end
        self.projection_strategy = nil
    end

    local errors = {}
    for _, strategy in ipairs(PROJECTION_STRATEGIES) do
        local converted, project_error = strategy.project(
            projection_target,
            self.map_body,
            world
        )
        if converted ~= nil then
            local pixels, scale_error = self:_projection_to_pixels(converted)
            if pixels ~= nil then
                self.projection_strategy = strategy
                self:_diagnostic(
                    "projection",
                    "PALTR_MAP_OVERLAY_PROJECTION | strategy=" .. strategy.name
                )
                return pixels
            end
            project_error = scale_error
        end
        table.insert(errors, strategy.name .. ":" .. tostring(project_error or ""))
    end
    if bounds_error ~= nil then
        table.insert(errors, "bounds_direct:" .. tostring(bounds_error))
    end
    self:_diagnostic(
        "projection",
        "PALTR_MAP_OVERLAY_PROJECTION_FAILED | " .. table.concat(errors, " | ")
    )
    return nil
end

function Overlay:_project_cached(world)
    world = type(world) == "table" and world or {}
    local key = string.format(
        "%.3f|%.3f|%.3f",
        tonumber(world.x) or 0,
        tonumber(world.y) or 0,
        tonumber(world.z) or 0
    )
    local cached = self.projected_points[key]
    if cached ~= nil then return cached ~= false and cached or nil end
    local projected = self:_world_to_widget(world)
    self.projected_points[key] = projected or false
    return projected
end

function Overlay:_control(name)
    local control = self.controls[tostring(name or "")]
    if valid_object(control) then return control end
    control = property(self.widget, name)
    if valid_object(control) then
        self.controls[name] = control
        return control
    end
    return nil
end

function Overlay:_diagnostic(key, message)
    key = tostring(key or "")
    message = tostring(message or "")
    if self.diagnostics[key] == message then return end
    self.diagnostics[key] = message
    if type(self.api.log) == "function" then
        pcall(self.api.log, message)
    end
end

function Overlay:set_snapshot(snapshot)
    self.snapshot = type(snapshot) == "table" and snapshot or nil
    self.model = TerritoryMapModel.build(self.snapshot or {}, {
        max_segments = Overlay.MAX_SEGMENTS,
        max_nodes = Overlay.MAX_NODES,
        max_banners = Overlay.MAX_BANNERS
    })
    self.render_dirty = true
    self.render_attempts = 0
    self.next_render_at = nil
    self.projection_size = nil
    self.projected_points = {}
    self:_diagnostic("model", string.format(
        "PALTR_MAP_OVERLAY_MODEL | boundaries=%d | segments=%d | nodes=%d"
            .. " | banners=%d",
        #(self.snapshot and self.snapshot.territories
            and self.snapshot.territories.boundaries or {}),
        tonumber(self.model.segment_count) or 0,
        tonumber(self.model.node_count) or 0,
        tonumber(self.model.banner_count) or 0
    ))
end

function Overlay:_request_snapshot(now)
    if self.snapshot ~= nil
        or type(self.api.request_snapshot) ~= "function" then
        return false
    end
    now = tonumber(now) or 0
    if self.last_snapshot_request_at ~= nil
        and now - self.last_snapshot_request_at
            < Overlay.SNAPSHOT_REQUEST_INTERVAL_SECONDS then
        return false
    end
    self.last_snapshot_request_at = now
    local called, requested, request_error = pcall(
        self.api.request_snapshot
    )
    local ok = called == true and requested == true
    local detail = ok and "" or (called and request_error or requested)
    self:_diagnostic("snapshot_request", string.format(
        "PALTR_MAP_OVERLAY_SNAPSHOT_REQUEST_%s | error=%s",
        ok and "OK" or "FAILED",
        tostring(detail or "")
    ))
    return ok
end

function Overlay:_load_class()
    if type(self.api.find_object) ~= "function" then return nil end
    local found, class = pcall(self.api.find_object, Overlay.CLASS_PATH)
    if found and valid_object(class) then return class, "already_loaded" end
    if type(self.api.load_asset) == "function" then
        pcall(self.api.load_asset, Overlay.ASSET_PATH)
        found, class = pcall(self.api.find_object, Overlay.CLASS_PATH)
        if found and valid_object(class) then return class, "load_asset" end
    end
    if type(self.api.load_registered_asset) == "function" then
        local registered, registry_error = self.api.load_registered_asset(
            Overlay.PACKAGE_NAME,
            Overlay.ASSET_NAME
        )
        found, class = pcall(self.api.find_object, Overlay.CLASS_PATH)
        if found and valid_object(class) then return class, "asset_registry" end
        self:_diagnostic("class_load", string.format(
            "PALTR_MAP_OVERLAY_CLASS_LOAD_FAILED | registry=%s | error=%s",
            tostring(registered == true),
            tostring(registry_error or "")
        ))
    end
    return nil
end

local function find_instances(api, class_names)
    local result = {}
    if type(api.find_all) ~= "function" then return result end
    for _, class_name in ipairs(class_names) do
        local found, values = pcall(api.find_all, class_name)
        if found and values ~= nil then
            for _, value in ipairs(values) do
                table.insert(result, unwrap(value))
            end
        end
    end
    return result
end

local function enclosing_map_base(body)
    local current = unwrap(body)
    for _ = 1, 16 do
        local read, outer = pcall(function()
            return current:GetOuter()
        end)
        outer = read and unwrap(outer) or nil
        if not valid_object(outer) then return nil end
        if map_widget_kind(outer) == "base" then return outer end
        current = outer
    end
    return nil
end

function Overlay:_discover_map(require_rendered)
    if type(self.api.find_all) ~= "function" then return false end
    local bases = find_instances(self.api, Overlay.MAP_BASE_CLASSES)
    local base_visible = nil
    local base_fallback = nil
    for _, candidate in ipairs(bases) do
        local body = property(candidate, "MapBody")
        if not valid_object(body) then
            body = map_body_from_widget_tree(candidate)
        end
        local parent, strategy = body_canvas(body, candidate)
        if strategy == "outer_base_canvas" then strategy = "base_canvas" end
        if valid_object(candidate) and valid_object(body)
            and valid_object(parent) then
            local context = { candidate, body, parent, strategy }
            if rendered_object(candidate) then
                base_visible = context
                break
            end
            if base_fallback == nil and require_rendered ~= true then
                base_fallback = context
            end
        end
    end

    local bodies = find_instances(self.api, Overlay.MAP_BODY_CLASSES)
    local body_visible = nil
    local body_fallback = nil
    for _, body in ipairs(bodies) do
        local outer_base = enclosing_map_base(body)
        local parent, strategy = body_canvas(body, outer_base)
        if valid_object(body) and valid_object(parent) then
            local context = { body, parent, outer_base, strategy }
            if rendered_object(body) then
                body_visible = context
                break
            end
            if body_fallback == nil and require_rendered ~= true then
                body_fallback = context
            end
        end
    end
    local selected_base = base_visible
    if selected_base == nil and body_visible == nil then
        selected_base = base_fallback
    end
    if selected_base ~= nil then
        self.map_base = selected_base[1]
        self.map_body = selected_base[2]
        self.parent_canvas = selected_base[3]
        self.attachment_strategy = selected_base[4] or "base_canvas"
        return true, string.format(
            "base_canvas | base=%s | body=%s",
            full_name(self.map_base),
            full_name(self.map_body)
        )
    end
    local selected_body = body_visible or body_fallback
    if selected_body ~= nil then
        self.map_base = selected_body[3]
        self.map_body = selected_body[1]
        self.parent_canvas = selected_body[2]
        self.attachment_strategy = selected_body[4]
            or (valid_object(self.map_base)
                and "outer_base_canvas" or "body_canvas")
        return true, string.format(
            "%s | body=%s",
            self.attachment_strategy,
            full_name(self.map_body)
        )
    end
    return false, string.format(
        "base_candidates=%d | body_candidates=%d",
        #bases,
        #bodies
    )
end

function Overlay:_remember_map_widget(widget)
    widget = unwrap(widget)
    local kind = map_widget_kind(widget)
    if kind == "base" then
        self.known_map_base = widget
    elseif kind == "body" then
        self.known_map_body = widget
    else
        return false
    end
    self.discovery_pending = false
    self.discovery_attempts = 0
    self.next_discovery_at = nil
    self.last_visibility_check_at = nil
    return true
end

function Overlay:_remember_current_map()
    if valid_object(self.map_base) then
        self.known_map_base = self.map_base
    end
    if valid_object(self.map_body) then
        self.known_map_body = self.map_body
    end
end

function Overlay:request_discovery(source)
    self.map_expected_open = true
    self.last_visibility_check_at = nil
    if valid_object(self.widget) and self:_restore_known_map() then
        show(self.widget)
        self.map_was_rendered = true
        self.render_dirty = true
        self.render_attempts = 0
        self.next_render_at = nil
        self.projection_size = nil
        self.projected_points = {}
        return true, "cached_widget"
    end
    if self:_restore_known_map() and self:_map_is_rendered(true) then
        return true, "cached"
    end
    if valid_object(self.widget) then self:_clear_runtime(false) end
    self.known_map_base = nil
    self.known_map_body = nil
    self.map_base = nil
    self.map_body = nil
    self.parent_canvas = nil
    self.attachment_strategy = nil
    self.initial_discovery_attempted = true
    self.discovery_pending = true
    self.discovery_attempts = 0
    local now = tonumber(self.api.now and self.api.now() or os.clock()) or 0
    self.next_discovery_at = now + Overlay.DISCOVERY_INITIAL_DELAY_SECONDS
    self:_diagnostic(
        "discovery_request",
        "PALTR_MAP_OVERLAY_DISCOVERY_REQUESTED | source="
            .. tostring(source or "runtime")
    )
    return true, "queued"
end

function Overlay:set_map_expected_open(expected_open, source)
    expected_open = expected_open == true
    self.map_expected_open = expected_open
    self.last_visibility_check_at = nil
    if expected_open then
        return self:request_discovery(source or "map_open")
    end

    self.discovery_pending = false
    self.discovery_attempts = 0
    self.next_discovery_at = nil
    self.map_was_rendered = false
    self.attach_attempts = 0
    self.next_attach_at = nil
    if valid_object(self.widget) then
        self:_diagnostic(
            "runtime",
            "PALTR_MAP_OVERLAY_HIDDEN | reason=map_key_closed"
        )
        hide(self.widget)
    end
    return true, "closed"
end

function Overlay:toggle_map_expected_open(source)
    return self:set_map_expected_open(
        self.map_expected_open ~= true,
        source or "map_key"
    )
end

function Overlay:_attempt_discovery(now)
    local initial = self.initial_discovery_attempted ~= true
    if not initial and self.discovery_pending ~= true then return false end
    if not initial and self.next_discovery_at ~= nil
        and now < self.next_discovery_at then
        return false
    end

    if initial then
        self.initial_discovery_attempted = true
    else
        self.discovery_attempts = self.discovery_attempts + 1
    end

    local discovered, discovery_detail = self:_discover_map(
        self.map_expected_open ~= true and not initial
    )
    if discovered then
        self.discovery_pending = false
        self.discovery_attempts = 0
        self.next_discovery_at = nil
        self:_remember_current_map()
        self:_diagnostic(
            "discovery",
            "PALTR_MAP_OVERLAY_MAP_FOUND | " .. tostring(discovery_detail)
        )
        return true
    end

    if not initial then
        if self.discovery_attempts >= Overlay.DISCOVERY_MAX_ATTEMPTS then
            self.discovery_pending = false
            self.next_discovery_at = nil
            self:_diagnostic(
                "discovery",
                "PALTR_MAP_OVERLAY_DISCOVERY_EXHAUSTED | "
                    .. tostring(discovery_detail)
            )
        else
            local multiplier = 2 ^ math.max(0, self.discovery_attempts - 1)
            local delay = math.min(
                Overlay.DISCOVERY_MAX_RETRY_INTERVAL_SECONDS,
                Overlay.DISCOVERY_RETRY_INTERVAL_SECONDS * multiplier
            )
            self.next_discovery_at = now + delay
        end
    end
    return false
end

function Overlay:_restore_known_map()
    local base = self.known_map_base
    local base_context = nil
    if valid_object(base) then
        local body = property(base, "MapBody")
        if not valid_object(body) then
            body = map_body_from_widget_tree(base)
        end
        local parent, strategy = body_canvas(body, base)
        if strategy == "outer_base_canvas" then strategy = "base_canvas" end
        if valid_object(body) and valid_object(parent) then
            base_context = { base, body, parent, strategy }
        end
    end

    local body = self.known_map_body
    local body_context = nil
    if valid_object(body) then
        local outer_base = enclosing_map_base(body)
        local parent, strategy = body_canvas(body, outer_base)
        if valid_object(parent) then
            body_context = { body, parent, outer_base, strategy }
        end
    end

    if base_context ~= nil and rendered_object(base_context[1]) then
        self.map_base = base_context[1]
        self.map_body = base_context[2]
        self.known_map_body = base_context[2]
        self.parent_canvas = base_context[3]
        self.attachment_strategy = base_context[4] or "base_canvas"
        return true
    end
    if body_context ~= nil and rendered_object(body_context[1]) then
        self.map_base = body_context[3]
        self.map_body = body_context[1]
        self.parent_canvas = body_context[2]
        self.attachment_strategy = body_context[4]
            or (valid_object(self.map_base)
                and "outer_base_canvas" or "body_canvas")
        return true
    end
    if base_context ~= nil then
        self.map_base = base_context[1]
        self.map_body = base_context[2]
        self.known_map_body = base_context[2]
        self.parent_canvas = base_context[3]
        self.attachment_strategy = base_context[4] or "base_canvas"
        return true
    end
    if body_context ~= nil then
        self.map_base = body_context[3]
        self.map_body = body_context[1]
        self.parent_canvas = body_context[2]
        self.attachment_strategy = body_context[4]
            or (valid_object(self.map_base)
                and "outer_base_canvas" or "body_canvas")
        return true
    end
    return false
end

function Overlay:_map_is_rendered(physical_only)
    if physical_only ~= true and self.map_expected_open == true then
        return valid_object(self.map_body)
            and valid_object(self.parent_canvas)
    end
    if valid_object(self.map_base) then
        return rendered_object(self.map_base)
    end
    return rendered_object(self.map_body)
end

function Overlay:_create_widget()
    local context = valid_object(self.map_base) and self.map_base or self.map_body
    if not valid_object(context) or not valid_object(self.parent_canvas) then
        return false, "map_context"
    end
    local class, class_source = self:_load_class()
    if not valid_object(class) or type(self.api.find_object) ~= "function" then
        return false, "overlay_class"
    end
    self:_diagnostic(
        "class_load",
        "PALTR_MAP_OVERLAY_CLASS_LOADED | source=" .. tostring(class_source)
    )
    local library_found, library = pcall(
        self.api.find_object,
        Overlay.WIDGET_LIBRARY_PATH
    )
    if not library_found or not valid_object(library) then
        return false, "widget_library"
    end

    local owner = nil
    pcall(function() owner = context:GetOwningPlayer() end)
    local created, widget = pcall(function()
        return library:Create(context, class, owner)
    end)
    if not created or not valid_object(widget) then
        return false, "widget_create"
    end

    local controls = {}
    collect_widgets(widget, controls, 0)

    local added, slot = pcall(function()
        return self.parent_canvas:AddChildToCanvas(widget)
    end)
    slot = unwrap(slot)
    if not added or not valid_object(slot) then
        return false, "canvas_add"
    end
    pcall(function()
        slot:SetAnchors({
            Minimum = { X = 0, Y = 0 },
            Maximum = { X = 1, Y = 1 }
        })
        slot:SetAlignment({ X = 0, Y = 0 })
        slot:SetOffsets({ Left = 0, Top = 0, Right = 0, Bottom = 0 })
        slot:SetZOrder(Overlay.Z_ORDER)
    end)
    self.widget = widget
    self.controls = controls
    self.visible_segment_count = 0
    self.visible_fill_count = 0
    self.visible_node_count = 0
    self.visible_banner_count = 0
    local control_count = 0
    for _ in pairs(controls) do control_count = control_count + 1 end
    return true, string.format(
        "%s | controls=%d",
        full_name(widget),
        control_count
    )
end

function Overlay:_clear_runtime(forget_map)
    if valid_object(self.widget) then
        pcall(function() self.widget:RemoveFromParent() end)
    end
    self.map_base = nil
    self.map_body = nil
    self.parent_canvas = nil
    self.attachment_strategy = nil
    self.widget = nil
    self.controls = {}
    self.render_dirty = true
    self.visible_segment_count = 0
    self.visible_fill_count = 0
    self.visible_node_count = 0
    self.visible_banner_count = 0
    self.render_attempts = 0
    self.next_render_at = nil
    self.projection_size = nil
    self.projected_points = {}
    if forget_map == true then
        self.known_map_base = nil
        self.known_map_body = nil
        self.discovery_pending = false
        self.discovery_attempts = 0
        self.next_discovery_at = nil
        self.map_was_rendered = false
        self.attach_attempts = 0
        self.next_attach_at = nil
    end
end

function Overlay:_render_segments(throttle)
    local used = 0
    local stats = {
        controls = 0, inners = 0, projected = 0, slots = 0,
        normalized = 0
    }
    for index, segment in ipairs(self.model.segments or {}) do
        local control = self:_control(control_name("TerritorySegment", index))
        local inner = self:_control(
            control_name("TerritorySegmentInner", index)
        )
        if valid_object(control) then stats.controls = stats.controls + 1 end
        if valid_object(inner) then stats.inners = stats.inners + 1 end
        local first = self:_project_cached(segment.first)
        local second = self:_project_cached(segment.second)
        if first ~= nil and second ~= nil then
            stats.projected = stats.projected + 1
        end
        local layout = Overlay.segment_layout(
            first,
            second,
            Overlay.BORDER_THICKNESS
        )
        if valid_object(control) and valid_object(inner) and layout ~= nil
            and configure_canvas_slot(control, layout) then
            if layout.normalized == true then
                stats.normalized = stats.normalized + 1
                -- The packaged segment has an inset colored child. At the tiny
                -- normalized fallback size that inset disappears completely,
                -- so color the visible outline itself with the territory color.
                set_color(control, segment.color)
                set_color(inner, segment.color)
            else
                set_segment_colors(control, inner, segment.color)
            end
            show(control)
            used = index
            stats.slots = stats.slots + 1
        elseif valid_object(control) then
            hide(control)
        end
        if valid_object(control) and type(throttle) == "function" then
            throttle()
        end
    end
    local previous = tonumber(self.visible_segment_count) or 0
    for index = used + 1, previous do
        local control = self:_control(control_name("TerritorySegment", index))
        hide(control)
        if valid_object(control) and type(throttle) == "function" then
            throttle()
        end
    end
    self.visible_segment_count = used
    return used, stats
end

function Overlay:_render_fills(throttle)
    local entries = {}
    local boundaries = self.model.boundaries or {}
    local remaining = Overlay.MAX_FILLS
    for boundary_index, boundary in ipairs(boundaries) do
        if remaining <= 0 then break end
        local points, normalized = {}, false
        for _, world in ipairs(boundary.points or {}) do
            local projected = self:_project_cached(world)
            if projected == nil then points = {}; break end
            if projected.normalized == true then normalized = true; break end
            table.insert(points, projected)
        end
        if not normalized and #points >= 3 then
            local boundary_count = #boundaries - boundary_index + 1
            local quota = math.max(1, math.floor(remaining / boundary_count))
            local spans = TerritoryMapModel.scanline_spans(points, {
                spacing = 4,
                max_spans = quota
            })
            for _, span in ipairs(spans) do
                table.insert(entries, {
                    span = span,
                    color = boundary.fill_color
                })
            end
            remaining = Overlay.MAX_FILLS - #entries
        end
    end

    local used = 0
    for index, entry in ipairs(entries) do
        local control = self:_control(control_name("TerritoryFill", index))
        local span = entry.span
        if valid_object(control) and span.width > 0
            and configure_canvas_slot(control, {
                x = span.x,
                y = span.y - span.height / 2,
                width = span.width,
                height = span.height,
                angle = 0,
                z_order = Overlay.FILL_Z_ORDER
            }) then
            set_color(control, entry.color)
            show(control)
            used = index
        elseif valid_object(control) then
            hide(control)
        end
        if valid_object(control) and type(throttle) == "function" then
            throttle()
        end
    end
    local previous = tonumber(self.visible_fill_count) or 0
    for index = used + 1, previous do
        local control = self:_control(control_name("TerritoryFill", index))
        hide(control)
        if valid_object(control) and type(throttle) == "function" then
            throttle()
        end
    end
    self.visible_fill_count = used
    return used, { entries = #entries }
end

local function banner_status(status)
    if status == "WAR" then return "SAVAS" end
    if status == "ALLIANCE" then return "ITTIFAK" end
    if status == "PENDING" then return "BEKLIYOR" end
    if status == "OWN" then return "BIZIM TOPRAK" end
    return ""
end

function Overlay:_render_banners(throttle)
    local used = 0
    for index, banner in ipairs(self.model.banners or {}) do
        local frame = self:_control(control_name("GuildBannerFrame", index))
        local emblem = self:_control(control_name("GuildBannerEmblem", index))
        local name = self:_control(control_name("GuildBannerName", index))
        local stats = self:_control(control_name("GuildBannerStats", index))
        local power = self:_control(control_name("GuildBannerPower", index))
        local status = self:_control(control_name("GuildBannerStatus", index))
        local position = self:_project_cached(banner.world)
        if valid_object(frame) and position ~= nil then
            local normalized = position.normalized == true
            local width = normalized and Overlay.NORMALIZED_BANNER_WIDTH or 168
            local height = normalized and Overlay.NORMALIZED_BANNER_HEIGHT or 78
            local configured = configure_canvas_slot(frame, {
                normalized = normalized,
                anchor_x = position.x,
                anchor_y = position.y,
                alignment_x = 0.5,
                alignment_y = 0.5,
                x = normalized and 0 or position.x - width / 2,
                y = normalized and 0 or position.y - height / 2,
                width = width,
                height = height,
                angle = 0,
                z_order = Overlay.BANNER_Z_ORDER,
                render_scale = normalized
                    and Overlay.NORMALIZED_BANNER_RENDER_SCALE or 1
            })
            local text_ok = configured
                and set_text(emblem, banner.emblem_label, self.api.make_text)
                and set_text(name, banner.guild_name, self.api.make_text)
                and set_text(stats, banner.region_text, self.api.make_text)
                and set_text(power, banner.power_text, self.api.make_text)
                and set_text(status, banner_status(banner.status), self.api.make_text)
            if text_ok then
                set_color(frame, banner.color)
                show(frame)
                used = index
            else
                hide(frame)
            end
        elseif valid_object(frame) then
            hide(frame)
        end
        if valid_object(frame) and type(throttle) == "function" then
            throttle()
        end
    end
    local previous = tonumber(self.visible_banner_count) or 0
    for index = used + 1, previous do
        local frame = self:_control(control_name("GuildBannerFrame", index))
        hide(frame)
        if valid_object(frame) and type(throttle) == "function" then
            throttle()
        end
    end
    self.visible_banner_count = used
    return used
end

function Overlay:_render_nodes(throttle)
    local used = 0
    local stats = {
        controls = 0, projected = 0, slots = 0,
        label_controls = 0, label_slots = 0
    }
    self.node_hover = {}
    local positions = {}
    local centroids = {
        normalized = { x = 0, y = 0, count = 0, normalized = true },
        pixels = { x = 0, y = 0, count = 0, normalized = false }
    }
    for index, node in ipairs(self.model.nodes or {}) do
        local position = self:_project_cached(node.world)
        positions[index] = position
        if position ~= nil then
            stats.projected = stats.projected + 1
            local centroid = position.normalized == true
                and centroids.normalized or centroids.pixels
            centroid.x = centroid.x + (tonumber(position.x) or 0)
            centroid.y = centroid.y + (tonumber(position.y) or 0)
            centroid.count = centroid.count + 1
        end
    end
    for _, centroid in pairs(centroids) do
        if centroid.count > 0 then
            centroid.x = centroid.x / centroid.count
            centroid.y = centroid.y / centroid.count
        end
    end
    for index, node in ipairs(self.model.nodes or {}) do
        local control = self:_control(control_name("TerritoryNode", index))
        local label = self:_control(control_name("TerritoryNodeLabel", index))
        local label_text = self:_control(
            control_name("TerritoryNodeLabelText", index)
        )
        local icon_text = self:_control(
            control_name("TerritoryNodeIconText", index)
        )
        local hit = self:_control(control_name("TerritoryNodeHit", index))
        if valid_object(control) then stats.controls = stats.controls + 1 end
        if valid_object(label) and valid_object(label_text) then
            stats.label_controls = stats.label_controls + 1
        end
        local position = positions[index]
        if valid_object(control) and position ~= nil then
            local is_capital = node.node_type == "CAPITAL"
            local size = tonumber(node.size) or 11
            if position.normalized == true then
                size = is_capital and Overlay.NORMALIZED_CAPITAL_SIZE
                    or Overlay.NORMALIZED_OUTPOST_SIZE
            end
            local layout = {
                normalized = position.normalized == true,
                anchor_x = position.x,
                anchor_y = position.y,
                x = position.normalized == true and 0
                    or position.x - size / 2,
                y = position.normalized == true and 0
                    or position.y - size / 2,
                width = size,
                height = size,
                angle = tonumber(node.angle) or 0,
                z_order = is_capital and Overlay.CAPITAL_Z_ORDER
                    or Overlay.OUTPOST_Z_ORDER
            }
            local configured = configure_canvas_slot(control, layout)
            if configured then
                set_color(control, node.color)
                set_text(icon_text, node.node_type == "CAPITAL" and "B" or "K",
                    self.api.make_text)
                show(control)
                used = index
                stats.slots = stats.slots + 1
                local centroid = position.normalized == true
                    and centroids.normalized or centroids.pixels
                local label_layout = Overlay.node_label_layout(
                    node, index, position, centroid
                )
                if valid_object(label) and valid_object(label_text)
                    and label_layout ~= nil
                    and configure_canvas_slot(label, label_layout)
                    and set_text(
                        label_text,
                        Overlay.node_label_text(node),
                        self.api.make_text
                    ) then
                    hide(label)
                    stats.label_slots = stats.label_slots + 1
                elseif valid_object(label) then
                    hide(label)
                end
                local hit_size = size + (position.normalized == true and 1 or 10)
                local hit_layout = {
                    normalized = position.normalized == true,
                    anchor_x = position.x,
                    anchor_y = position.y,
                    alignment_x = 0.5,
                    alignment_y = 0.5,
                    x = position.normalized == true and 0
                        or position.x - hit_size / 2,
                    y = position.normalized == true and 0
                        or position.y - hit_size / 2,
                    width = hit_size,
                    height = hit_size,
                    angle = 0,
                    z_order = 35
                }
                if valid_object(hit)
                    and configure_canvas_slot(hit, hit_layout) then
                    show_interactive(hit)
                    self.node_hover[index] = { hit = hit, label = label }
                elseif valid_object(hit) then
                    hide(hit)
                end
            else
                hide(control)
                hide(label)
                hide(hit)
            end
        elseif valid_object(control) then
            hide(control)
            hide(label)
            hide(hit)
        end
        if valid_object(control) and type(throttle) == "function" then
            throttle()
        end
    end
    local previous = tonumber(self.visible_node_count) or 0
    for index = used + 1, previous do
        hide(self:_control(control_name("TerritoryNode", index)))
        hide(self:_control(control_name("TerritoryNodeLabel", index)))
        hide(self:_control(control_name("TerritoryNodeHit", index)))
        local control = self:_control(control_name("TerritoryNode", index))
        if valid_object(control) and type(throttle) == "function" then
            throttle()
        end
    end
    self.visible_node_count = used
    return used, stats
end

function Overlay:_update_hover_labels()
    for _, item in pairs(self.node_hover or {}) do
        if is_hovered(item.hit) then show(item.label) else hide(item.label) end
    end
end

function Overlay:_tick()
    local now = tonumber(self.api.now and self.api.now() or os.clock()) or 0
    if self.last_visibility_check_at ~= nil
        and now - self.last_visibility_check_at
            < Overlay.VISIBILITY_CHECK_INTERVAL_SECONDS then
        return
    end
    self.last_visibility_check_at = now

    if self.map_expected_open ~= true then return end

    if not valid_object(self.map_body) or not valid_object(self.parent_canvas) then
        if not self:_restore_known_map() then
            if not self:_attempt_discovery(now) then return end
        end
    end

    local map_rendered = self:_map_is_rendered()
    if not map_rendered then
        self.map_was_rendered = false
        self.attach_attempts = 0
        self.next_attach_at = nil
        if valid_object(self.widget) then
            self:_diagnostic(
                "runtime",
                "PALTR_MAP_OVERLAY_DETACHED | reason=map_hidden"
            )
            self:_clear_runtime(false)
        end
        return
    end
    if self.map_was_rendered ~= true then
        self.map_was_rendered = true
        self.render_dirty = true
        self.attach_attempts = 0
        self.next_attach_at = nil
    end

    if valid_object(self.widget) then
        self:_request_snapshot(now)
        self:_update_hover_labels()
        if self.render_dirty ~= true then return end
        if self.next_render_at ~= nil and now < self.next_render_at then return end
        self.render_dirty = false
        -- UE4SS UMG/UObject calls must remain on the hook's main Lua context.
        -- Coroutine rendering silently invalidates projection and slot calls.
        -- The renderers only touch active controls plus previously visible
        -- leftovers, so this synchronous pass stays bounded by model size.
        local rendered_segments, segment_stats = self:_render_segments()
        local rendered_fills, fill_stats = self:_render_fills()
        local rendered_nodes, node_stats = self:_render_nodes()
        local rendered_banners = self:_render_banners()
        local first_segment = self.model.segments and self.model.segments[1]
        local sample_first = first_segment
            and self:_project_cached(first_segment.first) or nil
        local sample_second = first_segment
            and self:_project_cached(first_segment.second) or nil
        self:_diagnostic("render", string.format(
            "PALTR_MAP_OVERLAY_RENDER | fills=%d/%d | segments=%d/%d"
                .. " | nodes=%d/%d | banners=%d/%d"
                .. " | segment_controls=%d | inners=%d | projected=%d | slots=%d"
                .. " | node_controls=%d | projected=%d | slots=%d"
                .. " | labels=%d/%d"
                .. " | sample=%.2f,%.2f>%.2f,%.2f",
            rendered_fills,
            tonumber(fill_stats.entries) or 0,
            rendered_segments,
            tonumber(self.model.segment_count) or 0,
            rendered_nodes,
            tonumber(self.model.node_count) or 0,
            rendered_banners,
            tonumber(self.model.banner_count) or 0,
            segment_stats.controls,
            segment_stats.inners,
            segment_stats.projected,
            segment_stats.slots,
            node_stats.controls,
            node_stats.projected,
            node_stats.slots,
            tonumber(node_stats.label_slots) or 0,
            tonumber(node_stats.label_controls) or 0,
            tonumber(sample_first and sample_first.x) or -1,
            tonumber(sample_first and sample_first.y) or -1,
            tonumber(sample_second and sample_second.x) or -1,
            tonumber(sample_second and sample_second.y) or -1
        ))
        local has_segments = (tonumber(self.model.segment_count) or 0) > 0
        local normalized_fallback = (tonumber(segment_stats.normalized) or 0) > 0
        local retry_needed = has_segments
            and (segment_stats.slots == 0 or normalized_fallback)
        local retry_limit = normalized_fallback
            and Overlay.NORMALIZED_RENDER_MAX_ATTEMPTS
            or Overlay.RENDER_MAX_ATTEMPTS
        if retry_needed and self.render_attempts < retry_limit then
            self.render_attempts = self.render_attempts + 1
            self.next_render_at = now + Overlay.RENDER_RETRY_INTERVAL_SECONDS
            self.render_dirty = true
            self:_reset_projection_lookup()
        else
            self.render_attempts = 0
            self.next_render_at = nil
        end
        return
    end

    if self.attach_attempts >= Overlay.ATTACH_MAX_ATTEMPTS then return end
    if self.next_attach_at ~= nil and now < self.next_attach_at then return end
    local created, create_detail = self:_create_widget()
    if created then
        self.attach_attempts = 0
        self.next_attach_at = nil
        self.next_render_at = now + Overlay.INITIAL_RENDER_DELAY_SECONDS
        self:_reset_projection_lookup()
        self.render_dirty = true
        self:_diagnostic("runtime", string.format(
            "PALTR_MAP_OVERLAY_ATTACHED | strategy=%s | widget=%s",
            tostring(self.attachment_strategy),
            tostring(create_detail)
        ))
        self:_request_snapshot(now)
    else
        self.attach_attempts = self.attach_attempts + 1
        self.next_attach_at = now + Overlay.ATTACH_RETRY_INTERVAL_SECONDS
        self:_diagnostic(
            "runtime",
            "PALTR_MAP_OVERLAY_ATTACH_FAILED | stage="
                .. tostring(create_detail)
        )
        self:_clear_runtime()
    end
end

function Overlay:_on_widget_construct(widget)
    if not self:_remember_map_widget(widget) then return end
    self.map_expected_open = true
    self:_diagnostic(
        "map_construct",
        "PALTR_MAP_OVERLAY_MAP_CONSTRUCTED | " .. full_name(unwrap(widget))
    )
    self.map_was_rendered = false
    self.attach_attempts = 0
    self.next_attach_at = nil
    if valid_object(self.widget) then self:_clear_runtime(false) end
end

function Overlay:_on_widget_destruct(widget)
    widget = unwrap(widget)
    if map_widget_kind(widget) == nil then return end
    if not same_object(widget, self.known_map_base)
        and not same_object(widget, self.known_map_body)
        and not same_object(widget, self.map_base)
        and not same_object(widget, self.map_body) then
        return
    end
    self:_diagnostic(
        "runtime",
        "PALTR_MAP_OVERLAY_DETACHED | reason=map_destruct"
    )
    self.map_expected_open = false
    self:_clear_runtime(true)
end

function Overlay:register()
    if self.registered then return true end
    if type(self.api.register_hook) ~= "function" then
        return false, "UE4SS RegisterHook API hazir degil."
    end
    PalTRTerritoryMapOverlayCallbacks.tick = function()
        local ok, tick_error = pcall(function() self:_tick() end)
        if not ok and type(print) == "function" then
            print("[PalTRUI] PALTR_MAP_OVERLAY_TICK_ERROR | "
                .. tostring(tick_error) .. "\n")
        end
    end
    PalTRTerritoryMapOverlayCallbacks.construct = function(widget)
        local ok, hook_error = pcall(function()
            self:_on_widget_construct(widget)
        end)
        if not ok and type(print) == "function" then
            print("[PalTRUI] PALTR_MAP_OVERLAY_CONSTRUCT_ERROR | "
                .. tostring(hook_error) .. "\n")
        end
    end
    PalTRTerritoryMapOverlayCallbacks.destruct = function(widget)
        local ok, hook_error = pcall(function()
            self:_on_widget_destruct(widget)
        end)
        if not ok and type(print) == "function" then
            print("[PalTRUI] PALTR_MAP_OVERLAY_DESTRUCT_ERROR | "
                .. tostring(hook_error) .. "\n")
        end
    end
    PalTRTerritoryMapOverlayCallbacks.map_key = function()
        self:toggle_map_expected_open("map_key")
    end
    local tick_hooked, tick_pre_id, tick_post_id = pcall(
        self.api.register_hook,
        Overlay.TICK_HOOK,
        PalTRTerritoryMapOverlayCallbacks.tick
    )
    if not tick_hooked then return false, tostring(tick_pre_id) end
    local construct_hooked, construct_pre_id, construct_post_id = pcall(
        self.api.register_hook,
        Overlay.WIDGET_CONSTRUCT_HOOK,
        PalTRTerritoryMapOverlayCallbacks.construct
    )
    if not construct_hooked then return false, tostring(construct_pre_id) end
    local destruct_hooked, destruct_pre_id, destruct_post_id = pcall(
        self.api.register_hook,
        Overlay.WIDGET_DESTRUCT_HOOK,
        PalTRTerritoryMapOverlayCallbacks.destruct
    )
    if not destruct_hooked then return false, tostring(destruct_pre_id) end
    local key_registered = false
    if type(self.api.register_key_bind) == "function"
        and self.api.map_key ~= nil then
        local key_called = pcall(
            self.api.register_key_bind,
            self.api.map_key,
            PalTRTerritoryMapOverlayCallbacks.map_key
        )
        key_registered = key_called == true
    end
    self.registered = true
    return true, {
        tick = { pre_id = tick_pre_id, post_id = tick_post_id },
        construct = {
            pre_id = construct_pre_id,
            post_id = construct_post_id
        },
        destruct = {
            pre_id = destruct_pre_id,
            post_id = destruct_post_id
        },
        map_key = key_registered
    }
end

return Overlay
