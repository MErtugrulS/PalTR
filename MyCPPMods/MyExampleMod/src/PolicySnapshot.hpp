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
        AllianceDecision evaluate_alliance_structure_damage_by_pawn(
            const std::string& build_player_uid,
            const std::string& attacker_pawn_path) const;
        AllianceDecision evaluate_alliance_guilds(
            const std::string& target_guild_key,
            const std::string& attacker_guild_key) const;
        AllianceDecision evaluate_protected_guilds(
            const std::string& target_guild_key,
            const std::string& attacker_guild_key,
            bool attacker_present,
            bool protect_either) const;
        std::string guild_for_player_uid(const std::string& player_uid) const;
        std::string guild_for_pawn_path(const std::string& pawn_path) const;
        std::string guild_for_group_id(const std::string& group_id) const;
        bool is_guild_offline_protected(const std::string& guild_key) const;

    private:
        bool reload(std::string& error);

        std::filesystem::path m_data_root;
        std::unordered_map<std::string, std::string> m_player_guild_by_uid;
        std::unordered_map<std::string, std::string> m_player_guild_by_pawn_path;
        std::unordered_map<std::string, std::string> m_guild_key_by_group_id;
        std::unordered_set<std::string> m_alliance_pairs;
        std::unordered_set<std::string> m_offline_protected_guilds;
    };
}
