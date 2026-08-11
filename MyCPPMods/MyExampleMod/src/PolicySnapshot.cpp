#include "PolicySnapshot.hpp"

#include <algorithm>
#include <cctype>
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

        if (!read_rows(m_data_root / "player_registry.tsv", player_rows, error)
            || !read_rows(m_data_root / "guild_registry.tsv", guild_rows, error)
            || !read_rows(m_data_root / "diplomacy_relations.tsv", relation_rows, error)
            || !read_protection_rows(
                m_data_root / "guild_protection.tsv",
                protection_rows,
                error))
        {
            return false;
        }

        std::unordered_map<std::string, std::string> player_guild_by_uid;
        std::unordered_map<std::string, std::string> player_guild_by_pawn_path;
        std::unordered_map<std::string, std::string> guild_key_by_group_id;
        std::unordered_set<std::string> alliance_pairs;
        std::unordered_set<std::string> offline_protected_guilds;

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

        m_player_guild_by_uid = std::move(player_guild_by_uid);
        m_player_guild_by_pawn_path = std::move(player_guild_by_pawn_path);
        m_guild_key_by_group_id = std::move(guild_key_by_group_id);
        m_alliance_pairs = std::move(alliance_pairs);
        m_offline_protected_guilds = std::move(offline_protected_guilds);
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
}
