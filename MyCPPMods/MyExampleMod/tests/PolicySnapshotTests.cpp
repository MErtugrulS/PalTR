#include "PolicySnapshot.hpp"

#include <filesystem>
#include <fstream>
#include <iostream>
#include <string>

namespace
{
    void write_file(const std::filesystem::path& path, const std::string& contents)
    {
        std::ofstream output(path, std::ios::trunc);
        output << contents;
    }

    bool expect(bool condition, const char* message)
    {
        if (!condition)
        {
            std::cerr << "FAILED: " << message << '\n';
        }
        return condition;
    }
}

int main()
{
    const auto root = std::filesystem::temp_directory_path()
        / "paltr_structure_guard_policy_tests";
    std::filesystem::create_directories(root);

    write_file(
        root / "player_registry.tsv",
        "player_key\tplayer_name\tplayer_id\tplayer_uid\tguild_key\trole\tis_master\tplayer_state_path\tpawn_path\n"
        "owner\tOwner\t1\tAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\tGUILD_A\t1\ttrue\tStateA\tPawnA\n"
        "attacker\tAttacker\t2\tBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB\tGUILD_B\t1\tfalse\tStateB\tPawnB\n"
        "neutral\tNeutral\t3\tCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC\tGUILD_C\t1\tfalse\tStateC\tPawnC\n");
    write_file(
        root / "guild_registry.tsv",
        "guild_key\tguild_name\tguild_id\n"
        "GUILD_B\tAttackers\tBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB\n"
        "GUILD_C\tNeutral\tCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC\n");
    write_file(
        root / "diplomacy_relations.tsv",
        "pair_key\tguild_a\tguild_b\tstate\n"
        "GUILD_A::GUILD_B\tGUILD_A\tGUILD_B\tALLIANCE\n"
        "GUILD_A::GUILD_C\tGUILD_A\tGUILD_C\tNEUTRAL\n");

    PalTR::PolicySnapshot snapshot(root);
    std::string error;
    bool ok = expect(snapshot.refresh_if_changed(error), "snapshot loads");

    const auto allied = snapshot.evaluate_alliance_structure_damage(
        "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
        "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB");
    ok &= expect(allied.block, "active alliance blocks");
    ok &= expect(allied.reason == "ACTIVE_ALLIANCE", "alliance reason preserved");

    const auto allied_by_pawn = snapshot.evaluate_alliance_structure_damage_by_pawn(
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "PawnB");
    ok &= expect(allied_by_pawn.block, "active alliance blocks by attacker pawn");

    const auto neutral_by_pawn = snapshot.evaluate_alliance_structure_damage_by_pawn(
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "PawnC");
    ok &= expect(!neutral_by_pawn.block, "neutral pawn relation allows");

    const auto unknown_pawn = snapshot.evaluate_alliance_structure_damage_by_pawn(
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "UnknownPawn");
    ok &= expect(!unknown_pawn.block, "unresolved pawn identity fails open");

    const auto neutral = snapshot.evaluate_alliance_structure_damage(
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC");
    ok &= expect(!neutral.block, "neutral relation allows");

    const auto unknown = snapshot.evaluate_alliance_structure_damage(
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD");
    ok &= expect(!unknown.block, "unresolved identity fails open");

    write_file(
        root / "diplomacy_relations.tsv",
        "pair_key\tguild_a\tguild_b\tstate\n"
        "GUILD_A::GUILD_B\tGUILD_A\tGUILD_B\tNEUTRAL\n");
    ok &= expect(snapshot.refresh_if_changed(error), "changed snapshot reloads");
    const auto ended = snapshot.evaluate_alliance_structure_damage(
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB");
    ok &= expect(!ended.block, "ended alliance allows after reload");

    std::error_code cleanup_error;
    std::filesystem::remove_all(root, cleanup_error);
    return ok ? 0 : 1;
}
