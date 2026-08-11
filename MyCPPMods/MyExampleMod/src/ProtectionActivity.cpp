#include "ProtectionActivity.hpp"

#include <algorithm>
#include <fstream>
#include <utility>
#include <vector>

namespace
{
    constexpr std::int64_t persist_interval_seconds = 5;
    constexpr auto expected_header = "guild_key\tlast_hostile_at";
}

namespace PalTR
{
    ProtectionActivityStore::ProtectionActivityStore(std::filesystem::path path)
        : m_path(std::move(path))
    {
    }

    bool ProtectionActivityStore::ensure_loaded(std::string& error)
    {
        if (m_loaded)
        {
            return true;
        }

        std::ifstream input(m_path);
        if (!input)
        {
            m_loaded = true;
            return true;
        }

        std::string line;
        if (!std::getline(input, line))
        {
            error = "empty combat activity file " + m_path.string();
            return false;
        }
        if (!line.empty() && line.back() == '\r')
        {
            line.pop_back();
        }
        if (line != expected_header)
        {
            error = "invalid combat activity header " + m_path.string();
            return false;
        }

        while (std::getline(input, line))
        {
            if (!line.empty() && line.back() == '\r')
            {
                line.pop_back();
            }

            const auto separator = line.find('\t');
            if (separator == std::string::npos || separator == 0)
            {
                continue;
            }

            const auto guild_key = line.substr(0, separator);
            try
            {
                const auto timestamp = std::stoll(line.substr(separator + 1));
                if (timestamp >= 0)
                {
                    m_last_hostile_at[guild_key] = timestamp;
                    m_last_persisted_at[guild_key] = timestamp;
                }
            }
            catch (...)
            {
            }
        }

        m_loaded = true;
        error.clear();
        return true;
    }

    bool ProtectionActivityStore::persist(std::string& error)
    {
        std::vector<std::string> guild_keys;
        guild_keys.reserve(m_last_hostile_at.size());
        for (const auto& [guild_key, _] : m_last_hostile_at)
        {
            guild_keys.emplace_back(guild_key);
        }
        std::sort(guild_keys.begin(), guild_keys.end());

        std::ofstream output(m_path, std::ios::trunc);
        if (!output)
        {
            error = "cannot write " + m_path.string();
            return false;
        }

        output << expected_header << '\n';
        for (const auto& guild_key : guild_keys)
        {
            output << guild_key << '\t' << m_last_hostile_at.at(guild_key) << '\n';
        }
        if (!output)
        {
            error = "cannot finish writing " + m_path.string();
            return false;
        }

        error.clear();
        return true;
    }

    bool ProtectionActivityStore::record(
        const std::string& target_guild_key,
        std::int64_t timestamp,
        std::string& error)
    {
        if (target_guild_key.empty() || timestamp < 0)
        {
            error = "invalid combat activity";
            return false;
        }
        if (!ensure_loaded(error))
        {
            return false;
        }

        auto& current = m_last_hostile_at[target_guild_key];
        current = std::max(current, timestamp);

        const auto persisted = m_last_persisted_at[target_guild_key];
        if (current - persisted < persist_interval_seconds)
        {
            error.clear();
            return true;
        }
        if (!persist(error))
        {
            return false;
        }

        m_last_persisted_at[target_guild_key] = current;
        return true;
    }

    std::int64_t ProtectionActivityStore::last_hostile_at(
        const std::string& guild_key) const
    {
        const auto found = m_last_hostile_at.find(guild_key);
        return found == m_last_hostile_at.end() ? 0 : found->second;
    }
}
