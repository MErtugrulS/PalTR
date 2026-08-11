#include "PolicySnapshot.hpp"

#include <DynamicOutput/Output.hpp>
#include <Mod/CppUserModBase.hpp>
#include <Unreal/CoreUObject/UObject/Class.hpp>
#include <Unreal/CoreUObject/UObject/UnrealType.hpp>
#include <Unreal/Hooks/Hooks.hpp>
#include <Unreal/UObject.hpp>
#include <Unreal/UObjectGlobals.hpp>
#include <Unreal/UnrealCoreStructs.hpp>

#include <iomanip>
#include <exception>
#include <sstream>
#include <string>
#include <unordered_map>

namespace
{
    constexpr auto damage_function_path =
        STR("/Script/Pal.PalNetworkMapObjectComponent:RequestDamageMapObject_ToServer");
    constexpr auto model_class_path = STR("/Script/Pal.PalMapObjectModel");
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
            : m_policy(data_root)
        {
            ModVersion = STR("0.1.0");
            ModName = STR("PalTRStructureGuard");
            ModAuthors = STR("PalTR");
            ModDescription = STR("Blocks allied guild structure damage on the server");
        }

        ~StructureGuard() override
        {
            if (m_hook_id != Hook::ERROR_ID)
            {
                Hook::UnregisterCallback(m_hook_id);
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

            m_hook_id = Hook::RegisterProcessEventPreCallback(
                [this](Hook::TCallbackIterationData<void>& hook,
                       UObject*,
                       UFunction* function,
                       void* parameters) {
                    if (function == m_damage_function)
                    {
                        handle_damage_request(hook, parameters);
                    }
                },
                {false, false, STR("PalTRStructureGuard"), STR("AlliedStructureDamage")});

            if (m_hook_id == Hook::ERROR_ID)
            {
                Output::send<LogLevel::Error>(
                    STR("[PalTRStructureGuard] ProcessEvent pre-hook registration failed.\n"));
                return;
            }

            Output::send<LogLevel::Warning>(
                STR("[PalTRStructureGuard] Allied structure damage guard registered.\n"));
        }

    private:
        bool resolve_contract()
        {
            m_damage_function = UObjectGlobals::StaticFindObject<UFunction*>(
                nullptr,
                nullptr,
                damage_function_path);
            m_model_class = UObjectGlobals::StaticFindObject<UClass*>(
                nullptr,
                nullptr,
                model_class_path);

            if (m_damage_function == nullptr || m_model_class == nullptr)
            {
                return false;
            }

            m_instance_id_parameter = m_damage_function->FindProperty(
                FName(STR("InstanceId"), FNAME_Find));
            m_info_parameter = CastField<FStructProperty>(
                m_damage_function->FindProperty(FName(STR("Info"), FNAME_Find)));
            m_model_instance_property = m_model_class->FindProperty(
                FName(STR("InstanceId"), FNAME_Find));
            m_build_player_property = m_model_class->FindProperty(
                FName(STR("BuildPlayerUId"), FNAME_Find));

            if (m_instance_id_parameter == nullptr
                || m_info_parameter == nullptr
                || m_model_instance_property == nullptr
                || m_build_player_property == nullptr)
            {
                return false;
            }

            auto* info_struct = ToRawPtr(m_info_parameter->GetStruct());
            if (info_struct == nullptr)
            {
                return false;
            }

            if (!is_guid_property(m_instance_id_parameter)
                || !is_guid_property(m_model_instance_property)
                || !is_guid_property(m_build_player_property)
                || info_struct->GetName() != STR("PalDamageInfo"))
            {
                return false;
            }

            m_attacker_group_property = info_struct->FindProperty(
                FName(STR("AttackerGroupID"), FNAME_Find));
            m_attacker_property = info_struct->FindProperty(
                FName(STR("Attacker"), FNAME_Find));

            return is_guid_property(m_attacker_group_property)
                && CastField<FObjectPropertyBase>(m_attacker_property) != nullptr;
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

        void handle_damage_request(
            Hook::TCallbackIterationData<void>& hook,
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

                auto* const* attacker_slot =
                    m_attacker_property->ContainerPtrToValuePtr<UObject*>(info);
                UObject* attacker = attacker_slot == nullptr ? nullptr : *attacker_slot;
                if (attacker == nullptr
                    || !attacker->GetFullName().contains(STR("BP_Player_")))
                {
                    return;
                }

                const auto* attacker_group =
                    m_attacker_group_property->ContainerPtrToValuePtr<FGuid>(info);
                if (attacker_group == nullptr || !attacker_group->is_valid())
                {
                    return;
                }

                const auto build_player_uid = resolve_build_player(*instance_id);
                if (build_player_uid.empty())
                {
                    return;
                }

                std::string error;
                if (!m_policy.refresh_if_changed(error))
                {
                    Output::send<LogLevel::Error>(
                        STR("[PalTRStructureGuard] Policy refresh failed: {}\n"),
                        unreal_text(error));
                    return;
                }

                const auto decision = m_policy.evaluate_alliance_structure_damage(
                    build_player_uid,
                    guid_text(*attacker_group));
                if (!decision.block)
                {
                    return;
                }

                hook.PreventOriginalFunctionCall();
                Output::send<LogLevel::Warning>(
                    STR("[PalTRStructureGuard] Blocked allied structure damage: attacker={} target={} reason={}\n"),
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
        Hook::GlobalCallbackId m_hook_id{Hook::ERROR_ID};
        UFunction* m_damage_function{};
        UClass* m_model_class{};
        FProperty* m_instance_id_parameter{};
        FStructProperty* m_info_parameter{};
        FProperty* m_attacker_group_property{};
        FProperty* m_attacker_property{};
        FProperty* m_model_instance_property{};
        FProperty* m_build_player_property{};
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
