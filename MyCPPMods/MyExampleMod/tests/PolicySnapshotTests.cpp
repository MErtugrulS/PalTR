#include "PolicySnapshot.hpp"
#include "ProtectionActivity.hpp"

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
    write_file(
        root / "guild_protection.tsv",
        "guild_key\tonline_count\tlast_online_at\tlast_hostile_at\tprotected_at\tprotected\treason\n"
        "GUILD_A\t0\t1000\t2000\t3200\ttrue\tOFFLINE_PROTECTED\n"
        "GUILD_B\t1\t3200\t0\t0\tfalse\tONLINE\n");
    write_file(
        root / "conquest_damage_policy.tsv",
        "flag_reference\tnode_id\towner_guild\tallowed_attacker_guild\n"
        "11111111111111111111111111111111\tNODE_A\tGUILD_A\tGUILD_B\n"
        "22222222222222222222222222222222\tNODE_B\tGUILD_A\t\n");
    write_file(
        root / "conquest_zone_policy.tsv",
        "node_id\towner_guild\tallowed_attacker_guild\tcenter_x_world\tcenter_y_world\tcenter_z_world\tradius_world\n"
        "NODE_A\tGUILD_A\tGUILD_B\t1000\t2000\t3000\t15000\n"
        "INVALID\tGUILD_A\tGUILD_C\t0\t0\t0\tnot-a-radius\n"
        "OVERFLOW\tGUILD_A\tGUILD_C\t0\t0\t0\t1e308\n");

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

    const auto allied_guilds = snapshot.evaluate_alliance_guilds(
        "GUILD_A",
        "GUILD_B");
    ok &= expect(allied_guilds.block, "active alliance blocks by guild keys");
    ok &= expect(
        snapshot.guild_for_pawn_path("PawnB") == "GUILD_B",
        "pawn path resolves guild");
    ok &= expect(
        snapshot.guild_for_player_uid("AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA") == "GUILD_A",
        "player uid resolves guild");
    ok &= expect(
        snapshot.guild_for_group_id("BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB") == "GUILD_B",
        "group id resolves guild");
    ok &= expect(
        snapshot.is_guild_offline_protected("GUILD_A"),
        "offline protected guild loads");
    ok &= expect(
        !snapshot.is_guild_offline_protected("GUILD_B"),
        "online guild remains unprotected");

    std::filesystem::remove(root / "guild_protection.tsv");
    error.clear();
    ok &= expect(
        !snapshot.refresh_if_changed(error),
        "missing protection snapshot is rejected");
    ok &= expect(
        error.find("cannot open") != std::string::npos,
        "missing protection snapshot reports a useful error");
    ok &= expect(
        snapshot.is_guild_offline_protected("GUILD_A"),
        "last valid protection remains loaded after refresh failure");
    write_file(
        root / "guild_protection.tsv",
        "guild_key\tonline_count\tlast_online_at\tlast_hostile_at\tprotected_at\tprotected\treason\n"
        "GUILD_A\t0\t1000\t2000\t3200\ttrue\tOFFLINE_PROTECTED\n"
        "GUILD_B\t1\t3200\t0\t0\tfalse\tONLINE\n");
    error.clear();
    ok &= expect(snapshot.refresh_if_changed(error), "restored snapshot reloads");

    const auto active_flag = snapshot.evaluate_conquest_flag_damage(
        "11111111-1111-1111-1111-111111111111",
        "GUILD_B");
    ok &= expect(active_flag.handled, "registered conquest flag handled");
    ok &= expect(!active_flag.block, "active conquest attacker allowed");
    ok &= expect(
        active_flag.reason == "ACTIVE_CONQUEST_TARGET",
        "active conquest reason preserved");

    const auto wrong_flag_attacker = snapshot.evaluate_conquest_flag_damage(
        "11111111111111111111111111111111",
        "GUILD_C");
    ok &= expect(wrong_flag_attacker.block, "wrong attacker blocked on target flag");

    const auto unresolved_flag_attacker = snapshot.evaluate_conquest_flag_damage(
        "11111111111111111111111111111111",
        "");
    ok &= expect(
        unresolved_flag_attacker.block,
        "unresolved player attacker fails closed on registered flag");

    const auto same_guild_flag = snapshot.evaluate_conquest_flag_damage(
        "11111111111111111111111111111111",
        "GUILD_A");
    ok &= expect(!same_guild_flag.block, "same guild remains game controlled");

    const auto inactive_flag = snapshot.evaluate_conquest_flag_damage(
        "22222222222222222222222222222222",
        "GUILD_B");
    ok &= expect(inactive_flag.block, "inactive conquest flag protected");

    const auto ordinary_structure = snapshot.evaluate_conquest_flag_damage(
        "33333333333333333333333333333333",
        "GUILD_B");
    ok &= expect(!ordinary_structure.handled, "ordinary structure not handled");
    ok &= expect(
        snapshot.is_conquest_flag("11111111-1111-1111-1111-111111111111"),
        "registered conquest flag recognized for dispose hook");
    ok &= expect(
        !snapshot.is_conquest_flag("33333333333333333333333333333333"),
        "ordinary structure ignored by dispose hook");

    const auto active_zone = snapshot.evaluate_conquest_zone_damage(
        "GUILD_A",
        "GUILD_B",
        16000,
        2000,
        3000);
    ok &= expect(active_zone.allow, "active conquest zone boundary allows");
    ok &= expect(
        active_zone.reason == "ACTIVE_CONQUEST_ZONE",
        "active conquest zone reason preserved");
    ok &= expect(
        active_zone.node_id == "NODE_A",
        "active conquest node preserved");
    ok &= expect(
        !snapshot.evaluate_conquest_zone_damage(
            "GUILD_A", "GUILD_B", 16001, 2000, 3000).allow,
        "outside conquest zone does not allow");
    ok &= expect(
        !snapshot.evaluate_conquest_zone_damage(
            "GUILD_A", "GUILD_C", 1000, 2000, 3000).allow,
        "wrong attacker does not get conquest exception");
    ok &= expect(
        !snapshot.evaluate_conquest_zone_damage(
            "GUILD_C", "GUILD_B", 1000, 2000, 3000).allow,
        "wrong target does not get conquest exception");
    ok &= expect(
        !snapshot.evaluate_conquest_zone_damage(
            "GUILD_A", "GUILD_C", 0, 0, 0).allow,
        "overflowing conquest radius fails closed");

    const auto offline_external = snapshot.evaluate_protected_guilds(
        "GUILD_A",
        "GUILD_C",
        true,
        false);
    ok &= expect(offline_external.block, "offline guild blocks external damage");
    ok &= expect(
        offline_external.reason == "OFFLINE_PROTECTION",
        "offline protection reason preserved");

    const auto offline_wild = snapshot.evaluate_protected_guilds(
        "GUILD_A",
        "",
        true,
        false);
    ok &= expect(offline_wild.block, "offline guild blocks wild attacker damage");

    const auto offline_environment = snapshot.evaluate_protected_guilds(
        "GUILD_A",
        "",
        false,
        false);
    ok &= expect(
        !offline_environment.block,
        "environmental damage remains game controlled");

    const auto offline_same_guild = snapshot.evaluate_protected_guilds(
        "GUILD_A",
        "GUILD_A",
        true,
        false);
    ok &= expect(
        !offline_same_guild.block,
        "same guild damage remains game controlled");

    const auto protected_ai_actor = snapshot.evaluate_protected_guilds(
        "GUILD_C",
        "GUILD_A",
        true,
        true);
    ok &= expect(
        protected_ai_actor.block,
        "protected Pal does not acquire external AI target");

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
    write_file(
        root / "guild_protection.tsv",
        "guild_key\tonline_count\tlast_online_at\tlast_hostile_at\tprotected_at\tprotected\treason\n"
        "GUILD_A\t1\t3400\t2200\t0\tfalse\tONLINE\n");
    ok &= expect(snapshot.refresh_if_changed(error), "changed snapshot reloads");
    const auto ended = snapshot.evaluate_alliance_structure_damage(
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB");
    ok &= expect(!ended.block, "ended alliance allows after reload");
    ok &= expect(
        !snapshot.is_guild_offline_protected("GUILD_A"),
        "offline protection clears after reload");

    write_file(
        root / "player_registry.tsv",
        "wrong_header\n");
    error.clear();
    ok &= expect(
        !snapshot.refresh_if_changed(error),
        "invalid registry header is rejected");
    ok &= expect(
        error.find("invalid registry snapshot header") != std::string::npos,
        "invalid registry header reports a useful error");
    ok &= expect(
        snapshot.guild_for_player_uid("AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA") == "GUILD_A",
        "last valid registry remains loaded after invalid refresh");

    const auto activity_path = root / "guild_combat_activity.tsv";
    PalTR::ProtectionActivityStore activity(activity_path);
    ok &= expect(
        activity.record("GUILD_A", 100, error),
        "first combat activity records");
    ok &= expect(
        activity.last_hostile_at("GUILD_A") == 100,
        "first combat activity retained");
    ok &= expect(
        activity.record("GUILD_A", 103, error),
        "rapid combat activity throttles cleanly");
    ok &= expect(
        activity.last_hostile_at("GUILD_A") == 103,
        "throttled combat activity retained in memory");
    ok &= expect(
        activity.record("GUILD_A", 108, error),
        "later combat activity persists");

    PalTR::ProtectionActivityStore reloaded_activity(activity_path);
    ok &= expect(
        reloaded_activity.record("GUILD_B", 200, error),
        "combat activity file reloads");
    ok &= expect(
        reloaded_activity.last_hostile_at("GUILD_A") == 108,
        "persisted combat activity survives reload");

    std::error_code cleanup_error;
    std::filesystem::remove_all(root, cleanup_error);
    return ok ? 0 : 1;
}
