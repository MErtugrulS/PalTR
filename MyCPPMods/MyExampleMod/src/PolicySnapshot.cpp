#include "PolicySnapshot.hpp"

#include <algorithm>
#include <cctype>
#include <cmath>
#include <fstream>
#include <sstream>
#include <utility>
#include <vector>

namespace
{
    std::vector<std::string> split_tsv(const std::string& line)
    {
        std::vector<std::string> columns;
        std::size_t start = 0;

        while (start <= line.size())
        {
            const auto end = line.find('\t', start);
            columns.emplace_back(line.substr(start, end - start));
            if (end == std::string::npos)
            {
                break;
            }
            start = end + 1;
        }

        return columns;
    }

    std::string normalize_guid(std::string value)
    {
        value.erase(
            std::remove_if(
                value.begin(),
                value.end(),
                [](const unsigned char character) {
                    return std::isxdigit(character) == 0;
                }),
            value.end());

        std::transform(
            value.begin(),
            value.end(),
            value.begin(),
            [](const unsigned char character) {
                return static_cast<char>(std::toupper(character));
            });

        return value.size() == 32 ? value : std::string{};
    }

    std::string pair_key(const std::string& first, const std::string& second)
    {
        return first < second
            ? first + "::" + second
            : second + "::" + first;
    }

    bool read_rows(
        const std::filesystem::path& path,
        std::vector<std::vector<std::string>>& rows,
        std::string& error)
    {
        std::ifstream input(path);
        if (!input)
        {
            error = "cannot open " + path.string();
            return false;
        }

        std::string line;
        bool header = true;
        while (std::getline(input, line))
        {
            if (!line.empty() && line.back() == '\r')
            {
                line.pop_back();
            }
            if (header)
            {
                header = false;
                continue;
            }
            if (!line.empty())
            {
                rows.emplace_back(split_tsv(line));
            }
        }

        return true;
    }

    bool read_protection_rows(
        const std::filesystem::path& path,
        std::vector<std::vector<std::string>>& rows,
        std::string& error)
    {
        std::ifstream input(path);
        if (!input)
        {
            return true;
        }

        std::string line;
        if (!std::getline(input, line))
        {
            error = "empty protection snapshot " + path.string();
            return false;
        }
        if (!line.empty() && line.back() == '\r')
        {
            line.pop_back();
        }
        if (line != "guild_key\tonline_count\tlast_online_at\tlast_hostile_at\tprotected_at\tprotected\treason")
        {
            error = "invalid protection snapshot header " + path.string();
            return false;
        }

        while (std::getline(input, line))
        {
            if (!line.empty() && line.back() == '\r')
            {
                line.pop_back();
            }
            if (!line.empty())
            {
                rows.emplace_back(split_tsv(line));
            }
        }

        return true;
    }

    bool read_conquest_rows(
        const std::filesystem::path& path,
        std::vector<std::vector<std::string>>& rows,
        std::string& error)
    {
        std::ifstream input(path);
        if (!input)
        {
            return true;
        }

        std::string line;
        if (!std::getline(input, line))
        {
            error = "empty conquest snapshot " + path.string();
            return false;
        }
        if (!line.empty() && line.back() == '\r')
        {
            line.pop_back();
        }
        if (line != "flag_reference\tnode_id\towner_guild\tallowed_attacker_guild")
        {
            error = "invalid conquest snapshot header " + path.string();
            return false;
        }

        while (std::getline(input, line))
        {
            if (!line.empty() && line.back() == '\r')
            {
                line.pop_back();
            }
            if (!line.empty())
            {
                rows.emplace_back(split_tsv(line));
            }
        }
        return true;
    }

    bool read_conquest_zone_rows(
        const std::filesystem::path& path,
        std::vector<std::vector<std::string>>& rows,
        std::string& error)
    {
        std::ifstream input(path);
        if (!input)
        {
            return true;
        }

        std::string line;
        if (!std::getline(input, line))
        {
            error = "empty conquest zone snapshot " + path.string();
            return false;
        }
        if (!line.empty() && line.back() == '\r')
        {
            line.pop_back();
        }
        if (line != "node_id\towner_guild\tallowed_attacker_guild\tcenter_x_world\tcenter_y_world\tcenter_z_world\tradius_world")
        {
            error = "invalid conquest zone snapshot header " + path.string();
            return false;
        }

        while (std::getline(input, line))
        {
            if (!line.empty() && line.back() == '\r')
            {
                line.pop_back();
            }
            if (!line.empty())
            {
                rows.emplace_back(split_tsv(line));
            }
        }
        return true;
    }

    bool parse_finite_double(const std::string& value, double& parsed)
    {
        try
        {
            std::size_t consumed = 0;
            parsed = std::stod(value, &consumed);
            return consumed == value.size() && std::isfinite(parsed);
        }
        catch (...)
        {
            return false;
        }
    }
}

namespace PalTR
{
    PolicySnapshot::PolicySnapshot(std::filesystem::path data_root)
        : m_data_root(std::move(data_root))
    {
    }

    bool PolicySnapshot::refresh_if_changed(std::string& error)
    {
        return reload(error);
    }

    bool PolicySnapshot::reload(std::string& error)
    {
        std::vector<std::vector<std::string>> player_rows;
        std::vector<std::vector<std::string>> guild_rows;
        std::vector<std::vector<std::string>> relation_rows;
        std::vector<std::vector<std::string>> protection_rows;
        std::vector<std::vector<std::string>> conquest_rows;
        std::vector<std::vector<std::string>> conquest_zone_rows;

        if (!read_rows(m_data_root / "player_registry.tsv", player_rows, error)
            || !read_rows(m_data_root / "guild_registry.tsv", guild_rows, error)
            || !read_rows(m_data_root / "diplomacy_relations.tsv", relation_rows, error)
            || !read_protection_rows(
                m_data_root / "guild_protection.tsv",
                protection_rows,
                error)
            || !read_conquest_rows(
                m_data_root / "conquest_damage_policy.tsv",
                conquest_rows,
                error)
            || !read_conquest_zone_rows(
                m_data_root / "conquest_zone_policy.tsv",
                conquest_zone_rows,
                error))
        {
            return false;
        }

        std::unordered_map<std::string, std::string> player_guild_by_uid;
        std::unordered_map<std::string, std::string> player_guild_by_pawn_path;
        std::unordered_map<std::string, std::string> guild_key_by_group_id;
        std::unordered_set<std::string> alliance_pairs;
        std::unordered_set<std::string> offline_protected_guilds;
        std::unordered_map<std::string, std::string> conquest_flag_owner;
        std::unordered_set<std::string> conquest_allowed_attackers;
        std::vector<ConquestZone> conquest_zones;

        for (const auto& columns : player_rows)
        {
            if (columns.size() < 5)
            {
                continue;
            }
            const auto uid = normalize_guid(columns[3]);
            if (!uid.empty() && !columns[4].empty())
            {
                player_guild_by_uid[uid] = columns[4];
            }
            if (columns.size() > 8 && !columns[8].empty() && !columns[4].empty())
            {
                player_guild_by_pawn_path[columns[8]] = columns[4];
            }
        }

        for (const auto& columns : guild_rows)
        {
            if (columns.size() < 3)
            {
                continue;
            }
            const auto group_id = normalize_guid(columns[2]);
            if (!group_id.empty() && !columns[0].empty())
            {
                guild_key_by_group_id[group_id] = columns[0];
            }
        }

        for (const auto& columns : relation_rows)
        {
            if (columns.size() < 4 || columns[3] != "ALLIANCE")
            {
                continue;
            }
            if (!columns[1].empty() && !columns[2].empty())
            {
                alliance_pairs.emplace(pair_key(columns[1], columns[2]));
            }
        }

        for (const auto& columns : protection_rows)
        {
            if (columns.size() >= 6
                && !columns[0].empty()
                && columns[5] == "true")
            {
                offline_protected_guilds.emplace(columns[0]);
            }
        }

        for (const auto& columns : conquest_rows)
        {
            if (columns.size() < 4 || columns[2].empty())
            {
                continue;
            }

            const auto instance_id = normalize_guid(columns[0]);
            if (instance_id.empty())
            {
                continue;
            }

            conquest_flag_owner[instance_id] = columns[2];
            if (!columns[3].empty())
            {
                conquest_allowed_attackers.emplace(
                    instance_id + "::" + columns[3]);
            }
        }

        for (const auto& columns : conquest_zone_rows)
        {
            if (columns.size() < 7
                || columns[0].empty()
                || columns[1].empty()
                || columns[2].empty())
            {
                continue;
            }

            double center_x = 0;
            double center_y = 0;
            double center_z = 0;
            double radius = 0;
            if (!parse_finite_double(columns[3], center_x)
                || !parse_finite_double(columns[4], center_y)
                || !parse_finite_double(columns[5], center_z)
                || !parse_finite_double(columns[6], radius)
                || radius <= 0)
            {
                continue;
            }

            conquest_zones.push_back(ConquestZone{
                columns[0],
                columns[1],
                columns[2],
                center_x,
                center_y,
                center_z,
                radius * radius});
        }

        m_player_guild_by_uid = std::move(player_guild_by_uid);
        m_player_guild_by_pawn_path = std::move(player_guild_by_pawn_path);
        m_guild_key_by_group_id = std::move(guild_key_by_group_id);
        m_alliance_pairs = std::move(alliance_pairs);
        m_offline_protected_guilds = std::move(offline_protected_guilds);
        m_conquest_flag_owner = std::move(conquest_flag_owner);
        m_conquest_allowed_attackers = std::move(conquest_allowed_attackers);
        m_conquest_zones = std::move(conquest_zones);
        error.clear();
        return true;
    }

    AllianceDecision PolicySnapshot::evaluate_alliance_structure_damage(
        const std::string& build_player_uid,
        const std::string& attacker_group_id) const
    {
        return evaluate_alliance_guilds(
            guild_for_player_uid(build_player_uid),
            guild_for_group_id(attacker_group_id));
    }

    AllianceDecision PolicySnapshot::evaluate_alliance_structure_damage_by_pawn(
        const std::string& build_player_uid,
        const std::string& attacker_pawn_path) const
    {
        return evaluate_alliance_guilds(
            guild_for_player_uid(build_player_uid),
            guild_for_pawn_path(attacker_pawn_path));
    }

    AllianceDecision PolicySnapshot::evaluate_alliance_guilds(
        const std::string& target_guild_key,
        const std::string& attacker_guild_key) const
    {
        AllianceDecision result{};
        if (target_guild_key.empty() || attacker_guild_key.empty())
        {
            result.reason = "STRUCTURE_IDENTITY_UNRESOLVED";
            return result;
        }

        result.target_guild_key = target_guild_key;
        result.attacker_guild_key = attacker_guild_key;

        if (result.target_guild_key == result.attacker_guild_key)
        {
            result.reason = "SAME_GUILD_NOT_HANDLED";
            return result;
        }

        result.block = m_alliance_pairs.contains(
            pair_key(result.target_guild_key, result.attacker_guild_key));
        result.reason = result.block ? "ACTIVE_ALLIANCE" : "NOT_ALLIED";
        return result;
    }

    AllianceDecision PolicySnapshot::evaluate_protected_guilds(
        const std::string& target_guild_key,
        const std::string& attacker_guild_key,
        bool attacker_present,
        bool protect_either) const
    {
        AllianceDecision result{};
        result.target_guild_key = target_guild_key;
        result.attacker_guild_key = attacker_guild_key;

        if (!attacker_guild_key.empty()
            && attacker_guild_key == target_guild_key)
        {
            result.reason = "SAME_GUILD_NOT_HANDLED";
            return result;
        }

        const bool target_protected =
            is_guild_offline_protected(target_guild_key);
        const bool attacker_protected = protect_either
            && is_guild_offline_protected(attacker_guild_key);
        if ((attacker_present && target_protected) || attacker_protected)
        {
            result.block = true;
            result.reason = "OFFLINE_PROTECTION";
            return result;
        }

        return evaluate_alliance_guilds(
            target_guild_key,
            attacker_guild_key);
    }

    std::string PolicySnapshot::guild_for_player_uid(const std::string& player_uid) const
    {
        const auto found = m_player_guild_by_uid.find(normalize_guid(player_uid));
        return found == m_player_guild_by_uid.end() ? std::string{} : found->second;
    }

    std::string PolicySnapshot::guild_for_pawn_path(const std::string& pawn_path) const
    {
        const auto found = m_player_guild_by_pawn_path.find(pawn_path);
        return found == m_player_guild_by_pawn_path.end() ? std::string{} : found->second;
    }

    std::string PolicySnapshot::guild_for_group_id(const std::string& group_id) const
    {
        const auto found = m_guild_key_by_group_id.find(normalize_guid(group_id));
        return found == m_guild_key_by_group_id.end() ? std::string{} : found->second;
    }

    bool PolicySnapshot::is_guild_offline_protected(const std::string& guild_key) const
    {
        return !guild_key.empty()
            && m_offline_protected_guilds.contains(guild_key);
    }

    ConquestFlagDecision PolicySnapshot::evaluate_conquest_flag_damage(
        const std::string& instance_id,
        const std::string& attacker_guild_key) const
    {
        ConquestFlagDecision result{};
        const auto normalized = normalize_guid(instance_id);
        const auto found = m_conquest_flag_owner.find(normalized);
        if (found == m_conquest_flag_owner.end())
        {
            return result;
        }

        result.handled = true;
        result.target_guild_key = found->second;
        result.attacker_guild_key = attacker_guild_key;

        if (!attacker_guild_key.empty()
            && attacker_guild_key == result.target_guild_key)
        {
            result.reason = "SAME_GUILD_NOT_HANDLED";
            return result;
        }

        const bool allowed = !attacker_guild_key.empty()
            && m_conquest_allowed_attackers.contains(
                normalized + "::" + attacker_guild_key);
        result.block = !allowed;
        result.reason = allowed
            ? "ACTIVE_CONQUEST_TARGET"
            : "CONQUEST_FLAG_PROTECTED";
        return result;
    }

    bool PolicySnapshot::is_conquest_flag(const std::string& instance_id) const
    {
        return m_conquest_flag_owner.contains(normalize_guid(instance_id));
    }

    ConquestZoneDecision PolicySnapshot::evaluate_conquest_zone_damage(
        const std::string& target_guild_key,
        const std::string& attacker_guild_key,
        const double target_x,
        const double target_y,
        const double target_z) const
    {
        ConquestZoneDecision result{};
        result.target_guild_key = target_guild_key;
        result.attacker_guild_key = attacker_guild_key;
        if (target_guild_key.empty()
            || attacker_guild_key.empty()
            || !std::isfinite(target_x)
            || !std::isfinite(target_y)
            || !std::isfinite(target_z))
        {
            return result;
        }

        for (const auto& zone : m_conquest_zones)
        {
            if (zone.owner_guild_key != target_guild_key
                || zone.allowed_attacker_guild_key != attacker_guild_key)
            {
                continue;
            }

            const auto delta_x = target_x - zone.center_x;
            const auto delta_y = target_y - zone.center_y;
            const auto delta_z = target_z - zone.center_z;
            if ((delta_x * delta_x)
                + (delta_y * delta_y)
                + (delta_z * delta_z) <= zone.radius_squared)
            {
                result.allow = true;
                result.node_id = zone.node_id;
                result.reason = "ACTIVE_CONQUEST_ZONE";
                return result;
            }
        }

        return result;
    }
}
