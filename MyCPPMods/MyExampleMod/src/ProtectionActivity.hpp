#pragma once

#include <cstdint>
#include <filesystem>
#include <string>
#include <unordered_map>

namespace PalTR
{
    class ProtectionActivityStore
    {
    public:
        explicit ProtectionActivityStore(std::filesystem::path path);

        bool record(
            const std::string& target_guild_key,
            std::int64_t timestamp,
            std::string& error);
        std::int64_t last_hostile_at(const std::string& guild_key) const;

    private:
        bool ensure_loaded(std::string& error);
        bool persist(std::string& error);

        std::filesystem::path m_path;
        bool m_loaded{};
        std::unordered_map<std::string, std::int64_t> m_last_hostile_at;
        std::unordered_map<std::string, std::int64_t> m_last_persisted_at;
    };
}
