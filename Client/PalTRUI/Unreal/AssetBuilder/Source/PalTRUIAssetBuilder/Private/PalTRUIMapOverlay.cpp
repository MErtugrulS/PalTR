#include "PalTRUIMapOverlay.h"

#include "AssetRegistry/AssetRegistryModule.h"
#include "Blueprint/UserWidget.h"
#include "Blueprint/WidgetBlueprintGeneratedClass.h"
#include "Blueprint/WidgetTree.h"
#include "Components/Border.h"
#include "Components/BorderSlot.h"
#include "Components/CanvasPanel.h"
#include "Components/CanvasPanelSlot.h"
#include "Components/HorizontalBox.h"
#include "Components/HorizontalBoxSlot.h"
#include "Components/SizeBox.h"
#include "Components/SizeBoxSlot.h"
#include "Components/TextBlock.h"
#include "Engine/Blueprint.h"
#include "Kismet2/BlueprintEditorUtils.h"
#include "Kismet2/KismetEditorUtilities.h"
#include "Misc/PackageName.h"
#include "UObject/Package.h"
#include "UObject/SavePackage.h"
#include "WidgetBlueprint.h"

namespace PalTRUIMapOverlay
{
    namespace
    {
        constexpr TCHAR PackageName[] =
            TEXT("/Game/Mods/PalTRUI/WBP_PalTRMapOverlay");
        constexpr TCHAR AssetName[] = TEXT("WBP_PalTRMapOverlay");
        constexpr int32 SegmentCount = 512;
        constexpr int32 NodeCount = 64;

        FLinearColor FromSRGB(
            const uint8 R,
            const uint8 G,
            const uint8 B,
            const float Alpha = 1.0f
        )
        {
            FLinearColor Result = FLinearColor::FromSRGBColor(
                FColor(R, G, B, 255)
            );
            Result.A = Alpha;
            return Result;
        }

        bool SaveAsset(UObject* Asset)
        {
            UPackage* Package = Asset ? Asset->GetOutermost() : nullptr;
            if (!Package)
            {
                return false;
            }

            Package->MarkPackageDirty();
            const FString Filename = FPackageName::LongPackageNameToFilename(
                Package->GetName(),
                FPackageName::GetAssetPackageExtension()
            );
            FSavePackageArgs SaveArgs;
            SaveArgs.TopLevelFlags = RF_Public | RF_Standalone;
            SaveArgs.SaveFlags = SAVE_NoError;
            SaveArgs.bWarnOfLongFilename = true;
            return UPackage::SavePackage(Package, Asset, *Filename, SaveArgs);
        }

        UBorder* MakeSolid(
            UWidgetTree* Tree,
            const FName Name,
            const FLinearColor Color
        )
        {
            UBorder* Border = Tree->ConstructWidget<UBorder>(
                UBorder::StaticClass(),
                Name
            );
            Border->bIsVariable = true;
            Border->SetBrushColor(Color);
            Border->SetPadding(FMargin(0.0f));
            Border->SetVisibility(ESlateVisibility::Collapsed);
            Border->SetRenderTransformPivot(FVector2D(0.5f, 0.5f));
            return Border;
        }

        UTextBlock* MakeLegendText(
            UWidgetTree* Tree,
            const FName Name,
            const TCHAR* Label,
            const FLinearColor Color
        )
        {
            UTextBlock* Text = Tree->ConstructWidget<UTextBlock>(
                UTextBlock::StaticClass(),
                Name
            );
            Text->SetText(FText::FromString(Label));
            Text->SetColorAndOpacity(FSlateColor(Color));
            FSlateFontInfo Font = Text->GetFont();
            Font.Size = 12;
            Text->SetFont(Font);
            return Text;
        }

        void AddLegendText(
            UHorizontalBox* Row,
            UTextBlock* Text,
            const FMargin Padding
        )
        {
            UHorizontalBoxSlot* Slot = Row->AddChildToHorizontalBox(Text);
            Slot->SetPadding(Padding);
            Slot->SetVerticalAlignment(VAlign_Center);
        }

        void AddPoolControl(
            UCanvasPanel* Root,
            UBorder* Control,
            const int32 ZOrder
        )
        {
            UCanvasPanelSlot* Slot = Root->AddChildToCanvas(Control);
            Slot->SetPosition(FVector2D::ZeroVector);
            Slot->SetSize(FVector2D(1.0f, 1.0f));
            Slot->SetAlignment(FVector2D::ZeroVector);
            Slot->SetZOrder(ZOrder);
        }

        bool EnsureNodeLabel(
            UWidgetTree* Tree,
            UCanvasPanel* Root,
            const int32 Index
        )
        {
            const FName FrameName(*FString::Printf(
                TEXT("TerritoryNodeLabel%03d"), Index
            ));
            const FName TextName(*FString::Printf(
                TEXT("TerritoryNodeLabelText%03d"), Index
            ));
            UBorder* Frame = Cast<UBorder>(Tree->FindWidget(FrameName));
            UTextBlock* Label = Cast<UTextBlock>(Tree->FindWidget(TextName));
            if (Frame && Label && Frame->GetContent() == Label)
            {
                return true;
            }
            if (Frame || Label)
            {
                UE_LOG(
                    LogTemp,
                    Error,
                    TEXT("PalTR territory label %d has a partial hierarchy."),
                    Index
                );
                return false;
            }

            Frame = MakeSolid(
                Tree,
                FrameName,
                FromSRGB(5, 15, 22, 0.88f)
            );
            Frame->SetPadding(FMargin(0.55f, 0.18f));
            Label = Tree->ConstructWidget<UTextBlock>(
                UTextBlock::StaticClass(),
                TextName
            );
            Label->bIsVariable = true;
            Label->SetText(FText::FromString(TEXT("Karakol")));
            Label->SetColorAndOpacity(FSlateColor(FromSRGB(242, 232, 213)));
            Label->SetJustification(ETextJustify::Center);
            Label->SetAutoWrapText(false);
            Label->SetShadowOffset(FVector2D(0.15f, 0.15f));
            Label->SetShadowColorAndOpacity(FromSRGB(0, 0, 0, 0.90f));
            FSlateFontInfo Font = Label->GetFont();
            Font.Size = 2;
            Label->SetFont(Font);
            Label->SetVisibility(ESlateVisibility::SelfHitTestInvisible);
            Frame->SetContent(Label);
            AddPoolControl(Root, Frame, 31);
            return true;
        }
    }

    bool CreateTerritoryMapOverlay()
    {
        if (FPackageName::DoesPackageExist(PackageName))
        {
            UE_LOG(
                LogTemp,
                Error,
                TEXT("PalTR territory map overlay refused: target already exists.")
            );
            return false;
        }

        UPackage* Package = CreatePackage(PackageName);
        UWidgetBlueprint* Blueprint = Cast<UWidgetBlueprint>(
            FKismetEditorUtilities::CreateBlueprint(
                UUserWidget::StaticClass(),
                Package,
                AssetName,
                BPTYPE_Normal,
                UWidgetBlueprint::StaticClass(),
                UWidgetBlueprintGeneratedClass::StaticClass(),
                TEXT("PalTRUIAssetBuilder")
            )
        );
        if (!Blueprint || !Blueprint->WidgetTree)
        {
            UE_LOG(
                LogTemp,
                Error,
                TEXT("PalTR territory map overlay blueprint creation failed.")
            );
            return false;
        }

        UWidgetTree* Tree = Blueprint->WidgetTree;
        UCanvasPanel* Root = Tree->ConstructWidget<UCanvasPanel>(
            UCanvasPanel::StaticClass(),
            TEXT("TerritoryOverlayCanvas")
        );
        Root->bIsVariable = true;
        Root->SetVisibility(ESlateVisibility::SelfHitTestInvisible);
        Tree->RootWidget = Root;

        const FLinearColor Neutral = FromSRGB(148, 163, 184, 0.90f);
        const FLinearColor BorderShadow = FromSRGB(4, 12, 17, 0.92f);
        for (int32 Index = 1; Index <= SegmentCount; ++Index)
        {
            UBorder* Segment = MakeSolid(
                Tree,
                FName(*FString::Printf(TEXT("TerritorySegment%03d"), Index)),
                BorderShadow
            );
            Segment->SetPadding(FMargin(0.0f, 0.85f));
            UBorder* Inner = MakeSolid(
                Tree,
                FName(*FString::Printf(
                    TEXT("TerritorySegmentInner%03d"),
                    Index
                )),
                Neutral
            );
            Inner->SetVisibility(ESlateVisibility::SelfHitTestInvisible);
            Segment->SetContent(Inner);
            AddPoolControl(Root, Segment, 20);
        }

        const FLinearColor Gold = FromSRGB(232, 176, 69, 0.96f);
        for (int32 Index = 1; Index <= NodeCount; ++Index)
        {
            UBorder* Node = MakeSolid(
                Tree,
                FName(*FString::Printf(TEXT("TerritoryNode%03d"), Index)),
                Gold
            );
            AddPoolControl(Root, Node, 30);
            if (!EnsureNodeLabel(Tree, Root, Index))
            {
                return false;
            }
        }

        UBorder* Legend = Tree->ConstructWidget<UBorder>(
            UBorder::StaticClass(),
            TEXT("TerritoryLegendFrame")
        );
        Legend->bIsVariable = true;
        Legend->SetBrushColor(FromSRGB(7, 18, 27, 0.88f));
        Legend->SetPadding(FMargin(14.0f, 7.0f));
        Legend->SetVisibility(ESlateVisibility::SelfHitTestInvisible);
        UHorizontalBox* LegendRow = Tree->ConstructWidget<UHorizontalBox>(
            UHorizontalBox::StaticClass(),
            TEXT("TerritoryLegendRow")
        );
        Legend->SetContent(LegendRow);

        AddLegendText(
            LegendRow,
            MakeLegendText(
                Tree,
                TEXT("TerritoryLegendTitle"),
                TEXT("PALTR SINIRLARI"),
                FromSRGB(242, 232, 213)
            ),
            FMargin(0, 0, 18, 0)
        );
        AddLegendText(
            LegendRow,
            MakeLegendText(Tree, TEXT("TerritoryLegendOwn"), TEXT("● Biz"), Gold),
            FMargin(0, 0, 14, 0)
        );
        AddLegendText(
            LegendRow,
            MakeLegendText(
                Tree,
                TEXT("TerritoryLegendAlliance"),
                TEXT("● İttifak"),
                FromSRGB(51, 204, 224)
            ),
            FMargin(0, 0, 14, 0)
        );
        AddLegendText(
            LegendRow,
            MakeLegendText(
                Tree,
                TEXT("TerritoryLegendNeutral"),
                TEXT("● Tarafsız"),
                Neutral
            ),
            FMargin(0, 0, 14, 0)
        );
        AddLegendText(
            LegendRow,
            MakeLegendText(
                Tree,
                TEXT("TerritoryLegendWar"),
                TEXT("● Savaş"),
                FromSRGB(224, 64, 64)
            ),
            FMargin(0)
        );

        UCanvasPanelSlot* LegendSlot = Root->AddChildToCanvas(Legend);
        LegendSlot->SetAnchors(FAnchors(0.0f, 1.0f));
        LegendSlot->SetAlignment(FVector2D(0.0f, 1.0f));
        LegendSlot->SetPosition(FVector2D(28.0f, -28.0f));
        LegendSlot->SetSize(FVector2D(500.0f, 34.0f));
        LegendSlot->SetZOrder(40);

        FAssetRegistryModule::AssetCreated(Blueprint);
        FKismetEditorUtilities::CompileBlueprint(Blueprint);
        if (Blueprint->Status == BS_Error || !SaveAsset(Blueprint))
        {
            UE_LOG(
                LogTemp,
                Error,
                TEXT("PalTR territory map overlay compile/save failed.")
            );
            return false;
        }

        UE_LOG(
            LogTemp,
            Display,
            TEXT("PALTR_TERRITORY_MAP_OVERLAY_CREATED | segments=%d | nodes=%d"),
            SegmentCount,
            NodeCount
        );
        return true;
    }

    bool UpdateTerritoryMapOverlayLabels()
    {
        UWidgetBlueprint* Blueprint = LoadObject<UWidgetBlueprint>(
            nullptr,
            TEXT("/Game/Mods/PalTRUI/WBP_PalTRMapOverlay.WBP_PalTRMapOverlay")
        );
        UWidgetTree* Tree = Blueprint ? Blueprint->WidgetTree : nullptr;
        UCanvasPanel* Root = Tree
            ? Cast<UCanvasPanel>(Tree->RootWidget) : nullptr;
        if (!Blueprint || !Tree || !Root)
        {
            UE_LOG(
                LogTemp,
                Error,
                TEXT("PalTR territory label update failed: overlay root is missing.")
            );
            return false;
        }

        Blueprint->Modify();
        Tree->Modify();
        Root->Modify();
        for (int32 Index = 1; Index <= NodeCount; ++Index)
        {
            if (!EnsureNodeLabel(Tree, Root, Index))
            {
                return false;
            }
        }
        FBlueprintEditorUtils::MarkBlueprintAsStructurallyModified(Blueprint);
        FKismetEditorUtilities::CompileBlueprint(Blueprint);
        if (Blueprint->Status == BS_Error || !SaveAsset(Blueprint))
        {
            UE_LOG(
                LogTemp,
                Error,
                TEXT("PalTR territory label update failed while saving.")
            );
            return false;
        }

        UE_LOG(
            LogTemp,
            Display,
            TEXT("PALTR_TERRITORY_MAP_LABELS_UPDATED | labels=%d"),
            NodeCount
        );
        return true;
    }

    bool VerifyTerritoryMapOverlay()
    {
        UWidgetBlueprint* Blueprint = LoadObject<UWidgetBlueprint>(
            nullptr,
            TEXT("/Game/Mods/PalTRUI/WBP_PalTRMapOverlay.WBP_PalTRMapOverlay")
        );
        if (!Blueprint || !Blueprint->WidgetTree)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTR territory map overlay is missing."));
            return false;
        }

        for (int32 Index = 1; Index <= SegmentCount; ++Index)
        {
            if (!Cast<UBorder>(Blueprint->WidgetTree->FindWidget(
                FName(*FString::Printf(TEXT("TerritorySegment%03d"), Index))
            )) || !Cast<UBorder>(Blueprint->WidgetTree->FindWidget(
                FName(*FString::Printf(
                    TEXT("TerritorySegmentInner%03d"),
                    Index
                ))
            )))
            {
                UE_LOG(
                    LogTemp,
                    Error,
                    TEXT("PalTR territory map overlay segment %d is missing."),
                    Index
                );
                return false;
            }
        }
        for (int32 Index = 1; Index <= NodeCount; ++Index)
        {
            if (!Cast<UBorder>(Blueprint->WidgetTree->FindWidget(
                FName(*FString::Printf(TEXT("TerritoryNode%03d"), Index))
            )) || !Cast<UBorder>(Blueprint->WidgetTree->FindWidget(
                FName(*FString::Printf(TEXT("TerritoryNodeLabel%03d"), Index))
            )) || !Cast<UTextBlock>(Blueprint->WidgetTree->FindWidget(
                FName(*FString::Printf(
                    TEXT("TerritoryNodeLabelText%03d"), Index
                ))
            )))
            {
                UE_LOG(
                    LogTemp,
                    Error,
                    TEXT("PalTR territory map overlay node/label %d is missing."),
                    Index
                );
                return false;
            }
        }
        if (!Blueprint->GeneratedClass
            || !Blueprint->WidgetTree->FindWidget(TEXT("TerritoryLegendFrame")))
        {
            UE_LOG(
                LogTemp,
                Error,
                TEXT("PalTR territory map overlay class or legend is missing.")
            );
            return false;
        }

        UE_LOG(
            LogTemp,
            Display,
            TEXT("PALTR_TERRITORY_MAP_OVERLAY_VERIFIED | segments=%d | nodes=%d | labels=%d"),
            SegmentCount,
            NodeCount,
            NodeCount
        );
        return true;
    }
}
