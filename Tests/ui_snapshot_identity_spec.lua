package.path = "Scripts/?.lua;Scripts/?/init.lua;" .. package.path

local Snapshot = require("PalTR.services.ui_snapshot_service")
local Codec = require("PalTR.core.ui_snapshot_codec")

local function equal(actual, expected, label)
    if actual ~= expected then
        error(label .. ": expected=" .. tostring(expected)
            .. " actual=" .. tostring(actual))
    end
end

local registry = {
    guilds = {
        A = { name = "Alpha" },
        B = { name = "Beta" }
    },
    players = {},
    runtime_guilds = {}
}
local diplomacy = {}
function diplomacy:relations_for() return {} end

local identity = {
    records = {
        A = { color_id = "azure", emblem_id = "wolf" },
        B = { color_id = "red", emblem_id = "eagle" }
    }
}
function identity:get(key) return self.records[key] end
function identity:catalog_for(key, role)
    return {
        palette_version = 1,
        selected_color_id = self.records[key].color_id,
        selected_emblem_id = self.records[key].emblem_id,
        locked = true,
        can_manage = role == "LEADER",
        colors = {
            { id = "azure", hex = "#2F80ED", available = true },
            { id = "red", hex = "#D94A4A", available = false }
        },
        emblems = { { id = "wolf", name = "Kurt" } }
    }
end

local service = Snapshot.new(registry, diplomacy, nil, {}, {
    config = { conquest = { game_role_map = {}, operator_roles = {} } },
    guild_identity = identity,
    protection_reader = function() return {} end,
    territory_reader = function()
        return { nodes = {}, boundaries = {} }
    end
})
service.shared_recent_events = {}
local built = service:build({
    name = "Tester", guild_key = "A", role = 9, is_master = true
})
equal(built.schema_version, 2, "snapshot v2")
equal(built.guild.color_id, "azure", "own color")
equal(built.guild.emblem_id, "wolf", "own emblem")
equal(built.guilds[1].color_id, "red", "other color")
equal(built.guild_identity.can_manage, true, "leader can manage")

local payload = assert(Codec.encode(built))
local decoded = assert(Codec.decode(payload))
equal(decoded.guild_identity.palette_version, 1, "palette roundtrip")
equal(decoded.guilds[1].emblem_id, "eagle", "guild roundtrip")
equal(#decoded.guild_identity.colors, 2, "colors roundtrip")

local legacy = payload
    :gsub("\nguild%.color_id\t[^\n]*", "")
    :gsub("\nguild%.emblem_id\t[^\n]*", "")
    :gsub("\nguild_identity%.[^\n]*", "")
    :gsub("\nguilds%.1%.color_id\t[^\n]*", "")
    :gsub("\nguilds%.1%.emblem_id\t[^\n]*", "")
    :gsub("schema_version\t2", "schema_version\t1", 1)
local legacy_decoded = assert(Codec.decode(legacy))
equal(legacy_decoded.schema_version, 1, "legacy v1 accepted")
equal(legacy_decoded.guild.color_id, "", "legacy neutral color")
equal(legacy_decoded.guild_identity.palette_version, 0,
    "legacy neutral palette")

print("ui_snapshot_identity_spec: ok")
