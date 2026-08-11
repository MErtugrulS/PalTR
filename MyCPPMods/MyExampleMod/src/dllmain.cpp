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
                       UObject* context,
                       UFunction* function,
                       void* parameters) {
                    if (function == m_damage_function)
                    {
                        handle_damage_request(hook, context, parameters);
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
                || m_model_class == nullptr
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
            m_model_instance_property = m_model_class->FindProperty(
                FName(STR("InstanceId"), FNAME_Find));
            m_build_player_property = m_model_class->FindProperty(
                FName(STR("BuildPlayerUId"), FNAME_Find));
            m_controller_pawn_property = m_controller_class->FindProperty(
                FName(STR("Pawn"), FNAME_Find));
            m_controller_transmitter_property = m_player_controller_class->FindProperty(
                FName(STR("Transmitter"), FNAME_Find));

            if (m_instance_id_parameter == nullptr
                || m_info_parameter == nullptr
                || m_model_instance_property == nullptr
                || m_build_player_property == nullptr
                || m_controller_pawn_property == nullptr
                || m_controller_transmitter_property == nullptr)
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
                || CastField<FObjectPropertyBase>(m_controller_pawn_property) == nullptr
                || CastField<FObjectPropertyBase>(m_controller_transmitter_property) == nullptr
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

                const auto pawn_name = pawn->GetFullName();
                const auto decision = m_policy.evaluate_alliance_structure_damage_by_pawn(
                    build_player_uid,
                    ascii_text(pawn_name));
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
        UClass* m_player_controller_class{};
        UClass* m_network_transmitter_class{};
        UClass* m_controller_class{};
        FProperty* m_instance_id_parameter{};
        FStructProperty* m_info_parameter{};
        FProperty* m_attacker_group_property{};
        FProperty* m_attacker_property{};
        FProperty* m_model_instance_property{};
        FProperty* m_build_player_property{};
        FProperty* m_controller_pawn_property{};
        FProperty* m_controller_transmitter_property{};
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
