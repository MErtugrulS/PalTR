#include "PolicySnapshot.hpp"
#include "ProtectionActivity.hpp"

#include <DynamicOutput/Output.hpp>
#include <Mod/CppUserModBase.hpp>
#include <Unreal/CoreUObject/UObject/Class.hpp>
#include <Unreal/CoreUObject/UObject/UnrealType.hpp>
#include <Unreal/Hooks/Hooks.hpp>
#include <Unreal/UObject.hpp>
#include <Unreal/UObjectGlobals.hpp>
#include <Unreal/UnrealCoreStructs.hpp>

#include <chrono>
#include <iomanip>
#include <exception>
#include <sstream>
#include <string>
#include <unordered_map>

namespace
{
    constexpr auto damage_function_path =
        STR("/Script/Pal.PalNetworkMapObjectComponent:RequestDamageMapObject_ToServer");
    constexpr auto npc_damage_function_path =
        STR("/Script/Pal.PalPlayerController:DamageReactionComponent_ProcessDamage_ToServer_ToNPC");
    constexpr auto enemy_player_damage_function_path =
        STR("/Script/Pal.PalPlayerController:DamageReactionComponent_ProcessDamage_ToServer_ToEnemyPlayer");
    constexpr auto is_enemy_function_path = STR("/Script/Pal.PalUtility:IsEnemy");
    constexpr auto nearest_enemy_build_function_path =
        STR("/Script/Pal.PalUtility:GetNearestEnemyBuildObject");
    constexpr auto model_class_path = STR("/Script/Pal.PalMapObjectModel");
    constexpr auto map_object_class_path = STR("/Script/Pal.PalMapObject");
    constexpr auto pal_character_class_path = STR("/Script/Pal.PalCharacter");
    constexpr auto character_parameter_component_class_path =
        STR("/Script/Pal.PalCharacterParameterComponent");
    constexpr auto individual_parameter_class_path =
        STR("/Script/Pal.PalIndividualCharacterParameter");
    constexpr auto player_controller_class_path = STR("/Script/Pal.PalPlayerController");
    constexpr auto network_transmitter_class_path = STR("/Script/Pal.PalNetworkTransmitter");
    constexpr auto controller_class_path = STR("/Script/Engine.Controller");
    constexpr auto data_root = "C:/PalTR-Dev/Data";

    std::string guid_text(const RC::Unreal::FGuid& guid)
    {
        std::ostringstream stream;
        stream << std::uppercase << std::hex << std::setfill('0')
               << std::setw(8) << guid.A
               << std::setw(8) << guid.B
               << std::setw(8) << guid.C
               << std::setw(8) << guid.D;
        return stream.str();
    }

    RC::StringType unreal_text(const std::string& value)
    {
        return RC::StringType(value.begin(), value.end());
    }

    std::string ascii_text(const RC::StringType& value)
    {
        std::string result;
        result.reserve(value.size());
        for (const auto character : value)
        {
            if (static_cast<unsigned int>(character) > 0x7F)
            {
                return {};
            }
            result.push_back(static_cast<char>(character));
        }
        return result;
    }

    bool is_guid_property(RC::Unreal::FProperty* property)
    {
        auto* struct_property = RC::Unreal::CastField<RC::Unreal::FStructProperty>(property);
        if (struct_property == nullptr)
        {
            return false;
        }

        auto* script_struct = RC::Unreal::ToRawPtr(struct_property->GetStruct());
        return script_struct != nullptr
            && script_struct->GetName() == STR("Guid");
    }
}

namespace PalTR
{
    using namespace RC;
    using namespace RC::Unreal;

    class StructureGuard final : public CppUserModBase
    {
    public:
        StructureGuard()
            : m_policy(data_root),
              m_activity(std::filesystem::path(data_root) / "guild_combat_activity.tsv")
        {
            ModVersion = STR("0.3.0");
            ModName = STR("PalTRStructureGuard");
            ModAuthors = STR("PalTR");
            ModDescription = STR("Blocks allied and offline-protected guild damage on the server");
        }

        ~StructureGuard() override
        {
            if (m_pre_hook_id != Hook::ERROR_ID)
            {
                Hook::UnregisterCallback(m_pre_hook_id);
            }
            if (m_post_hook_id != Hook::ERROR_ID)
            {
                Hook::UnregisterCallback(m_post_hook_id);
            }
        }

        auto on_unreal_init() -> void override
        {
            if (!resolve_contract())
            {
                Output::send<LogLevel::Error>(
                    STR("[PalTRStructureGuard] Verified reflection contract was not found; guard disabled.\n"));
                return;
            }

            rebuild_model_index();
            ensure_policy_current(true);

            m_pre_hook_id = Hook::RegisterProcessEventPreCallback(
                [this](Hook::TCallbackIterationData<void>& hook,
                       UObject* context,
                       UFunction* function,
                       void* parameters) {
                    if (function == m_damage_function)
                    {
                        handle_damage_request(hook, context, parameters);
                    }
                    else if (function == m_is_enemy_function)
                    {
                        handle_is_enemy(hook, parameters);
                    }
                    else if (function == m_npc_damage_function)
                    {
                        handle_character_damage(
                            hook,
                            parameters,
                            m_npc_damage_info_parameter,
                            m_npc_damage_defender_parameter);
                    }
                    else if (function == m_enemy_player_damage_function)
                    {
                        handle_character_damage(
                            hook,
                            parameters,
                            m_enemy_player_damage_info_parameter,
                            m_enemy_player_damage_defender_parameter);
                    }
                },
                {false, false, STR("PalTRStructureGuard"), STR("ProtectedDamagePre")});

            if (m_pre_hook_id == Hook::ERROR_ID)
            {
                Output::send<LogLevel::Error>(
                    STR("[PalTRStructureGuard] ProcessEvent pre-hook registration failed.\n"));
                return;
            }

            m_post_hook_id = Hook::RegisterProcessEventPostCallback(
                [this](Hook::TCallbackIterationData<void>&,
                       UObject*,
                       UFunction* function,
                       void* parameters) {
                    if (function == m_nearest_enemy_build_function)
                    {
                        handle_nearest_enemy_build_result(parameters);
                    }
                },
                {false, false, STR("PalTRStructureGuard"), STR("ProtectedTargetingPost")});

            if (m_post_hook_id == Hook::ERROR_ID)
            {
                Hook::UnregisterCallback(m_pre_hook_id);
                m_pre_hook_id = Hook::ERROR_ID;
                Output::send<LogLevel::Error>(
                    STR("[PalTRStructureGuard] ProcessEvent post-hook registration failed.\n"));
                return;
            }

            Output::send<LogLevel::Warning>(
                STR("[PalTRStructureGuard] Allied and offline protection guard registered.\n"));
        }

    private:
        bool resolve_contract()
        {
            m_damage_function = UObjectGlobals::StaticFindObject<UFunction*>(
                nullptr,
                nullptr,
                damage_function_path);
            m_npc_damage_function = UObjectGlobals::StaticFindObject<UFunction*>(
                nullptr,
                nullptr,
                npc_damage_function_path);
            m_enemy_player_damage_function = UObjectGlobals::StaticFindObject<UFunction*>(
                nullptr,
                nullptr,
                enemy_player_damage_function_path);
            m_is_enemy_function = UObjectGlobals::StaticFindObject<UFunction*>(
                nullptr,
                nullptr,
                is_enemy_function_path);
            m_nearest_enemy_build_function = UObjectGlobals::StaticFindObject<UFunction*>(
                nullptr,
                nullptr,
                nearest_enemy_build_function_path);
            m_model_class = UObjectGlobals::StaticFindObject<UClass*>(
                nullptr,
                nullptr,
                model_class_path);
            m_map_object_class = UObjectGlobals::StaticFindObject<UClass*>(
                nullptr,
                nullptr,
                map_object_class_path);
            m_pal_character_class = UObjectGlobals::StaticFindObject<UClass*>(
                nullptr,
                nullptr,
                pal_character_class_path);
            m_character_parameter_component_class = UObjectGlobals::StaticFindObject<UClass*>(
                nullptr,
                nullptr,
                character_parameter_component_class_path);
            m_individual_parameter_class = UObjectGlobals::StaticFindObject<UClass*>(
                nullptr,
                nullptr,
                individual_parameter_class_path);
            m_player_controller_class = UObjectGlobals::StaticFindObject<UClass*>(
                nullptr,
                nullptr,
                player_controller_class_path);
            m_network_transmitter_class = UObjectGlobals::StaticFindObject<UClass*>(
                nullptr,
                nullptr,
                network_transmitter_class_path);
            m_controller_class = UObjectGlobals::StaticFindObject<UClass*>(
                nullptr,
                nullptr,
                controller_class_path);

            if (m_damage_function == nullptr
                || m_npc_damage_function == nullptr
                || m_enemy_player_damage_function == nullptr
                || m_is_enemy_function == nullptr
                || m_nearest_enemy_build_function == nullptr
                || m_model_class == nullptr
                || m_map_object_class == nullptr
                || m_pal_character_class == nullptr
                || m_character_parameter_component_class == nullptr
                || m_individual_parameter_class == nullptr
                || m_player_controller_class == nullptr
                || m_network_transmitter_class == nullptr
                || m_controller_class == nullptr)
            {
                return false;
            }

            m_instance_id_parameter = m_damage_function->FindProperty(
                FName(STR("InstanceId"), FNAME_Find));
            m_info_parameter = CastField<FStructProperty>(
                m_damage_function->FindProperty(FName(STR("Info"), FNAME_Find)));
            m_npc_damage_info_parameter = CastField<FStructProperty>(
                m_npc_damage_function->FindProperty(FName(STR("Info"), FNAME_Find)));
            m_npc_damage_defender_parameter = m_npc_damage_function->FindProperty(
                FName(STR("Defender"), FNAME_Find));
            m_enemy_player_damage_info_parameter = CastField<FStructProperty>(
                m_enemy_player_damage_function->FindProperty(FName(STR("Info"), FNAME_Find)));
            m_enemy_player_damage_defender_parameter =
                m_enemy_player_damage_function->FindProperty(
                    FName(STR("Defender"), FNAME_Find));
            m_is_enemy_actor_a_parameter = m_is_enemy_function->FindProperty(
                FName(STR("ActorA"), FNAME_Find));
            m_is_enemy_actor_b_parameter = m_is_enemy_function->FindProperty(
                FName(STR("ActorB"), FNAME_Find));
            m_is_enemy_return_parameter = CastField<FBoolProperty>(
                m_is_enemy_function->FindProperty(FName(STR("ReturnValue"), FNAME_Find)));
            m_nearest_enemy_build_character_parameter =
                m_nearest_enemy_build_function->FindProperty(
                    FName(STR("Character"), FNAME_Find));
            m_nearest_enemy_build_return_parameter =
                m_nearest_enemy_build_function->FindProperty(
                    FName(STR("ReturnValue"), FNAME_Find));
            m_model_instance_property = m_model_class->FindProperty(
                FName(STR("InstanceId"), FNAME_Find));
            m_build_player_property = m_model_class->FindProperty(
                FName(STR("BuildPlayerUId"), FNAME_Find));
            m_map_object_model_property = m_map_object_class->FindProperty(
                FName(STR("MapObjectModel"), FNAME_Find));
            m_character_parameter_component_property = m_pal_character_class->FindProperty(
                FName(STR("CharacterParameterComponent"), FNAME_Find));
            m_trainer_property = m_character_parameter_component_class->FindProperty(
                FName(STR("Trainer"), FNAME_Find));
            m_individual_parameter_property =
                m_character_parameter_component_class->FindProperty(
                    FName(STR("IndividualParameter"), FNAME_Find));
            m_save_parameter_property = CastField<FStructProperty>(
                m_individual_parameter_class->FindProperty(
                    FName(STR("SaveParameter"), FNAME_Find)));
            m_controller_pawn_property = m_controller_class->FindProperty(
                FName(STR("Pawn"), FNAME_Find));
            m_controller_transmitter_property = m_player_controller_class->FindProperty(
                FName(STR("Transmitter"), FNAME_Find));

            if (m_instance_id_parameter == nullptr
                || m_info_parameter == nullptr
                || m_npc_damage_info_parameter == nullptr
                || m_npc_damage_defender_parameter == nullptr
                || m_enemy_player_damage_info_parameter == nullptr
                || m_enemy_player_damage_defender_parameter == nullptr
                || m_is_enemy_actor_a_parameter == nullptr
                || m_is_enemy_actor_b_parameter == nullptr
                || m_is_enemy_return_parameter == nullptr
                || m_nearest_enemy_build_character_parameter == nullptr
                || m_nearest_enemy_build_return_parameter == nullptr
                || m_model_instance_property == nullptr
                || m_build_player_property == nullptr
                || m_map_object_model_property == nullptr
                || m_character_parameter_component_property == nullptr
                || m_trainer_property == nullptr
                || m_individual_parameter_property == nullptr
                || m_save_parameter_property == nullptr
                || m_controller_pawn_property == nullptr
                || m_controller_transmitter_property == nullptr)
            {
                return false;
            }

            auto* info_struct = ToRawPtr(m_info_parameter->GetStruct());
            auto* npc_info_struct = ToRawPtr(m_npc_damage_info_parameter->GetStruct());
            auto* enemy_player_info_struct =
                ToRawPtr(m_enemy_player_damage_info_parameter->GetStruct());
            auto* save_parameter_struct =
                ToRawPtr(m_save_parameter_property->GetStruct());
            if (info_struct == nullptr
                || npc_info_struct == nullptr
                || enemy_player_info_struct == nullptr
                || save_parameter_struct == nullptr)
            {
                return false;
            }

            if (!is_guid_property(m_instance_id_parameter)
                || !is_guid_property(m_model_instance_property)
                || !is_guid_property(m_build_player_property)
                || CastField<FObjectPropertyBase>(m_npc_damage_defender_parameter) == nullptr
                || CastField<FObjectPropertyBase>(m_enemy_player_damage_defender_parameter) == nullptr
                || CastField<FObjectPropertyBase>(m_is_enemy_actor_a_parameter) == nullptr
                || CastField<FObjectPropertyBase>(m_is_enemy_actor_b_parameter) == nullptr
                || CastField<FObjectPropertyBase>(m_nearest_enemy_build_character_parameter) == nullptr
                || CastField<FObjectPropertyBase>(m_nearest_enemy_build_return_parameter) == nullptr
                || CastField<FObjectPropertyBase>(m_map_object_model_property) == nullptr
                || CastField<FObjectPropertyBase>(m_character_parameter_component_property) == nullptr
                || CastField<FObjectPropertyBase>(m_trainer_property) == nullptr
                || CastField<FObjectPropertyBase>(m_individual_parameter_property) == nullptr
                || CastField<FObjectPropertyBase>(m_controller_pawn_property) == nullptr
                || CastField<FObjectPropertyBase>(m_controller_transmitter_property) == nullptr
                || info_struct->GetName() != STR("PalDamageInfo")
                || npc_info_struct->GetName() != STR("PalDamageInfo")
                || enemy_player_info_struct->GetName() != STR("PalDamageInfo")
                || save_parameter_struct->GetName() != STR("PalIndividualCharacterSaveParameter"))
            {
                return false;
            }

            m_attacker_group_property = info_struct->FindProperty(
                FName(STR("AttackerGroupID"), FNAME_Find));
            m_attacker_property = info_struct->FindProperty(
                FName(STR("Attacker"), FNAME_Find));
            m_override_network_owner_property = info_struct->FindProperty(
                FName(STR("OverrideNetworkOwner"), FNAME_Find));
            m_owner_player_uid_property = save_parameter_struct->FindProperty(
                FName(STR("OwnerPlayerUId"), FNAME_Find));

            return is_guid_property(m_attacker_group_property)
                && CastField<FObjectPropertyBase>(m_attacker_property) != nullptr
                && CastField<FObjectPropertyBase>(m_override_network_owner_property) != nullptr
                && is_guid_property(m_owner_player_uid_property);
        }

        bool ensure_policy_current(bool force = false)
        {
            const auto now = std::chrono::steady_clock::now();
            if (!force
                && m_policy_refresh_attempted
                && now - m_last_policy_refresh < std::chrono::seconds(1))
            {
                return m_policy_loaded;
            }

            m_policy_refresh_attempted = true;
            m_last_policy_refresh = now;

            std::string error;
            if (!m_policy.refresh_if_changed(error))
            {
                m_policy_loaded = false;
                if (error != m_last_policy_error)
                {
                    m_last_policy_error = error;
                    Output::send<LogLevel::Error>(
                        STR("[PalTRStructureGuard] Policy refresh failed; guard failing open: {}\n"),
                        unreal_text(error));
                }
                return false;
            }

            m_policy_loaded = true;
            m_last_policy_error.clear();
            return true;
        }

        std::string resolve_actor_guild(UObject* actor)
        {
            if (actor == nullptr)
            {
                return {};
            }

            auto guild = m_policy.guild_for_pawn_path(ascii_text(actor->GetFullName()));
            if (!guild.empty())
            {
                return guild;
            }

            if (actor->IsA(m_map_object_class))
            {
                auto* const* model_slot =
                    m_map_object_model_property->ContainerPtrToValuePtr<UObject*>(actor);
                UObject* model = model_slot == nullptr ? nullptr : *model_slot;
                if (model == nullptr || !model->IsA(m_model_class))
                {
                    return {};
                }

                const auto* build_player_uid =
                    m_build_player_property->ContainerPtrToValuePtr<FGuid>(model);
                return build_player_uid != nullptr && build_player_uid->is_valid()
                    ? m_policy.guild_for_player_uid(guid_text(*build_player_uid))
                    : std::string{};
            }

            if (!actor->IsA(m_pal_character_class))
            {
                return {};
            }

            auto* const* component_slot =
                m_character_parameter_component_property->ContainerPtrToValuePtr<UObject*>(actor);
            UObject* component = component_slot == nullptr ? nullptr : *component_slot;
            if (component == nullptr || !component->IsA(m_character_parameter_component_class))
            {
                return {};
            }

            auto* const* trainer_slot =
                m_trainer_property->ContainerPtrToValuePtr<UObject*>(component);
            UObject* trainer = trainer_slot == nullptr ? nullptr : *trainer_slot;
            if (trainer != nullptr)
            {
                guild = m_policy.guild_for_pawn_path(ascii_text(trainer->GetFullName()));
                if (!guild.empty())
                {
                    return guild;
                }
            }

            auto* const* individual_slot =
                m_individual_parameter_property->ContainerPtrToValuePtr<UObject*>(component);
            UObject* individual = individual_slot == nullptr ? nullptr : *individual_slot;
            if (individual == nullptr || !individual->IsA(m_individual_parameter_class))
            {
                return {};
            }

            void* save_parameter =
                m_save_parameter_property->ContainerPtrToValuePtr<void>(individual);
            const auto* owner_player_uid = save_parameter == nullptr
                ? nullptr
                : m_owner_player_uid_property->ContainerPtrToValuePtr<FGuid>(save_parameter);
            return owner_player_uid != nullptr && owner_player_uid->is_valid()
                ? m_policy.guild_for_player_uid(guid_text(*owner_player_uid))
                : std::string{};
        }

        AllianceDecision evaluate_actor_interaction(
            UObject* attacker,
            UObject* target,
            bool protect_either = false)
        {
            if (!ensure_policy_current())
            {
                return {};
            }

            const auto attacker_guild = resolve_actor_guild(attacker);
            const auto target_guild = resolve_actor_guild(target);
            return m_policy.evaluate_protected_guilds(
                target_guild,
                attacker_guild,
                attacker != nullptr,
                protect_either);
        }

        void record_hostile_activity(
            const std::string& attacker_guild,
            const std::string& target_guild,
            bool attacker_present)
        {
            if (!attacker_present
                || target_guild.empty()
                || attacker_guild == target_guild)
            {
                return;
            }

            const auto now = std::chrono::duration_cast<std::chrono::seconds>(
                std::chrono::system_clock::now().time_since_epoch()).count();
            std::string error;
            if (!m_activity.record(target_guild, now, error)
                && error != m_last_activity_error)
            {
                m_last_activity_error = error;
                Output::send<LogLevel::Error>(
                    STR("[PalTRStructureGuard] Combat activity write failed: {}\n"),
                    unreal_text(error));
            }
            else if (error.empty())
            {
                m_last_activity_error.clear();
            }
        }

        void rebuild_model_index()
        {
            std::unordered_map<std::string, std::string> new_index;

            UObjectGlobals::ForEachUObject(
                [this, &new_index](UObject* object, ...) -> LoopAction {
                    if (object == nullptr || !object->IsA(m_model_class))
                    {
                        return LoopAction::Continue;
                    }

                    const auto* instance_id =
                        m_model_instance_property->ContainerPtrToValuePtr<FGuid>(object);
                    const auto* build_player_uid =
                        m_build_player_property->ContainerPtrToValuePtr<FGuid>(object);

                    if (instance_id != nullptr
                        && build_player_uid != nullptr
                        && instance_id->is_valid()
                        && build_player_uid->is_valid())
                    {
                        new_index[guid_text(*instance_id)] = guid_text(*build_player_uid);
                    }

                    return LoopAction::Continue;
                });

            m_build_player_by_instance = std::move(new_index);
        }

        std::string resolve_build_player(const FGuid& instance_id)
        {
            const auto key = guid_text(instance_id);
            auto found = m_build_player_by_instance.find(key);
            if (found != m_build_player_by_instance.end())
            {
                return found->second;
            }

            rebuild_model_index();
            found = m_build_player_by_instance.find(key);
            return found == m_build_player_by_instance.end()
                ? std::string{}
                : found->second;
        }

        UObject* resolve_request_controller(UObject* context)
        {
            UObject* transmitter = context == nullptr
                ? nullptr
                : context->GetTypedOuter(m_network_transmitter_class);
            if (transmitter == nullptr)
            {
                return nullptr;
            }

            UObject* matched_controller = nullptr;
            UObjectGlobals::ForEachUObject(
                [this, transmitter, &matched_controller](UObject* object, ...) -> LoopAction {
                    if (object == nullptr || !object->IsA(m_player_controller_class))
                    {
                        return LoopAction::Continue;
                    }

                    auto* const* transmitter_slot =
                        m_controller_transmitter_property->ContainerPtrToValuePtr<UObject*>(object);
                    if (transmitter_slot != nullptr && *transmitter_slot == transmitter)
                    {
                        matched_controller = object;
                        return LoopAction::Break;
                    }

                    return LoopAction::Continue;
                });
            return matched_controller;
        }

        void handle_is_enemy(
            Hook::TCallbackIterationData<void>& hook,
            void* parameters)
        {
            if (parameters == nullptr)
            {
                return;
            }

            try
            {
                auto* const* actor_a_slot =
                    m_is_enemy_actor_a_parameter->ContainerPtrToValuePtr<UObject*>(parameters);
                auto* const* actor_b_slot =
                    m_is_enemy_actor_b_parameter->ContainerPtrToValuePtr<UObject*>(parameters);
                UObject* actor_a = actor_a_slot == nullptr ? nullptr : *actor_a_slot;
                UObject* actor_b = actor_b_slot == nullptr ? nullptr : *actor_b_slot;
                const auto decision = evaluate_actor_interaction(
                    actor_a,
                    actor_b,
                    true);
                if (!decision.block)
                {
                    return;
                }

                void* return_value =
                    m_is_enemy_return_parameter->ContainerPtrToValuePtr<void>(parameters);
                if (return_value == nullptr)
                {
                    return;
                }

                m_is_enemy_return_parameter->SetPropertyValue(return_value, false);
                hook.PreventOriginalFunctionCall();
            }
            catch (const std::exception& exception)
            {
                Output::send<LogLevel::Error>(
                    STR("[PalTRStructureGuard] IsEnemy hook failed open: {}\n"),
                    unreal_text(exception.what()));
            }
        }

        void handle_nearest_enemy_build_result(void* parameters)
        {
            if (parameters == nullptr)
            {
                return;
            }

            try
            {
                auto* const* character_slot =
                    m_nearest_enemy_build_character_parameter->ContainerPtrToValuePtr<UObject*>(
                        parameters);
                auto** return_slot =
                    m_nearest_enemy_build_return_parameter->ContainerPtrToValuePtr<UObject*>(
                        parameters);
                UObject* character = character_slot == nullptr ? nullptr : *character_slot;
                UObject* build_object = return_slot == nullptr ? nullptr : *return_slot;
                if (return_slot != nullptr
                    && evaluate_actor_interaction(character, build_object).block)
                {
                    *return_slot = nullptr;
                }
            }
            catch (const std::exception& exception)
            {
                Output::send<LogLevel::Error>(
                    STR("[PalTRStructureGuard] Build target hook failed open: {}\n"),
                    unreal_text(exception.what()));
            }
        }

        void handle_character_damage(
            Hook::TCallbackIterationData<void>& hook,
            void* parameters,
            FStructProperty* info_parameter,
            FProperty* defender_parameter)
        {
            if (parameters == nullptr || info_parameter == nullptr || defender_parameter == nullptr)
            {
                return;
            }

            try
            {
                void* info = info_parameter->ContainerPtrToValuePtr<void>(parameters);
                auto* const* defender_slot =
                    defender_parameter->ContainerPtrToValuePtr<UObject*>(parameters);
                if (info == nullptr || defender_slot == nullptr || *defender_slot == nullptr)
                {
                    return;
                }

                auto* const* attacker_slot =
                    m_attacker_property->ContainerPtrToValuePtr<UObject*>(info);
                auto* const* owner_slot =
                    m_override_network_owner_property->ContainerPtrToValuePtr<UObject*>(info);
                UObject* attacker = attacker_slot == nullptr ? nullptr : *attacker_slot;
                UObject* network_owner = owner_slot == nullptr ? nullptr : *owner_slot;
                if (attacker == nullptr)
                {
                    attacker = network_owner;
                }

                if (!ensure_policy_current())
                {
                    return;
                }

                auto attacker_guild = resolve_actor_guild(attacker);
                if (attacker_guild.empty()
                    && network_owner != nullptr
                    && network_owner != attacker)
                {
                    attacker_guild = resolve_actor_guild(network_owner);
                }
                const auto target_guild = resolve_actor_guild(*defender_slot);
                const bool attacker_present = attacker != nullptr || network_owner != nullptr;
                const auto decision = m_policy.evaluate_protected_guilds(
                    target_guild,
                    attacker_guild,
                    attacker_present,
                    false);
                if (!decision.block)
                {
                    record_hostile_activity(
                        attacker_guild,
                        target_guild,
                        attacker_present);
                    return;
                }

                hook.PreventOriginalFunctionCall();
                Output::send<LogLevel::Warning>(
                    STR("[PalTRStructureGuard] Blocked protected character damage: attacker={} target={} reason={}\n"),
                    unreal_text(decision.attacker_guild_key),
                    unreal_text(decision.target_guild_key),
                    unreal_text(decision.reason));
            }
            catch (const std::exception& exception)
            {
                Output::send<LogLevel::Error>(
                    STR("[PalTRStructureGuard] Character damage hook failed open: {}\n"),
                    unreal_text(exception.what()));
            }
        }

        void handle_damage_request(
            Hook::TCallbackIterationData<void>& hook,
            UObject* context,
            void* parameters)
        {
            if (parameters == nullptr)
            {
                return;
            }

            try
            {
                const auto* instance_id =
                    m_instance_id_parameter->ContainerPtrToValuePtr<FGuid>(parameters);
                void* info = m_info_parameter->ContainerPtrToValuePtr<void>(parameters);
                if (instance_id == nullptr || info == nullptr || !instance_id->is_valid())
                {
                    return;
                }

                if (context == nullptr)
                {
                    return;
                }

                UObject* controller = resolve_request_controller(context);
                if (controller == nullptr)
                {
                    return;
                }

                auto* const* pawn_slot =
                    m_controller_pawn_property->ContainerPtrToValuePtr<UObject*>(controller);
                UObject* pawn = pawn_slot == nullptr ? nullptr : *pawn_slot;
                if (pawn == nullptr || !pawn->GetFullName().contains(STR("BP_Player_")))
                {
                    return;
                }

                if (!ensure_policy_current())
                {
                    return;
                }

                const auto attacker_guild =
                    m_policy.guild_for_pawn_path(ascii_text(pawn->GetFullName()));
                const auto conquest = m_policy.evaluate_conquest_flag_damage(
                    guid_text(*instance_id),
                    attacker_guild);
                if (conquest.handled)
                {
                    if (conquest.block)
                    {
                        hook.PreventOriginalFunctionCall();
                        Output::send<LogLevel::Warning>(
                            STR("[PalTRStructureGuard] Blocked conquest flag damage: attacker={} target={} reason={}\n"),
                            unreal_text(conquest.attacker_guild_key),
                            unreal_text(conquest.target_guild_key),
                            unreal_text(conquest.reason));
                    }
                    else
                    {
                        record_hostile_activity(
                            conquest.attacker_guild_key,
                            conquest.target_guild_key,
                            true);
                    }
                    return;
                }

                const auto build_player_uid = resolve_build_player(*instance_id);
                if (build_player_uid.empty())
                {
                    return;
                }

                const auto target_guild =
                    m_policy.guild_for_player_uid(build_player_uid);
                const auto decision = m_policy.evaluate_protected_guilds(
                    target_guild,
                    attacker_guild,
                    true,
                    false);
                if (!decision.block)
                {
                    record_hostile_activity(
                        attacker_guild,
                        target_guild,
                        true);
                    return;
                }

                hook.PreventOriginalFunctionCall();
                Output::send<LogLevel::Warning>(
                    STR("[PalTRStructureGuard] Blocked protected structure damage: attacker={} target={} reason={}\n"),
                    unreal_text(decision.attacker_guild_key),
                    unreal_text(decision.target_guild_key),
                    unreal_text(decision.reason));
            }
            catch (const std::exception& exception)
            {
                Output::send<LogLevel::Error>(
                    STR("[PalTRStructureGuard] Damage hook failed open: {}\n"),
                    unreal_text(exception.what()));
            }
        }

        PolicySnapshot m_policy;
        ProtectionActivityStore m_activity;
        Hook::GlobalCallbackId m_pre_hook_id{Hook::ERROR_ID};
        Hook::GlobalCallbackId m_post_hook_id{Hook::ERROR_ID};
        UFunction* m_damage_function{};
        UFunction* m_npc_damage_function{};
        UFunction* m_enemy_player_damage_function{};
        UFunction* m_is_enemy_function{};
        UFunction* m_nearest_enemy_build_function{};
        UClass* m_model_class{};
        UClass* m_map_object_class{};
        UClass* m_pal_character_class{};
        UClass* m_character_parameter_component_class{};
        UClass* m_individual_parameter_class{};
        UClass* m_player_controller_class{};
        UClass* m_network_transmitter_class{};
        UClass* m_controller_class{};
        FProperty* m_instance_id_parameter{};
        FStructProperty* m_info_parameter{};
        FStructProperty* m_npc_damage_info_parameter{};
        FProperty* m_npc_damage_defender_parameter{};
        FStructProperty* m_enemy_player_damage_info_parameter{};
        FProperty* m_enemy_player_damage_defender_parameter{};
        FProperty* m_is_enemy_actor_a_parameter{};
        FProperty* m_is_enemy_actor_b_parameter{};
        FBoolProperty* m_is_enemy_return_parameter{};
        FProperty* m_nearest_enemy_build_character_parameter{};
        FProperty* m_nearest_enemy_build_return_parameter{};
        FProperty* m_attacker_group_property{};
        FProperty* m_attacker_property{};
        FProperty* m_override_network_owner_property{};
        FProperty* m_model_instance_property{};
        FProperty* m_build_player_property{};
        FProperty* m_map_object_model_property{};
        FProperty* m_character_parameter_component_property{};
        FProperty* m_trainer_property{};
        FProperty* m_individual_parameter_property{};
        FStructProperty* m_save_parameter_property{};
        FProperty* m_owner_player_uid_property{};
        FProperty* m_controller_pawn_property{};
        FProperty* m_controller_transmitter_property{};
        bool m_policy_refresh_attempted{};
        bool m_policy_loaded{};
        std::chrono::steady_clock::time_point m_last_policy_refresh{};
        std::string m_last_policy_error;
        std::string m_last_activity_error;
        std::unordered_map<std::string, std::string> m_build_player_by_instance;
    };
}

#define MOD_EXPORT __declspec(dllexport)

extern "C"
{
    MOD_EXPORT RC::CppUserModBase* start_mod()
    {
        return new PalTR::StructureGuard();
    }

    MOD_EXPORT void uninstall_mod(RC::CppUserModBase* mod)
    {
        delete mod;
    }
}
