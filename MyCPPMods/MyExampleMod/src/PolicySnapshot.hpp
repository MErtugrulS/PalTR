#pragma once

#include <filesystem>
#include <string>
#include <unordered_map>
#include <unordered_set>

namespace PalTR
{
    struct AllianceDecision
    {
        bool block{};
        std::string target_guild_key;
        std::string attacker_guild_key;
        std::string reason;
    };

    class PolicySnapshot
    {
    public:
        explicit PolicySnapshot(std::filesystem::path data_root);

        bool refresh_if_changed(std::string& error);
        AllianceDecision evaluate_alliance_structure_damage(
            const std::string& build_player_uid,
            const std::string& attacker_group_id) const;

    private:
        bool reload(std::string& error);

        std::filesystem::path m_data_root;
        std::unordered_map<std::string, std::string> m_player_guild_by_uid;
        std::unordered_map<std::string, std::string> m_guild_key_by_group_id;
        std::unordered_set<std::string> m_alliance_pairs;
    };
}
