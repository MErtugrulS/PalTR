#include "PalTRUIMapOverlay.h"

#include "AssetRegistry/AssetRegistryModule.h"
#include "Blueprint/UserWidget.h"
#include "Blueprint/WidgetBlueprintGeneratedClass.h"
#include "Blueprint/WidgetTree.h"
#include "Components/Border.h"
#include "Components/BorderSlot.h"
#include "Components/Button.h"
#include "Components/CanvasPanel.h"
#include "Components/CanvasPanelSlot.h"
#include "Components/HorizontalBox.h"
#include "Components/HorizontalBoxSlot.h"
#include "Components/Image.h"
#include "Components/SizeBox.h"
#include "Components/SizeBoxSlot.h"
#include "Components/TextBlock.h"
#include "Components/VerticalBox.h"
#include "Components/VerticalBoxSlot.h"
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
        constexpr int32 SegmentCount = 128;
        constexpr int32 FillCount = 96;
        constexpr int32 NodeCount = 32;
        constexpr int32 GuildBannerCount = 8;

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
            UWidget* Control,
            const int32 ZOrder
        )
        {
            UCanvasPanelSlot* Slot = Root->AddChildToCanvas(Control);
            Slot->SetPosition(FVector2D::ZeroVector);
            Slot->SetSize(FVector2D(1.0f, 1.0f));
            Slot->SetAlignment(FVector2D::ZeroVector);
            Slot->SetZOrder(ZOrder);
        }

        UTextBlock* MakeRuntimeText(
            UWidgetTree* Tree,
            const FName Name,
            const TCHAR* Initial,
            const int32 Size,
            const FLinearColor Color
        )
        {
            UTextBlock* Text = Tree->ConstructWidget<UTextBlock>(
                UTextBlock::StaticClass(), Name
            );
            Text->bIsVariable = true;
            Text->SetText(FText::FromString(Initial));
            Text->SetColorAndOpacity(FSlateColor(Color));
            Text->SetJustification(ETextJustify::Center);
            Text->SetAutoWrapText(false);
            Text->SetShadowOffset(FVector2D(1.0f, 1.0f));
            Text->SetShadowColorAndOpacity(FromSRGB(0, 0, 0, 0.9f));
            FSlateFontInfo Font = Text->GetFont();
            Font.Size = Size;
            Text->SetFont(Font);
            return Text;
        }

        bool EnsureFill(UWidgetTree* Tree, UCanvasPanel* Root, int32 Index)
        {
            const FName Name(*FString::Printf(TEXT("TerritoryFill%03d"), Index));
            UBorder* Fill = Cast<UBorder>(Tree->FindWidget(Name));
            if (!Fill)
            {
                Fill = MakeSolid(Tree, Name, FromSRGB(47, 128, 237, 0.14f));
                AddPoolControl(Root, Fill, 10);
            }
            Fill->Modify();
            Fill->SetBrushColor(FromSRGB(47, 128, 237, 0.14f));
            Fill->SetVisibility(ESlateVisibility::Collapsed);
            return true;
        }

        bool EnsureNodeVisual(
            UWidgetTree* Tree,
            UCanvasPanel* Root,
            const int32 Index
        )
        {
            const FName NodeName(*FString::Printf(TEXT("TerritoryNode%03d"), Index));
            const FName IconName(*FString::Printf(
                TEXT("TerritoryNodeIconText%03d"), Index
            ));
            const FName HitName(*FString::Printf(
                TEXT("TerritoryNodeHit%03d"), Index
            ));
            UWidget* ExistingNode = Tree->FindWidget(NodeName);
            UTextBlock* ExistingIcon = Cast<UTextBlock>(
                Tree->FindWidget(IconName)
            );
            UImage* Node = Cast<UImage>(ExistingNode);
            if (!Node && ExistingNode)
            {
                if (ExistingIcon)
                {
                    Tree->RemoveWidget(ExistingIcon);
                    ExistingIcon = nullptr;
                }
                Tree->RemoveWidget(ExistingNode);
                const FName LegacyName = MakeUniqueObjectName(
                    Tree,
                    ExistingNode->GetClass(),
                    FName(*FString::Printf(
                        TEXT("LegacyTerritoryNode%03d"), Index
                    ))
                );
                ExistingNode->Rename(
                    *LegacyName.ToString(),
                    Tree,
                    REN_DontCreateRedirectors | REN_ForceNoResetLoaders
                );
            }
            if (!Node)
            {
                Node = Tree->ConstructWidget<UImage>(
                    UImage::StaticClass(), NodeName
                );
                Node->bIsVariable = true;
                AddPoolControl(Root, Node, 30);
            }
            UButton* Hit = Cast<UButton>(Tree->FindWidget(HitName));
            if (!Hit)
            {
                Hit = Tree->ConstructWidget<UButton>(UButton::StaticClass(), HitName);
                Hit->bIsVariable = true;
                Hit->SetBackgroundColor(FromSRGB(255, 255, 255, 0.001f));
                Hit->SetColorAndOpacity(FLinearColor::Transparent);
                Hit->SetVisibility(ESlateVisibility::Collapsed);
                UCanvasPanelSlot* Slot = Root->AddChildToCanvas(Hit);
                Slot->SetPosition(FVector2D::ZeroVector);
                Slot->SetSize(FVector2D(1.0f, 1.0f));
                Slot->SetZOrder(35);
            }
            Node->SetColorAndOpacity(FLinearColor::White);
            Node->SetVisibility(ESlateVisibility::Collapsed);
            Hit->SetVisibility(ESlateVisibility::Collapsed);
            return true;
        }

        void AddBannerLine(UVerticalBox* Box, UTextBlock* Text, float Bottom)
        {
            UVerticalBoxSlot* Slot = Box->AddChildToVerticalBox(Text);
            Slot->SetHorizontalAlignment(HAlign_Fill);
            Slot->SetPadding(FMargin(0, 0, 0, Bottom));
        }

        bool EnsureGuildBanner(
            UWidgetTree* Tree,
            UCanvasPanel* Root,
            const int32 Index
        )
        {
            const FString Suffix = FString::Printf(TEXT("%03d"), Index);
            UBorder* Frame = Cast<UBorder>(Tree->FindWidget(
                FName(*(TEXT("GuildBannerFrame") + Suffix))
            ));
            if (Frame)
            {
                Frame->SetVisibility(ESlateVisibility::Collapsed);
                return true;
            }
            Frame = MakeSolid(
                Tree, FName(*(TEXT("GuildBannerFrame") + Suffix)),
                FromSRGB(47, 128, 237, 0.92f)
            );
            Frame->SetPadding(FMargin(2.0f));
            UBorder* Body = MakeSolid(
                Tree, FName(*(TEXT("GuildBannerBody") + Suffix)),
                FromSRGB(5, 15, 22, 0.90f)
            );
            Body->SetVisibility(ESlateVisibility::SelfHitTestInvisible);
            Body->SetPadding(FMargin(7.0f, 5.0f));
            UVerticalBox* Lines = Tree->ConstructWidget<UVerticalBox>(
                UVerticalBox::StaticClass(),
                FName(*(TEXT("GuildBannerLines") + Suffix))
            );
            Lines->SetVisibility(ESlateVisibility::SelfHitTestInvisible);
            AddBannerLine(Lines, MakeRuntimeText(Tree,
                FName(*(TEXT("GuildBannerEmblem") + Suffix)), TEXT("KLAN"), 10,
                FromSRGB(232, 176, 69)), 1.0f);
            AddBannerLine(Lines, MakeRuntimeText(Tree,
                FName(*(TEXT("GuildBannerName") + Suffix)), TEXT("Klan"), 13,
                FromSRGB(248, 243, 229)), 1.0f);
            AddBannerLine(Lines, MakeRuntimeText(Tree,
                FName(*(TEXT("GuildBannerStats") + Suffix)), TEXT("1 Bolge"), 9,
                FromSRGB(219, 226, 230)), 0.0f);
            AddBannerLine(Lines, MakeRuntimeText(Tree,
                FName(*(TEXT("GuildBannerPower") + Suffix)), TEXT("Guc: Yakinda"), 8,
                FromSRGB(165, 180, 190)), 0.0f);
            AddBannerLine(Lines, MakeRuntimeText(Tree,
                FName(*(TEXT("GuildBannerStatus") + Suffix)), TEXT(""), 8,
                FromSRGB(232, 176, 69)), 0.0f);
            Body->SetContent(Lines);
            Frame->SetContent(Body);
            AddPoolControl(Root, Frame, 40);
            Frame->SetVisibility(ESlateVisibility::Collapsed);
            return true;
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
            const bool bExists = Frame && Label && Frame->GetContent() == Label;
            if (!bExists && (Frame || Label))
            {
                UE_LOG(
                    LogTemp,
                    Error,
                    TEXT("PalTR territory label %d has a partial hierarchy."),
                    Index
                );
                return false;
            }
            if (!bExists)
            {
                Frame = MakeSolid(
                    Tree,
                    FrameName,
                    FromSRGB(5, 15, 22, 0.88f)
                );
                Label = Tree->ConstructWidget<UTextBlock>(
                    UTextBlock::StaticClass(),
                    TextName
                );
                Label->bIsVariable = true;
                Frame->SetContent(Label);
                AddPoolControl(Root, Frame, 31);
            }

            Frame->Modify();
            Label->Modify();
            Frame->SetBrushColor(FromSRGB(5, 15, 22, 0.88f));
            // Runtime scales the complete label down after layout. Keeping the
            // font and padding at normal resolution prevents blocky glyphs
            // when Palworld magnifies the map-body canvas.
            Frame->SetPadding(FMargin(3.3f, 1.08f));
            Frame->SetVisibility(ESlateVisibility::Collapsed);
            Label->SetText(FText::FromString(TEXT("Karakol")));
            Label->SetColorAndOpacity(FSlateColor(FromSRGB(242, 232, 213)));
            Label->SetJustification(ETextJustify::Center);
            Label->SetAutoWrapText(false);
            Label->SetShadowOffset(FVector2D(1.0f, 1.0f));
            Label->SetShadowColorAndOpacity(FromSRGB(0, 0, 0, 0.90f));
            FSlateFontInfo Font = Label->GetFont();
            Font.Size = 12;
            Label->SetFont(Font);
            Label->SetVisibility(ESlateVisibility::SelfHitTestInvisible);
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
        for (int32 Index = 1; Index <= FillCount; ++Index)
        {
            if (!EnsureFill(Tree, Root, Index)) return false;
        }
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
            if (!EnsureNodeVisual(Tree, Root, Index)) return false;
            if (!EnsureNodeLabel(Tree, Root, Index))
            {
                return false;
            }
        }
        for (int32 Index = 1; Index <= GuildBannerCount; ++Index)
        {
            if (!EnsureGuildBanner(Tree, Root, Index)) return false;
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

    bool UpdateTerritoryMapOverlayTerritories()
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
        for (int32 Index = 1; Index <= FillCount; ++Index)
        {
            if (!EnsureFill(Tree, Root, Index)) return false;
        }
        for (int32 Index = 1; Index <= NodeCount; ++Index)
        {
            if (!EnsureNodeVisual(Tree, Root, Index)) return false;
            if (!EnsureNodeLabel(Tree, Root, Index))
            {
                return false;
            }
        }
        for (int32 Index = 1; Index <= GuildBannerCount; ++Index)
        {
            if (!EnsureGuildBanner(Tree, Root, Index)) return false;
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
            TEXT("PALTR_TERRITORY_MAP_UPDATED | fills=%d | nodes=%d | banners=%d"),
            FillCount,
            NodeCount,
            GuildBannerCount
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
        for (int32 Index = 1; Index <= FillCount; ++Index)
        {
            if (!Cast<UBorder>(Blueprint->WidgetTree->FindWidget(
                FName(*FString::Printf(TEXT("TerritoryFill%03d"), Index))
            ))) return false;
        }
        for (int32 Index = 1; Index <= NodeCount; ++Index)
        {
            if (!Cast<UImage>(Blueprint->WidgetTree->FindWidget(
                FName(*FString::Printf(TEXT("TerritoryNode%03d"), Index))
            )) || !Cast<UButton>(Blueprint->WidgetTree->FindWidget(
                FName(*FString::Printf(TEXT("TerritoryNodeHit%03d"), Index))
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
        for (int32 Index = 1; Index <= GuildBannerCount; ++Index)
        {
            if (!Cast<UBorder>(Blueprint->WidgetTree->FindWidget(
                FName(*FString::Printf(TEXT("GuildBannerFrame%03d"), Index))
            )) || !Cast<UTextBlock>(Blueprint->WidgetTree->FindWidget(
                FName(*FString::Printf(TEXT("GuildBannerName%03d"), Index))
            ))) return false;
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
            TEXT("PALTR_TERRITORY_MAP_OVERLAY_VERIFIED | fills=%d | segments=%d | nodes=%d | labels=%d | banners=%d"),
            FillCount,
            SegmentCount,
            NodeCount,
            NodeCount,
            GuildBannerCount
        );
        return true;
    }
}
