#include "PalTRUIGuildIdentityPage.h"

#include "Blueprint/WidgetTree.h"
#include "Brushes/SlateRoundedBoxBrush.h"
#include "Components/Border.h"
#include "Components/Button.h"
#include "Components/HorizontalBox.h"
#include "Components/HorizontalBoxSlot.h"
#include "Components/TextBlock.h"
#include "Components/VerticalBox.h"
#include "Components/VerticalBoxSlot.h"
#include "Components/WidgetSwitcher.h"
#include "EdGraphSchema_K2_Actions.h"
#include "K2Node_ComponentBoundEvent.h"
#include "Kismet2/BlueprintEditorUtils.h"
#include "Kismet2/KismetEditorUtilities.h"
#include "Misc/PackageName.h"
#include "UObject/SavePackage.h"
#include "WidgetBlueprint.h"

namespace
{
    constexpr TCHAR PanelPath[] =
        TEXT("/Game/Mods/PalTRUI/WBP_PalTRPanel_DesignTemplate.WBP_PalTRPanel_DesignTemplate");

    FLinearColor FromSRGB(
        const uint8 R,
        const uint8 G,
        const uint8 B,
        const float Alpha = 1.0f
    )
    {
        FLinearColor Result = FLinearColor::FromSRGBColor(FColor(R, G, B, 255));
        Result.A = Alpha;
        return Result;
    }

    const FLinearColor GuildGoldMuted = FromSRGB(131, 107, 60, 0.96f);
    const FLinearColor GuildGold = FromSRGB(198, 154, 72, 0.98f);
    const FLinearColor GuildCyan = FromSRGB(40, 217, 237, 0.96f);
    const FLinearColor GuildCyanDark = FromSRGB(14, 58, 70, 0.98f);
    const FLinearColor GuildPanelBlue = FromSRGB(24, 52, 70, 0.96f);
    const FLinearColor GuildTextPrimary = FromSRGB(242, 232, 213, 1.0f);
    const FLinearColor GuildTextSecondary = FromSRGB(184, 185, 181, 1.0f);

    UTextBlock* MakeText(
        UWidgetTree* Tree,
        const FName Name,
        const TCHAR* Value,
        const int32 Size
    )
    {
        UTextBlock* Text = Tree->ConstructWidget<UTextBlock>(
            UTextBlock::StaticClass(), Name
        );
        Text->SetText(FText::FromString(Value));
        Text->SetColorAndOpacity(FSlateColor(FLinearColor::White));
        FSlateFontInfo Font = Text->GetFont();
        Font.Size = Size;
        Text->SetFont(Font);
        return Text;
    }

    UButton* MakeButton(
        UWidgetTree* Tree,
        const FName ButtonName,
        const FName TextName,
        const TCHAR* Label
    )
    {
        UButton* Button = Tree->ConstructWidget<UButton>(
            UButton::StaticClass(), ButtonName
        );
        Button->SetContent(MakeText(Tree, TextName, Label, 16));
        return Button;
    }

    void StyleButton(
        UWidgetTree* Tree,
        const FName Name,
        const FLinearColor Color
    )
    {
        UButton* Button = Cast<UButton>(Tree->FindWidget(Name));
        if (!Button) return;
        const FLinearColor Hover(
            FMath::Min(Color.R * 1.20f, 1.0f),
            FMath::Min(Color.G * 1.20f, 1.0f),
            FMath::Min(Color.B * 1.20f, 1.0f),
            Color.A
        );
        const FLinearColor Pressed(
            Color.R * 0.82f,
            Color.G * 0.82f,
            Color.B * 0.82f,
            Color.A
        );
        FButtonStyle Style = Button->WidgetStyle;
        Style.SetNormal(FSlateRoundedBoxBrush(Color, 6.0f, GuildGoldMuted, 1.5f));
        Style.SetHovered(FSlateRoundedBoxBrush(Hover, 6.0f, GuildCyan, 2.0f));
        Style.SetPressed(FSlateRoundedBoxBrush(Pressed, 5.0f, GuildGold, 2.0f));
        Style.SetDisabled(FSlateRoundedBoxBrush(
            FromSRGB(25, 31, 34, 0.78f),
            6.0f,
            FromSRGB(67, 71, 70, 0.72f),
            1.0f
        ));
        Style.SetNormalPadding(FMargin(7.0f, 5.0f));
        Style.SetPressedPadding(FMargin(7.0f, 6.0f, 7.0f, 4.0f));
        Button->SetStyle(Style);
        Button->SetBackgroundColor(FLinearColor::White);
        if (UTextBlock* Label = Cast<UTextBlock>(Button->GetContent()))
        {
            Label->SetColorAndOpacity(FSlateColor(GuildTextPrimary));
            Label->SetShadowOffset(FVector2D(1.0f, 2.0f));
            Label->SetShadowColorAndOpacity(FLinearColor(0, 0, 0, 0.85f));
        }
    }

    UVerticalBoxSlot* AddVertical(
        UVerticalBox* Parent,
        UWidget* Child,
        const FMargin Padding = FMargin(0.0f)
    )
    {
        UVerticalBoxSlot* Slot = Parent->AddChildToVerticalBox(Child);
        Slot->SetPadding(Padding);
        Slot->SetHorizontalAlignment(HAlign_Fill);
        return Slot;
    }

    UHorizontalBoxSlot* AddHorizontal(
        UHorizontalBox* Parent,
        UWidget* Child,
        const FMargin Padding = FMargin(0.0f)
    )
    {
        UHorizontalBoxSlot* Slot = Parent->AddChildToHorizontalBox(Child);
        Slot->SetPadding(Padding);
        Slot->SetVerticalAlignment(VAlign_Center);
        return Slot;
    }

    bool SaveAsset(UObject* Asset)
    {
        UPackage* Package = Asset ? Asset->GetOutermost() : nullptr;
        if (!Package) return false;
        Package->MarkPackageDirty();
        const FString Filename = FPackageName::LongPackageNameToFilename(
            Package->GetName(), FPackageName::GetAssetPackageExtension()
        );
        FSavePackageArgs SaveArgs;
        SaveArgs.TopLevelFlags = RF_Public | RF_Standalone;
        SaveArgs.SaveFlags = SAVE_NoError;
        SaveArgs.bWarnOfLongFilename = true;
        return UPackage::SavePackage(Package, Asset, *Filename, SaveArgs);
    }

    bool EnsureButtonEvent(
        UWidgetBlueprint* Blueprint,
        const FName ComponentName,
        const FName FunctionName
    )
    {
        FKismetEditorUtilities::CompileBlueprint(Blueprint);
        FObjectProperty* ComponentProperty = FindFProperty<FObjectProperty>(
            Blueprint->GeneratedClass, ComponentName
        );
        UButton* Button = Cast<UButton>(
            Blueprint->WidgetTree->FindWidget(ComponentName)
        );
        if (!ComponentProperty || !Button) return false;
        const FName DelegateName(TEXT("OnClicked"));
        const UK2Node_ComponentBoundEvent* Existing =
            FKismetEditorUtilities::FindBoundEventForComponent(
                Blueprint, DelegateName, ComponentName
            );
        if (!Existing)
        {
            FMulticastDelegateProperty* DelegateProperty =
                FindFProperty<FMulticastDelegateProperty>(
                    UButton::StaticClass(), DelegateName
                );
            UEdGraph* TargetGraph = Blueprint->GetLastEditedUberGraph();
            if (!DelegateProperty || !TargetGraph) return false;
            FEdGraphSchemaAction_K2NewNode::SpawnNode<
                UK2Node_ComponentBoundEvent
            >(
                TargetGraph,
                FVector2D(0.0f, 1800.0f + TargetGraph->Nodes.Num() * 160.0f),
                EK2NewNodeFlags::None,
                [ComponentProperty, DelegateProperty](
                    UK2Node_ComponentBoundEvent* Node
                )
                {
                    Node->InitializeComponentBoundEventParams(
                        ComponentProperty, DelegateProperty
                    );
                }
            );
            Existing = FKismetEditorUtilities::FindBoundEventForComponent(
                Blueprint, DelegateName, ComponentName
            );
        }
        UK2Node_ComponentBoundEvent* Event =
            const_cast<UK2Node_ComponentBoundEvent*>(Existing);
        if (!Event) return false;
        Event->Modify();
        Event->CustomFunctionName = FunctionName;
        return true;
    }

    bool HasRequiredControls(UWidgetTree* Tree)
    {
        if (!Tree
            || !Tree->FindWidget(TEXT("GuildIdentityPage"))
            || !Tree->FindWidget(TEXT("GuildIdentitySaveButton")))
        {
            return false;
        }
        for (int32 Index = 1; Index <= 16; ++Index)
        {
            if (!Tree->FindWidget(FName(*FString::Printf(
                TEXT("GuildIdentityColorButton%02d"), Index
            )))) return false;
        }
        for (int32 Index = 1; Index <= 12; ++Index)
        {
            if (!Tree->FindWidget(FName(*FString::Printf(
                TEXT("GuildIdentityEmblemButton%02d"), Index
            )))) return false;
        }
        return true;
    }

    bool BindEvents(UWidgetBlueprint* Panel)
    {
        if (!EnsureButtonEvent(
            Panel, TEXT("YonetimButton"), TEXT("PalTR_ManagementClicked")
        )) return false;
        for (int32 Index = 1; Index <= 16; ++Index)
        {
            if (!EnsureButtonEvent(
                Panel,
                FName(*FString::Printf(
                    TEXT("GuildIdentityColorButton%02d"), Index
                )),
                FName(*FString::Printf(
                    TEXT("PalTR_GuildIdentityColor%02dClicked"), Index
                ))
            )) return false;
        }
        for (int32 Index = 1; Index <= 12; ++Index)
        {
            if (!EnsureButtonEvent(
                Panel,
                FName(*FString::Printf(
                    TEXT("GuildIdentityEmblemButton%02d"), Index
                )),
                FName(*FString::Printf(
                    TEXT("PalTR_GuildIdentityEmblem%02dClicked"), Index
                ))
            )) return false;
        }
        return EnsureButtonEvent(
            Panel,
            TEXT("GuildIdentitySaveButton"),
            TEXT("PalTR_GuildIdentitySaveClicked")
        );
    }
}

namespace PalTRUIGuildIdentityPage
{
    bool UpdateGuildIdentityPage()
    {
        UWidgetBlueprint* Panel = LoadObject<UWidgetBlueprint>(nullptr, PanelPath);
        if (!Panel || !Panel->WidgetTree)
        {
            UE_LOG(LogTemp, Error,
                TEXT("PalTRUI guild-identity page asset is missing."));
            return false;
        }
        UWidgetTree* Tree = Panel->WidgetTree;
        UWidgetSwitcher* Switcher = Cast<UWidgetSwitcher>(
            Tree->FindWidget(TEXT("TemplatePageSwitcher"))
        );
        UButton* ManagementButton = Cast<UButton>(
            Tree->FindWidget(TEXT("YonetimButton"))
        );
        if (!Switcher || !ManagementButton)
        {
            UE_LOG(LogTemp, Error,
                TEXT("PalTRUI guild-identity page requires TemplatePageSwitcher and YonetimButton."));
            return false;
        }

        Panel->Modify();
        Tree->Modify();
        UBorder* PageFrame = Cast<UBorder>(
            Tree->FindWidget(TEXT("GuildIdentityPage"))
        );
        if (!PageFrame)
        {
            PageFrame = Tree->ConstructWidget<UBorder>(
                UBorder::StaticClass(), TEXT("GuildIdentityPage")
            );
            PageFrame->SetBrush(FSlateRoundedBoxBrush(
                FromSRGB(7, 22, 32, 0.90f),
                6.0f,
                FromSRGB(92, 72, 42, 0.90f),
                1.0f
            ));
            PageFrame->SetPadding(FMargin(18.0f));
            UVerticalBox* Page = Tree->ConstructWidget<UVerticalBox>(
                UVerticalBox::StaticClass(), TEXT("GuildIdentityLayout")
            );
            PageFrame->SetContent(Page);

            UTextBlock* Heading = MakeText(
                Tree, TEXT("GuildIdentityHeadingText"), TEXT("Klan Kimliği"), 28
            );
            Heading->SetColorAndOpacity(FSlateColor(GuildTextPrimary));
            AddVertical(Page, Heading);
            UTextBlock* Subtitle = MakeText(
                Tree,
                TEXT("GuildIdentitySubtitleText"),
                TEXT("Harita sınırlarınız için benzersiz renk ve klan arması seçin."),
                15
            );
            Subtitle->SetColorAndOpacity(FSlateColor(GuildTextSecondary));
            AddVertical(Page, Subtitle, FMargin(0, 4, 0, 15));

            UHorizontalBox* Columns = Tree->ConstructWidget<UHorizontalBox>(
                UHorizontalBox::StaticClass(), TEXT("GuildIdentityColumns")
            );
            UVerticalBoxSlot* ColumnsSlot = AddVertical(Page, Columns);
            ColumnsSlot->SetSize(FSlateChildSize(ESlateSizeRule::Fill));
            ColumnsSlot->SetVerticalAlignment(VAlign_Fill);

            UBorder* ColorFrame = Tree->ConstructWidget<UBorder>(
                UBorder::StaticClass(), TEXT("GuildIdentityColorFrame")
            );
            ColorFrame->SetBrush(FSlateRoundedBoxBrush(
                FromSRGB(8, 29, 40, 0.90f), 5.0f, GuildGoldMuted, 1.0f
            ));
            ColorFrame->SetPadding(FMargin(13.0f));
            UVerticalBox* ColorList = Tree->ConstructWidget<UVerticalBox>(
                UVerticalBox::StaticClass(), TEXT("GuildIdentityColorList")
            );
            ColorFrame->SetContent(ColorList);
            AddVertical(ColorList, MakeText(
                Tree, TEXT("GuildIdentityColorHeadingText"), TEXT("Klan Rengi"), 21
            ), FMargin(0, 0, 0, 10));

            struct FColorChoice
            {
                const TCHAR* Id;
                uint8 R;
                uint8 G;
                uint8 B;
            };
            const FColorChoice Colors[] = {
                { TEXT("azure"), 36, 117, 216 },
                { TEXT("cyan"), 24, 187, 209 },
                { TEXT("teal"), 22, 142, 131 },
                { TEXT("green"), 39, 138, 76 },
                { TEXT("lime"), 114, 168, 59 },
                { TEXT("gold"), 196, 154, 50 },
                { TEXT("amber"), 209, 124, 34 },
                { TEXT("orange"), 203, 87, 39 },
                { TEXT("red"), 190, 53, 53 },
                { TEXT("crimson"), 143, 41, 67 },
                { TEXT("magenta"), 177, 62, 134 },
                { TEXT("purple"), 117, 66, 167 },
                { TEXT("violet"), 87, 74, 168 },
                { TEXT("steel"), 82, 111, 131 },
                { TEXT("ivory"), 184, 173, 143 },
                { TEXT("rose"), 182, 95, 112 }
            };
            for (int32 RowIndex = 0; RowIndex < 4; ++RowIndex)
            {
                UHorizontalBox* Row = Tree->ConstructWidget<UHorizontalBox>(
                    UHorizontalBox::StaticClass(),
                    FName(*FString::Printf(
                        TEXT("GuildIdentityColorRow%02d"), RowIndex + 1
                    ))
                );
                for (int32 ColumnIndex = 0; ColumnIndex < 4; ++ColumnIndex)
                {
                    const int32 Index = RowIndex * 4 + ColumnIndex;
                    const FName ButtonName(*FString::Printf(
                        TEXT("GuildIdentityColorButton%02d"), Index + 1
                    ));
                    UButton* Button = MakeButton(
                        Tree,
                        ButtonName,
                        FName(*FString::Printf(
                            TEXT("GuildIdentityColorText%02d"), Index + 1
                        )),
                        Colors[Index].Id
                    );
                    StyleButton(Tree, ButtonName, FromSRGB(
                        Colors[Index].R,
                        Colors[Index].G,
                        Colors[Index].B,
                        0.96f
                    ));
                    UHorizontalBoxSlot* Slot = AddHorizontal(
                        Row,
                        Button,
                        ColumnIndex < 3 ? FMargin(0, 0, 7, 0) : FMargin(0)
                    );
                    Slot->SetSize(FSlateChildSize(ESlateSizeRule::Fill));
                    Slot->SetHorizontalAlignment(HAlign_Fill);
                }
                AddVertical(
                    ColorList,
                    Row,
                    RowIndex < 3 ? FMargin(0, 0, 0, 7) : FMargin(0)
                );
            }
            UHorizontalBoxSlot* ColorSlot = AddHorizontal(
                Columns, ColorFrame, FMargin(0, 0, 12, 0)
            );
            ColorSlot->SetSize(FSlateChildSize(ESlateSizeRule::Fill));
            ColorSlot->SetVerticalAlignment(VAlign_Fill);

            UBorder* EmblemFrame = Tree->ConstructWidget<UBorder>(
                UBorder::StaticClass(), TEXT("GuildIdentityEmblemFrame")
            );
            EmblemFrame->SetBrush(FSlateRoundedBoxBrush(
                FromSRGB(9, 31, 43, 0.90f), 5.0f, GuildGoldMuted, 1.0f
            ));
            EmblemFrame->SetPadding(FMargin(13.0f));
            UVerticalBox* EmblemList = Tree->ConstructWidget<UVerticalBox>(
                UVerticalBox::StaticClass(), TEXT("GuildIdentityEmblemList")
            );
            EmblemFrame->SetContent(EmblemList);
            AddVertical(EmblemList, MakeText(
                Tree, TEXT("GuildIdentityEmblemHeadingText"), TEXT("Klan Arması"), 21
            ), FMargin(0, 0, 0, 10));
            const TCHAR* EmblemIds[] = {
                TEXT("wolf"), TEXT("eagle"), TEXT("stag"), TEXT("lion"),
                TEXT("raven"), TEXT("serpent"), TEXT("bear"), TEXT("boar"),
                TEXT("dragon"), TEXT("sun"), TEXT("moon"), TEXT("tower")
            };
            for (int32 RowIndex = 0; RowIndex < 3; ++RowIndex)
            {
                UHorizontalBox* Row = Tree->ConstructWidget<UHorizontalBox>(
                    UHorizontalBox::StaticClass(),
                    FName(*FString::Printf(
                        TEXT("GuildIdentityEmblemRow%02d"), RowIndex + 1
                    ))
                );
                for (int32 ColumnIndex = 0; ColumnIndex < 4; ++ColumnIndex)
                {
                    const int32 Index = RowIndex * 4 + ColumnIndex;
                    const FName ButtonName(*FString::Printf(
                        TEXT("GuildIdentityEmblemButton%02d"), Index + 1
                    ));
                    UButton* Button = MakeButton(
                        Tree,
                        ButtonName,
                        FName(*FString::Printf(
                            TEXT("GuildIdentityEmblemText%02d"), Index + 1
                        )),
                        EmblemIds[Index]
                    );
                    StyleButton(Tree, ButtonName, GuildPanelBlue);
                    UHorizontalBoxSlot* Slot = AddHorizontal(
                        Row,
                        Button,
                        ColumnIndex < 3 ? FMargin(0, 0, 7, 0) : FMargin(0)
                    );
                    Slot->SetSize(FSlateChildSize(ESlateSizeRule::Fill));
                    Slot->SetHorizontalAlignment(HAlign_Fill);
                }
                AddVertical(
                    EmblemList,
                    Row,
                    RowIndex < 2 ? FMargin(0, 0, 0, 7) : FMargin(0)
                );
            }
            UHorizontalBoxSlot* EmblemSlot = AddHorizontal(
                Columns, EmblemFrame
            );
            EmblemSlot->SetSize(FSlateChildSize(ESlateSizeRule::Fill));
            EmblemSlot->SetVerticalAlignment(VAlign_Fill);

            UTextBlock* Status = MakeText(
                Tree,
                TEXT("GuildIdentityStatusText"),
                TEXT("Sunucu klan kimliği verisi bekleniyor."),
                14
            );
            Status->SetAutoWrapText(true);
            Status->SetColorAndOpacity(FSlateColor(GuildTextSecondary));
            AddVertical(Page, Status, FMargin(0, 13, 0, 8));
            UButton* Save = MakeButton(
                Tree,
                TEXT("GuildIdentitySaveButton"),
                TEXT("GuildIdentitySaveText"),
                TEXT("Kimliği Kaydet")
            );
            // The disabled style remains muted. Once both choices are made,
            // enabling the button exposes this bright gold call-to-action.
            StyleButton(Tree, TEXT("GuildIdentitySaveButton"), GuildGold);
            Save->SetIsEnabled(false);
            AddVertical(Page, Save);
            Switcher->AddChild(PageFrame);
        }

        ManagementButton->SetIsEnabled(true);
        if (!HasRequiredControls(Tree) || !BindEvents(Panel))
        {
            UE_LOG(LogTemp, Error,
                TEXT("PalTRUI guild-identity controls or events are incomplete."));
            return false;
        }
        FBlueprintEditorUtils::MarkBlueprintAsStructurallyModified(Panel);
        FKismetEditorUtilities::CompileBlueprint(Panel);
        if (Panel->Status == BS_Error || !SaveAsset(Panel)) return false;
        UE_LOG(LogTemp, Display,
            TEXT("PALTR_UI_GUILD_IDENTITY_PAGE_OK | colors=16 | emblems=12 | save=atomic"));
        return true;
    }

    bool VerifyGuildIdentityPage()
    {
        UWidgetBlueprint* Panel = LoadObject<UWidgetBlueprint>(nullptr, PanelPath);
        if (!Panel || !Panel->WidgetTree
            || !Panel->WidgetTree->FindWidget(TEXT("TemplatePageSwitcher"))
            || !Panel->WidgetTree->FindWidget(TEXT("YonetimButton"))
            || !HasRequiredControls(Panel->WidgetTree))
        {
            UE_LOG(LogTemp, Error,
                TEXT("PALTR_UI_GUILD_IDENTITY_PAGE_VERIFY_FAILED"));
            return false;
        }
        UE_LOG(LogTemp, Display,
            TEXT("PALTR_UI_GUILD_IDENTITY_PAGE_VERIFIED | colors=16 | emblems=12 | management=1 | save=1"));
        return true;
    }
}
