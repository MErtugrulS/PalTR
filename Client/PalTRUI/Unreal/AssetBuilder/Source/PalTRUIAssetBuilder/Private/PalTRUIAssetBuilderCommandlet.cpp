#include "PalTRUIAssetBuilderCommandlet.h"

#include "AssetRegistry/AssetRegistryModule.h"
#include "Blueprint/UserWidget.h"
#include "Blueprint/WidgetBlueprintGeneratedClass.h"
#include "Blueprint/WidgetTree.h"
#include "Brushes/SlateNoResource.h"
#include "Brushes/SlateRoundedBoxBrush.h"
#include "Components/Border.h"
#include "Components/BorderSlot.h"
#include "Components/Button.h"
#include "Components/ButtonSlot.h"
#include "Components/CanvasPanel.h"
#include "Components/CanvasPanelSlot.h"
#include "Components/EditableTextBox.h"
#include "Components/HorizontalBox.h"
#include "Components/HorizontalBoxSlot.h"
#include "Components/Image.h"
#include "Components/Overlay.h"
#include "Components/OverlaySlot.h"
#include "Components/PanelWidget.h"
#include "Components/ScrollBox.h"
#include "Components/SizeBox.h"
#include "Components/TextBlock.h"
#include "Components/VerticalBox.h"
#include "Components/VerticalBoxSlot.h"
#include "Components/WidgetSwitcher.h"
#include "Engine/Blueprint.h"
#include "Engine/Texture2D.h"
#include "Factories/Factory.h"
#include "Factories/TextureFactory.h"
#include "GameFramework/Actor.h"
#include "Kismet2/KismetEditorUtilities.h"
#include "Kismet2/BlueprintEditorUtils.h"
#include "Misc/Parse.h"
#include "Misc/PackageName.h"
#include "Misc/Paths.h"
#include "UObject/Package.h"
#include "UObject/SavePackage.h"
#include "WidgetBlueprint.h"

namespace PalTRUIAssetBuilder
{
    constexpr TCHAR AssetRoot[] = TEXT("/Game/Mods/PalTRUI");

    UTextBlock* MakeText(UWidgetTree* Tree, const FName Name, const TCHAR* Value, const int32 Size)
    {
        UTextBlock* Text = Tree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass(), Name);
        Text->SetText(FText::FromString(Value));
        Text->SetColorAndOpacity(FSlateColor(FLinearColor::White));

        FSlateFontInfo Font = Text->GetFont();
        Font.Size = Size;
        Text->SetFont(Font);
        return Text;
    }

    UButton* MakeTabButton(UWidgetTree* Tree, const FName ButtonName, const FName TextName, const TCHAR* Label)
    {
        UButton* Button = Tree->ConstructWidget<UButton>(UButton::StaticClass(), ButtonName);
        Button->SetContent(MakeText(Tree, TextName, Label, 18));
        return Button;
    }

    void SetTextColor(UWidgetTree* Tree, const FName Name, const FLinearColor Color)
    {
        if (UTextBlock* Text = Cast<UTextBlock>(Tree->FindWidget(Name)))
        {
            Text->Modify();
            Text->SetColorAndOpacity(FSlateColor(Color));
        }
    }

    void StyleButton(UWidgetTree* Tree, const FName Name, const FLinearColor Color)
    {
        UButton* Button = Cast<UButton>(Tree->FindWidget(Name));
        if (!Button)
        {
            return;
        }

        Button->Modify();
        const FLinearColor Outline(0.32f, 0.68f, 0.72f, 0.95f);
        const FLinearColor Hover(
            FMath::Min(Color.R * 1.20f, 1.0f),
            FMath::Min(Color.G * 1.20f, 1.0f),
            FMath::Min(Color.B * 1.20f, 1.0f),
            Color.A
        );
        const FLinearColor Pressed(Color.R * 0.82f, Color.G * 0.82f, Color.B * 0.82f, Color.A);
        FButtonStyle Style = Button->WidgetStyle;
        Style.SetNormal(FSlateRoundedBoxBrush(Color, 6.0f, Outline, 1.0f));
        Style.SetHovered(FSlateRoundedBoxBrush(Hover, 6.0f, FLinearColor(0.42f, 0.88f, 0.90f, 1.0f), 1.5f));
        Style.SetPressed(FSlateRoundedBoxBrush(Pressed, 6.0f, FLinearColor(0.85f, 0.66f, 0.30f, 1.0f), 1.5f));
        Style.SetDisabled(FSlateRoundedBoxBrush(FLinearColor(0.06f, 0.08f, 0.09f, 0.72f), 6.0f, FLinearColor(0.22f, 0.25f, 0.25f, 0.7f), 1.0f));
        Style.SetNormalPadding(FMargin(7.0f, 5.0f));
        Style.SetPressedPadding(FMargin(7.0f, 6.0f, 7.0f, 4.0f));
        Button->SetStyle(Style);
        Button->SetBackgroundColor(FLinearColor::White);
        if (UTextBlock* Label = Cast<UTextBlock>(Button->GetContent()))
        {
            Label->Modify();
            Label->SetColorAndOpacity(FSlateColor(FLinearColor(0.95f, 0.88f, 0.70f, 1.0f)));
        }
    }

    void StyleRoundedFrame(
        UWidgetTree* Tree,
        const FName Name,
        const FLinearColor Fill,
        const FLinearColor Outline,
        const float Radius,
        const float OutlineWidth,
        const FMargin Padding
    )
    {
        if (UBorder* Frame = Cast<UBorder>(Tree->FindWidget(Name)))
        {
            Frame->Modify();
            Frame->SetBrush(FSlateRoundedBoxBrush(Fill, Radius, Outline, OutlineWidth));
            Frame->SetBrushColor(FLinearColor::White);
            Frame->SetPadding(Padding);
        }
    }

    void StyleFrame(
        UWidgetTree* Tree,
        const FName Name,
        const FLinearColor Color,
        const FMargin Padding
    )
    {
        if (UBorder* Frame = Cast<UBorder>(Tree->FindWidget(Name)))
        {
            Frame->Modify();
            Frame->SetBrushColor(Color);
            Frame->SetPadding(Padding);
        }
    }

    void SetTextFontSize(UWidgetTree* Tree, const FName Name, const int32 Size)
    {
        if (UTextBlock* Text = Cast<UTextBlock>(Tree->FindWidget(Name)))
        {
            Text->Modify();
            FSlateFontInfo Font = Text->GetFont();
            Font.Size = Size;
            Text->SetFont(Font);
        }
    }

    UVerticalBoxSlot* AddVertical(UVerticalBox* Parent, UWidget* Child, const FMargin Padding = FMargin(0.0f))
    {
        UVerticalBoxSlot* Slot = Parent->AddChildToVerticalBox(Child);
        Slot->SetPadding(Padding);
        Slot->SetHorizontalAlignment(HAlign_Fill);
        return Slot;
    }

    UHorizontalBoxSlot* AddHorizontal(UHorizontalBox* Parent, UWidget* Child, const FMargin Padding = FMargin(0.0f))
    {
        UHorizontalBoxSlot* Slot = Parent->AddChildToHorizontalBox(Child);
        Slot->SetPadding(Padding);
        Slot->SetVerticalAlignment(VAlign_Center);
        return Slot;
    }

    UVerticalBox* MakeClanPage(UWidgetTree* Tree)
    {
        UVerticalBox* Page = Tree->ConstructWidget<UVerticalBox>(UVerticalBox::StaticClass(), TEXT("ClanPage"));
        AddVertical(Page, MakeText(Tree, TEXT("ClanHeadingText"), TEXT("KLANIM"), 26), FMargin(0, 0, 0, 18));
        AddVertical(Page, MakeText(Tree, TEXT("ClanNameText"), TEXT("Klan bilgisi bekleniyor"), 22), FMargin(0, 0, 0, 10));
        AddVertical(Page, MakeText(Tree, TEXT("ClanSummaryText"), TEXT("Uyeler ve klan ozeti burada gosterilecek."), 17), FMargin(0, 0, 0, 14));
        AddVertical(Page, MakeText(Tree, TEXT("ClanMembersText"), TEXT("Henuz uye verisi yok."), 16));
        return Page;
    }

    UVerticalBox* MakeDiplomacyPage(UWidgetTree* Tree)
    {
        UVerticalBox* Page = Tree->ConstructWidget<UVerticalBox>(UVerticalBox::StaticClass(), TEXT("DiplomacyPage"));
        AddVertical(Page, MakeText(Tree, TEXT("DiplomacyHeadingText"), TEXT("DIPLOMASI"), 26), FMargin(0, 0, 0, 18));

        UHorizontalBox* Columns = Tree->ConstructWidget<UHorizontalBox>(UHorizontalBox::StaticClass(), TEXT("DiplomacyColumns"));
        UVerticalBoxSlot* ColumnsSlot = AddVertical(Page, Columns);
        ColumnsSlot->SetSize(FSlateChildSize(ESlateSizeRule::Fill));

        USizeBox* ListSize = Tree->ConstructWidget<USizeBox>(USizeBox::StaticClass(), TEXT("RelationListSize"));
        ListSize->SetWidthOverride(330.0f);
        UScrollBox* RelationList = Tree->ConstructWidget<UScrollBox>(UScrollBox::StaticClass(), TEXT("RelationList"));
        RelationList->AddChild(MakeText(Tree, TEXT("RelationListEmptyText"), TEXT("Iliski verisi bekleniyor."), 16));
        ListSize->SetContent(RelationList);
        AddHorizontal(Columns, ListSize, FMargin(0, 0, 24, 0));

        UVerticalBox* Detail = Tree->ConstructWidget<UVerticalBox>(UVerticalBox::StaticClass(), TEXT("RelationDetail"));
        UHorizontalBoxSlot* DetailSlot = AddHorizontal(Columns, Detail);
        DetailSlot->SetSize(FSlateChildSize(ESlateSizeRule::Fill));
        AddVertical(Detail, MakeText(Tree, TEXT("RelationTitleText"), TEXT("Klan secin"), 22), FMargin(0, 0, 0, 10));
        AddVertical(Detail, MakeText(Tree, TEXT("RelationStateText"), TEXT("Iliski durumu: -"), 17), FMargin(0, 0, 0, 10));
        AddVertical(Detail, MakeText(Tree, TEXT("RelationDescriptionText"), TEXT("Sunucu snapshot verisi burada sunulacak."), 16), FMargin(0, 0, 0, 18));

        UHorizontalBox* Actions = Tree->ConstructWidget<UHorizontalBox>(UHorizontalBox::StaticClass(), TEXT("RelationActions"));
        AddHorizontal(Actions, MakeTabButton(Tree, TEXT("AllianceRequestButton"), TEXT("AllianceRequestButtonText"), TEXT("Ittifak Iste")), FMargin(0, 0, 8, 0));
        AddHorizontal(Actions, MakeTabButton(Tree, TEXT("WarRequestButton"), TEXT("WarRequestButtonText"), TEXT("Savas Ilan Et")), FMargin(0, 0, 8, 0));
        AddHorizontal(Actions, MakeTabButton(Tree, TEXT("AcceptButton"), TEXT("AcceptButtonText"), TEXT("Kabul Et")), FMargin(0, 0, 8, 0));
        AddHorizontal(Actions, MakeTabButton(Tree, TEXT("RejectButton"), TEXT("RejectButtonText"), TEXT("Reddet")), FMargin(0, 0, 8, 0));
        AddHorizontal(Actions, MakeTabButton(Tree, TEXT("CancelButton"), TEXT("CancelButtonText"), TEXT("Iptal Et")));
        AddVertical(Detail, Actions);
        return Page;
    }

    UVerticalBox* MakeAlliancePage(UWidgetTree* Tree)
    {
        UVerticalBox* Page = Tree->ConstructWidget<UVerticalBox>(UVerticalBox::StaticClass(), TEXT("AlliancePage"));
        AddVertical(Page, MakeText(Tree, TEXT("AllianceHeadingText"), TEXT("ITTIFAK"), 26), FMargin(0, 0, 0, 18));
        AddVertical(Page, MakeText(Tree, TEXT("AllianceSummaryText"), TEXT("Ittifak bilgisi bekleniyor."), 18), FMargin(0, 0, 0, 14));
        AddVertical(Page, MakeText(Tree, TEXT("AllianceMembersText"), TEXT("Henuz ittifak uyesi verisi yok."), 16));
        return Page;
    }

    UVerticalBox* MakeChatPage(UWidgetTree* Tree)
    {
        UVerticalBox* Page = Tree->ConstructWidget<UVerticalBox>(UVerticalBox::StaticClass(), TEXT("ChatPage"));
        AddVertical(Page, MakeText(Tree, TEXT("ChatHeadingText"), TEXT("SOHBET"), 26), FMargin(0, 0, 0, 18));

        UScrollBox* Messages = Tree->ConstructWidget<UScrollBox>(UScrollBox::StaticClass(), TEXT("ChatMessageList"));
        Messages->AddChild(MakeText(Tree, TEXT("ChatEmptyText"), TEXT("Henuz mesaj yok."), 16));
        UVerticalBoxSlot* MessagesSlot = AddVertical(Page, Messages, FMargin(0, 0, 0, 14));
        MessagesSlot->SetSize(FSlateChildSize(ESlateSizeRule::Fill));

        UHorizontalBox* Composer = Tree->ConstructWidget<UHorizontalBox>(UHorizontalBox::StaticClass(), TEXT("ChatComposer"));
        UEditableTextBox* Input = Tree->ConstructWidget<UEditableTextBox>(UEditableTextBox::StaticClass(), TEXT("ChatInput"));
        Input->SetHintText(FText::FromString(TEXT("Mesaj yaz...")));
        UHorizontalBoxSlot* InputSlot = AddHorizontal(Composer, Input, FMargin(0, 0, 10, 0));
        InputSlot->SetSize(FSlateChildSize(ESlateSizeRule::Fill));
        AddHorizontal(Composer, MakeTabButton(Tree, TEXT("ChatSendButton"), TEXT("ChatSendButtonText"), TEXT("Gonder")));
        AddVertical(Page, Composer);
        return Page;
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

    UTexture2D* ImportUITexture(
        const FString& PackageName,
        const FName AssetName,
        const FString& SourceFilename
    )
    {
        const FString ObjectPath = FString::Printf(
            TEXT("%s.%s"),
            *PackageName,
            *AssetName.ToString()
        );
        if (UTexture2D* Existing = LoadObject<UTexture2D>(nullptr, *ObjectPath))
        {
            return Existing;
        }
        if (!FPaths::FileExists(SourceFilename))
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI texture import failed: source missing: %s"), *SourceFilename);
            return nullptr;
        }

        UPackage* Package = CreatePackage(*PackageName);
        UTextureFactory* Factory = NewObject<UTextureFactory>();
        bool bCanceled = false;
        UTexture2D* Texture = Cast<UTexture2D>(UFactory::StaticImportObject(
            UTexture2D::StaticClass(),
            Package,
            AssetName,
            RF_Public | RF_Standalone,
            bCanceled,
            *SourceFilename,
            nullptr,
            Factory
        ));
        if (!Texture || bCanceled)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI texture import failed: %s"), *SourceFilename);
            return nullptr;
        }
        Texture->Modify();
        Texture->LODGroup = TEXTUREGROUP_UI;
        Texture->NeverStream = true;
        Texture->SRGB = true;
        Texture->UpdateResource();
        FAssetRegistryModule::AssetCreated(Texture);
        if (!SaveAsset(Texture))
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI texture import failed while saving: %s"), *ObjectPath);
            return nullptr;
        }
        return Texture;
    }

    UBlueprint* CreateModActor()
    {
        const FString PackageName = FString(AssetRoot) / TEXT("ModActor");
        UPackage* Package = CreatePackage(*PackageName);
        UBlueprint* Blueprint = FKismetEditorUtilities::CreateBlueprint(
            AActor::StaticClass(),
            Package,
            TEXT("ModActor"),
            BPTYPE_Normal,
            UBlueprint::StaticClass(),
            UBlueprintGeneratedClass::StaticClass(),
            TEXT("PalTRUIAssetBuilder")
        );

        if (Blueprint)
        {
            FAssetRegistryModule::AssetCreated(Blueprint);
            FKismetEditorUtilities::CompileBlueprint(Blueprint);
        }
        return Blueprint;
    }

    UWidgetBlueprint* CreatePanelWidget()
    {
        const FString PackageName = FString(AssetRoot) / TEXT("WBP_PalTRPanel");
        UPackage* Package = CreatePackage(*PackageName);
        UWidgetBlueprint* Blueprint = Cast<UWidgetBlueprint>(FKismetEditorUtilities::CreateBlueprint(
            UUserWidget::StaticClass(),
            Package,
            TEXT("WBP_PalTRPanel"),
            BPTYPE_Normal,
            UWidgetBlueprint::StaticClass(),
            UWidgetBlueprintGeneratedClass::StaticClass(),
            TEXT("PalTRUIAssetBuilder")
        ));

        if (!Blueprint || !Blueprint->WidgetTree)
        {
            return nullptr;
        }

        UWidgetTree* Tree = Blueprint->WidgetTree;
        UCanvasPanel* Root = Tree->ConstructWidget<UCanvasPanel>(UCanvasPanel::StaticClass(), TEXT("RootCanvas"));
        Tree->RootWidget = Root;

        UBorder* Background = Tree->ConstructWidget<UBorder>(UBorder::StaticClass(), TEXT("PanelBackground"));
        Background->SetBrushColor(FLinearColor(0.025f, 0.04f, 0.065f, 0.97f));
        Background->SetPadding(FMargin(28.0f));
        UCanvasPanelSlot* BackgroundSlot = Root->AddChildToCanvas(Background);
        BackgroundSlot->SetAnchors(FAnchors(0.04f, 0.05f, 0.96f, 0.95f));
        BackgroundSlot->SetAlignment(FVector2D::ZeroVector);
        BackgroundSlot->SetOffsets(FMargin(0.0f));

        UVerticalBox* Layout = Tree->ConstructWidget<UVerticalBox>(UVerticalBox::StaticClass(), TEXT("PanelLayout"));
        Background->SetContent(Layout);

        UHorizontalBox* Header = Tree->ConstructWidget<UHorizontalBox>(UHorizontalBox::StaticClass(), TEXT("HeaderRow"));
        UHorizontalBoxSlot* TitleSlot = AddHorizontal(Header, MakeText(Tree, TEXT("TitleText"), TEXT("PalTR"), 32));
        TitleSlot->SetSize(FSlateChildSize(ESlateSizeRule::Fill));
        AddHorizontal(Header, MakeText(Tree, TEXT("ConnectionStatusText"), TEXT("Baglanti bekleniyor"), 15), FMargin(0, 0, 16, 0));
        AddHorizontal(Header, MakeTabButton(Tree, TEXT("CloseButton"), TEXT("CloseButtonText"), TEXT("X")));
        AddVertical(Layout, Header, FMargin(0, 0, 0, 22));

        UHorizontalBox* Tabs = Tree->ConstructWidget<UHorizontalBox>(UHorizontalBox::StaticClass(), TEXT("TabBar"));
        AddHorizontal(Tabs, MakeTabButton(Tree, TEXT("ClanTabButton"), TEXT("ClanTabText"), TEXT("Klanim")), FMargin(0, 0, 10, 0));
        AddHorizontal(Tabs, MakeTabButton(Tree, TEXT("DiplomacyTabButton"), TEXT("DiplomacyTabText"), TEXT("Diplomasi")), FMargin(0, 0, 10, 0));
        AddHorizontal(Tabs, MakeTabButton(Tree, TEXT("AllianceTabButton"), TEXT("AllianceTabText"), TEXT("Ittifak")), FMargin(0, 0, 10, 0));
        AddHorizontal(Tabs, MakeTabButton(Tree, TEXT("ChatTabButton"), TEXT("ChatTabText"), TEXT("Sohbet")));
        AddVertical(Layout, Tabs, FMargin(0, 0, 0, 24));

        UWidgetSwitcher* Switcher = Tree->ConstructWidget<UWidgetSwitcher>(UWidgetSwitcher::StaticClass(), TEXT("ContentSwitcher"));
        Switcher->AddChild(MakeClanPage(Tree));
        Switcher->AddChild(MakeDiplomacyPage(Tree));
        Switcher->AddChild(MakeAlliancePage(Tree));
        Switcher->AddChild(MakeChatPage(Tree));
        Switcher->SetActiveWidgetIndex(0);
        UVerticalBoxSlot* SwitcherSlot = AddVertical(Layout, Switcher);
        SwitcherSlot->SetSize(FSlateChildSize(ESlateSizeRule::Fill));

        FAssetRegistryModule::AssetCreated(Blueprint);
        FKismetEditorUtilities::CompileBlueprint(Blueprint);
        return Blueprint;
    }

    bool UpdateRelationNavigation()
    {
        UWidgetBlueprint* Panel = LoadObject<UWidgetBlueprint>(
            nullptr,
            TEXT("/Game/Mods/PalTRUI/WBP_PalTRPanel.WBP_PalTRPanel")
        );
        if (!Panel || !Panel->WidgetTree)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI relation navigation update failed: panel asset missing."));
            return false;
        }

        UWidgetTree* Tree = Panel->WidgetTree;
        UButton* PreviousButton = Cast<UButton>(Tree->FindWidget(TEXT("PreviousRelationButton")));
        UButton* NextButton = Cast<UButton>(Tree->FindWidget(TEXT("NextRelationButton")));
        if (PreviousButton && NextButton)
        {
            UE_LOG(LogTemp, Display, TEXT("PALTR_UI_RELATION_NAV_UPDATE_OK | changed=false"));
            return true;
        }
        if (PreviousButton || NextButton)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI relation navigation update refused: partial controls exist."));
            return false;
        }

        USizeBox* ListSize = Cast<USizeBox>(Tree->FindWidget(TEXT("RelationListSize")));
        UScrollBox* RelationList = Cast<UScrollBox>(Tree->FindWidget(TEXT("RelationList")));
        if (!ListSize || !RelationList || RelationList->GetParent() != ListSize)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI relation navigation update failed: relation list hierarchy changed."));
            return false;
        }

        Panel->Modify();
        Tree->Modify();
        ListSize->Modify();
        ListSize->RemoveChild(RelationList);

        UVerticalBox* ListColumn = Tree->ConstructWidget<UVerticalBox>(
            UVerticalBox::StaticClass(),
            TEXT("RelationListColumn")
        );
        ListSize->SetContent(ListColumn);
        UVerticalBoxSlot* RelationListSlot = AddVertical(ListColumn, RelationList);
        RelationListSlot->SetSize(FSlateChildSize(ESlateSizeRule::Fill));

        UHorizontalBox* Navigation = Tree->ConstructWidget<UHorizontalBox>(
            UHorizontalBox::StaticClass(),
            TEXT("RelationNavigationRow")
        );
        AddHorizontal(
            Navigation,
            MakeTabButton(
                Tree,
                TEXT("PreviousRelationButton"),
                TEXT("PreviousRelationButtonText"),
                TEXT("Onceki")
            ),
            FMargin(0, 0, 8, 0)
        );
        AddHorizontal(
            Navigation,
            MakeTabButton(
                Tree,
                TEXT("NextRelationButton"),
                TEXT("NextRelationButtonText"),
                TEXT("Sonraki")
            )
        );
        AddVertical(ListColumn, Navigation, FMargin(0, 12, 0, 0));

        FBlueprintEditorUtils::MarkBlueprintAsStructurallyModified(Panel);
        FKismetEditorUtilities::CompileBlueprint(Panel);
        if (!SaveAsset(Panel))
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI relation navigation update failed while saving panel."));
            return false;
        }

        UE_LOG(LogTemp, Display, TEXT("PALTR_UI_RELATION_NAV_UPDATE_OK | changed=true"));
        return true;
    }

    bool UpdateGuildCatalogPage()
    {
        UWidgetBlueprint* Panel = LoadObject<UWidgetBlueprint>(
            nullptr,
            TEXT("/Game/Mods/PalTRUI/WBP_PalTRPanel.WBP_PalTRPanel")
        );
        if (!Panel || !Panel->WidgetTree)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI guild catalog update failed: panel asset missing."));
            return false;
        }

        UWidgetTree* Tree = Panel->WidgetTree;
        UTextBlock* Heading = Cast<UTextBlock>(Tree->FindWidget(TEXT("ChatHeadingText")));
        UTextBlock* TabText = Cast<UTextBlock>(Tree->FindWidget(TEXT("ChatTabText")));
        UHorizontalBox* Composer = Cast<UHorizontalBox>(Tree->FindWidget(TEXT("ChatComposer")));
        if (!Heading || !TabText || !Composer)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI guild catalog update failed: legacy page hierarchy changed."));
            return false;
        }

        const bool AlreadyUpdated =
            Heading->GetText().ToString() == TEXT("KLANLAR")
            && TabText->GetText().ToString() == TEXT("Klanlar")
            && Composer->GetVisibility() == ESlateVisibility::Collapsed;
        if (AlreadyUpdated)
        {
            UE_LOG(LogTemp, Display, TEXT("PALTR_UI_GUILD_PAGE_UPDATE_OK | changed=false"));
            return true;
        }

        Panel->Modify();
        Tree->Modify();
        Heading->Modify();
        TabText->Modify();
        Composer->Modify();
        Heading->SetText(FText::FromString(TEXT("KLANLAR")));
        TabText->SetText(FText::FromString(TEXT("Klanlar")));
        Composer->SetVisibility(ESlateVisibility::Collapsed);

        FBlueprintEditorUtils::MarkBlueprintAsStructurallyModified(Panel);
        FKismetEditorUtilities::CompileBlueprint(Panel);
        if (!SaveAsset(Panel))
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI guild catalog update failed while saving panel."));
            return false;
        }

        UE_LOG(LogTemp, Display, TEXT("PALTR_UI_GUILD_PAGE_UPDATE_OK | changed=true"));
        return true;
    }

    bool UpdateDiplomacyTheme()
    {
        UWidgetBlueprint* Panel = LoadObject<UWidgetBlueprint>(
            nullptr,
            TEXT("/Game/Mods/PalTRUI/WBP_PalTRPanel.WBP_PalTRPanel")
        );
        if (!Panel || !Panel->WidgetTree)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI diplomacy theme update failed: panel asset missing."));
            return false;
        }

        UWidgetTree* Tree = Panel->WidgetTree;
        UVerticalBox* Layout = Cast<UVerticalBox>(Tree->FindWidget(TEXT("PanelLayout")));
        UBorder* Background = Cast<UBorder>(Tree->FindWidget(TEXT("PanelBackground")));
        UHorizontalBox* TabBar = Cast<UHorizontalBox>(Tree->FindWidget(TEXT("TabBar")));
        UWidgetSwitcher* Switcher = Cast<UWidgetSwitcher>(Tree->FindWidget(TEXT("ContentSwitcher")));
        if (!Layout || !Background || !TabBar || !Switcher)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI diplomacy theme update failed: panel hierarchy changed."));
            return false;
        }

        UBorder* TabFrame = Cast<UBorder>(Tree->FindWidget(TEXT("TabFrame")));
        UBorder* ContentFrame = Cast<UBorder>(Tree->FindWidget(TEXT("ContentFrame")));
        const bool HasTabFrame = TabFrame && TabFrame->GetContent() == TabBar;
        const bool HasContentFrame = ContentFrame && ContentFrame->GetContent() == Switcher;
        if ((TabFrame || ContentFrame) && (!HasTabFrame || !HasContentFrame))
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI diplomacy theme update refused: partial theme hierarchy exists."));
            return false;
        }

        Panel->Modify();
        Tree->Modify();
        Layout->Modify();
        Background->Modify();
        Background->SetBrushColor(FLinearColor(0.012f, 0.018f, 0.022f, 0.985f));
        Background->SetPadding(FMargin(20.0f));

        bool Changed = false;
        if (!HasTabFrame)
        {
            if (TabBar->GetParent() != Layout || Switcher->GetParent() != Layout)
            {
                UE_LOG(LogTemp, Error, TEXT("PalTRUI diplomacy theme update failed: expected direct layout children."));
                return false;
            }

            Layout->RemoveChild(TabBar);
            Layout->RemoveChild(Switcher);

            TabFrame = Tree->ConstructWidget<UBorder>(UBorder::StaticClass(), TEXT("TabFrame"));
            TabFrame->SetPadding(FMargin(8.0f, 6.0f));
            TabFrame->SetContent(TabBar);
            AddVertical(Layout, TabFrame, FMargin(0, 0, 0, 12));

            ContentFrame = Tree->ConstructWidget<UBorder>(UBorder::StaticClass(), TEXT("ContentFrame"));
            ContentFrame->SetPadding(FMargin(18.0f));
            ContentFrame->SetContent(Switcher);
            UVerticalBoxSlot* ContentSlot = AddVertical(Layout, ContentFrame);
            ContentSlot->SetSize(FSlateChildSize(ESlateSizeRule::Fill));
            Changed = true;
        }

        TabFrame->Modify();
        ContentFrame->Modify();
        TabFrame->SetBrushColor(FLinearColor(0.025f, 0.075f, 0.085f, 0.98f));
        ContentFrame->SetBrushColor(FLinearColor(0.018f, 0.055f, 0.065f, 0.94f));

        if (UTextBlock* Title = Cast<UTextBlock>(Tree->FindWidget(TEXT("TitleText"))))
        {
            Title->Modify();
            Title->SetText(FText::FromString(TEXT("PALTR DİPLOMASİ MODU")));
            FSlateFontInfo Font = Title->GetFont();
            Font.Size = 28;
            Title->SetFont(Font);
        }

        const FLinearColor Gold(0.92f, 0.68f, 0.25f, 1.0f);
        const FLinearColor Ivory(0.94f, 0.90f, 0.78f, 1.0f);
        for (const FName Heading : {
            FName(TEXT("TitleText")),
            FName(TEXT("ClanHeadingText")),
            FName(TEXT("DiplomacyHeadingText")),
            FName(TEXT("AllianceHeadingText")),
            FName(TEXT("ChatHeadingText"))
        })
        {
            SetTextColor(Tree, Heading, Gold);
        }
        SetTextColor(Tree, TEXT("ConnectionStatusText"), Ivory);

        const FLinearColor Teal(0.055f, 0.24f, 0.27f, 1.0f);
        const FLinearColor Amber(0.30f, 0.20f, 0.07f, 1.0f);
        const FLinearColor Green(0.06f, 0.28f, 0.16f, 1.0f);
        const FLinearColor Red(0.34f, 0.07f, 0.055f, 1.0f);
        for (const FName Tab : {
            FName(TEXT("ClanTabButton")),
            FName(TEXT("DiplomacyTabButton")),
            FName(TEXT("AllianceTabButton")),
            FName(TEXT("ChatTabButton"))
        })
        {
            StyleButton(Tree, Tab, Teal);
        }
        StyleButton(Tree, TEXT("PreviousRelationButton"), Amber);
        StyleButton(Tree, TEXT("NextRelationButton"), Amber);
        StyleButton(Tree, TEXT("AllianceRequestButton"), Teal);
        StyleButton(Tree, TEXT("WarRequestButton"), Red);
        StyleButton(Tree, TEXT("AcceptButton"), Green);
        StyleButton(Tree, TEXT("RejectButton"), Red);
        StyleButton(Tree, TEXT("CancelButton"), Amber);
        StyleButton(Tree, TEXT("CloseButton"), Red);

        FBlueprintEditorUtils::MarkBlueprintAsStructurallyModified(Panel);
        FKismetEditorUtilities::CompileBlueprint(Panel);
        if (!SaveAsset(Panel))
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI diplomacy theme update failed while saving panel."));
            return false;
        }

        UE_LOG(LogTemp, Display, TEXT("PALTR_UI_DIPLOMACY_THEME_UPDATE_OK | changed=%s"), Changed ? TEXT("true") : TEXT("false"));
        return true;
    }

    bool UpdatePendingOffersPanel()
    {
        UWidgetBlueprint* Panel = LoadObject<UWidgetBlueprint>(
            nullptr,
            TEXT("/Game/Mods/PalTRUI/WBP_PalTRPanel.WBP_PalTRPanel")
        );
        if (!Panel || !Panel->WidgetTree)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI pending offers update failed: panel asset missing."));
            return false;
        }

        UWidgetTree* Tree = Panel->WidgetTree;
        UVerticalBox* ClanPage = Cast<UVerticalBox>(Tree->FindWidget(TEXT("ClanPage")));
        UBorder* Frame = Cast<UBorder>(Tree->FindWidget(TEXT("PendingOffersFrame")));
        UTextBlock* Heading = Cast<UTextBlock>(Tree->FindWidget(TEXT("PendingOffersHeadingText")));
        UTextBlock* Offers = Cast<UTextBlock>(Tree->FindWidget(TEXT("PendingOffersText")));
        if (!ClanPage)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI pending offers update failed: clan page missing."));
            return false;
        }
        if (Frame && Heading && Offers)
        {
            UE_LOG(LogTemp, Display, TEXT("PALTR_UI_PENDING_OFFERS_UPDATE_OK | changed=false"));
            return true;
        }
        if (Frame || Heading || Offers)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI pending offers update refused: partial controls exist."));
            return false;
        }

        Panel->Modify();
        Tree->Modify();
        ClanPage->Modify();

        Frame = Tree->ConstructWidget<UBorder>(UBorder::StaticClass(), TEXT("PendingOffersFrame"));
        Frame->SetBrushColor(FLinearColor(0.07f, 0.055f, 0.025f, 0.94f));
        Frame->SetPadding(FMargin(14.0f));

        UVerticalBox* Content = Tree->ConstructWidget<UVerticalBox>(
            UVerticalBox::StaticClass(),
            TEXT("PendingOffersContent")
        );
        Frame->SetContent(Content);
        Heading = MakeText(Tree, TEXT("PendingOffersHeadingText"), TEXT("BEKLEYEN TEKLİFLER"), 20);
        Heading->SetColorAndOpacity(FSlateColor(FLinearColor(0.92f, 0.68f, 0.25f, 1.0f)));
        Offers = MakeText(Tree, TEXT("PendingOffersText"), TEXT("Bekleyen teklif yok."), 16);
        AddVertical(Content, Heading, FMargin(0, 0, 0, 10));
        AddVertical(Content, Offers);
        AddVertical(ClanPage, Frame, FMargin(0, 22, 0, 0));

        FBlueprintEditorUtils::MarkBlueprintAsStructurallyModified(Panel);
        FKismetEditorUtilities::CompileBlueprint(Panel);
        if (!SaveAsset(Panel))
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI pending offers update failed while saving panel."));
            return false;
        }

        UE_LOG(LogTemp, Display, TEXT("PALTR_UI_PENDING_OFFERS_UPDATE_OK | changed=true"));
        return true;
    }

    bool UpdateDashboardQuickActions()
    {
        UWidgetBlueprint* Panel = LoadObject<UWidgetBlueprint>(
            nullptr,
            TEXT("/Game/Mods/PalTRUI/WBP_PalTRPanel.WBP_PalTRPanel")
        );
        if (!Panel || !Panel->WidgetTree)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI quick actions update failed: panel asset missing."));
            return false;
        }

        UWidgetTree* Tree = Panel->WidgetTree;
        UVerticalBox* ClanPage = Cast<UVerticalBox>(Tree->FindWidget(TEXT("ClanPage")));
        static const FName QuickActionWidgets[] = {
            TEXT("DashboardQuickActionsFrame"),
            TEXT("DashboardQuickActionsContent"),
            TEXT("DashboardQuickActionsHeadingText"),
            TEXT("DashboardDiplomacyButton"),
            TEXT("DashboardDiplomacyButtonText"),
            TEXT("DashboardOffersButton"),
            TEXT("DashboardOffersButtonText"),
            TEXT("DashboardGuildsButton"),
            TEXT("DashboardGuildsButtonText")
        };

        if (!ClanPage)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI quick actions update failed: clan page missing."));
            return false;
        }

        int32 ExistingWidgetCount = 0;
        for (const FName WidgetName : QuickActionWidgets)
        {
            ExistingWidgetCount += Tree->FindWidget(WidgetName) ? 1 : 0;
        }
        if (ExistingWidgetCount == UE_ARRAY_COUNT(QuickActionWidgets))
        {
            UE_LOG(LogTemp, Display, TEXT("PALTR_UI_QUICK_ACTIONS_UPDATE_OK | changed=false"));
            return true;
        }
        if (ExistingWidgetCount != 0)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI quick actions update refused: partial controls exist."));
            return false;
        }

        Panel->Modify();
        Tree->Modify();
        ClanPage->Modify();

        UBorder* Frame = Tree->ConstructWidget<UBorder>(
            UBorder::StaticClass(),
            TEXT("DashboardQuickActionsFrame")
        );
        Frame->SetBrushColor(FLinearColor(0.025f, 0.075f, 0.095f, 0.96f));
        Frame->SetPadding(FMargin(14.0f));

        UVerticalBox* Content = Tree->ConstructWidget<UVerticalBox>(
            UVerticalBox::StaticClass(),
            TEXT("DashboardQuickActionsContent")
        );
        Frame->SetContent(Content);

        UTextBlock* Heading = MakeText(
            Tree,
            TEXT("DashboardQuickActionsHeadingText"),
            TEXT("HIZLI ISLEMLER"),
            20
        );
        Heading->SetColorAndOpacity(FSlateColor(FLinearColor(0.92f, 0.68f, 0.25f, 1.0f)));
        AddVertical(Content, Heading, FMargin(0, 0, 0, 10));

        AddVertical(
            Content,
            MakeTabButton(Tree, TEXT("DashboardDiplomacyButton"), TEXT("DashboardDiplomacyButtonText"), TEXT("Diplomasiyi Ac")),
            FMargin(0, 0, 0, 8)
        );
        AddVertical(
            Content,
            MakeTabButton(Tree, TEXT("DashboardOffersButton"), TEXT("DashboardOffersButtonText"), TEXT("Teklifleri Gor")),
            FMargin(0, 0, 0, 8)
        );
        AddVertical(
            Content,
            MakeTabButton(Tree, TEXT("DashboardGuildsButton"), TEXT("DashboardGuildsButtonText"), TEXT("Klanlari Listele"))
        );
        AddVertical(ClanPage, Frame, FMargin(0, 18, 0, 0));

        const FLinearColor Teal(0.04f, 0.35f, 0.42f, 1.0f);
        StyleButton(Tree, TEXT("DashboardDiplomacyButton"), Teal);
        StyleButton(Tree, TEXT("DashboardOffersButton"), Teal);
        StyleButton(Tree, TEXT("DashboardGuildsButton"), Teal);

        FBlueprintEditorUtils::MarkBlueprintAsStructurallyModified(Panel);
        FKismetEditorUtilities::CompileBlueprint(Panel);
        if (!SaveAsset(Panel))
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI quick actions update failed while saving panel."));
            return false;
        }

        UE_LOG(LogTemp, Display, TEXT("PALTR_UI_QUICK_ACTIONS_UPDATE_OK | changed=true"));
        return true;
    }

    bool UpdateDashboardStatusCards()
    {
        UWidgetBlueprint* Panel = LoadObject<UWidgetBlueprint>(
            nullptr,
            TEXT("/Game/Mods/PalTRUI/WBP_PalTRPanel.WBP_PalTRPanel")
        );
        if (!Panel || !Panel->WidgetTree)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI status cards update failed: panel asset missing."));
            return false;
        }

        UWidgetTree* Tree = Panel->WidgetTree;
        UVerticalBox* ClanPage = Cast<UVerticalBox>(Tree->FindWidget(TEXT("ClanPage")));
        static const FName StatusCardWidgets[] = {
            TEXT("DashboardStatusCardsFrame"),
            TEXT("DashboardClanCardFrame"),
            TEXT("DashboardClanCardContent"),
            TEXT("DashboardClanCardTitleText"),
            TEXT("DashboardClanCardValueText"),
            TEXT("DashboardClanCardDetailText"),
            TEXT("DashboardDiplomacyCardFrame"),
            TEXT("DashboardDiplomacyCardContent"),
            TEXT("DashboardDiplomacyCardTitleText"),
            TEXT("DashboardDiplomacyCardValueText"),
            TEXT("DashboardDiplomacyCardDetailText")
        };
        if (!ClanPage)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI status cards update failed: clan page missing."));
            return false;
        }

        int32 ExistingWidgetCount = 0;
        for (const FName WidgetName : StatusCardWidgets)
        {
            ExistingWidgetCount += Tree->FindWidget(WidgetName) ? 1 : 0;
        }
        if (ExistingWidgetCount == UE_ARRAY_COUNT(StatusCardWidgets))
        {
            UE_LOG(LogTemp, Display, TEXT("PALTR_UI_STATUS_CARDS_UPDATE_OK | changed=false"));
            return true;
        }
        if (ExistingWidgetCount != 0)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI status cards update refused: partial controls exist."));
            return false;
        }

        UTextBlock* LegacyName = Cast<UTextBlock>(Tree->FindWidget(TEXT("ClanNameText")));
        UTextBlock* LegacySummary = Cast<UTextBlock>(Tree->FindWidget(TEXT("ClanSummaryText")));
        if (!LegacyName || !LegacySummary)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI status cards update failed: legacy clan summary missing."));
            return false;
        }

        Panel->Modify();
        Tree->Modify();
        ClanPage->Modify();
        LegacyName->Modify();
        LegacySummary->Modify();

        UHorizontalBox* Cards = Tree->ConstructWidget<UHorizontalBox>(
            UHorizontalBox::StaticClass(),
            TEXT("DashboardStatusCardsFrame")
        );

        const FLinearColor ClanColor(0.025f, 0.20f, 0.18f, 0.96f);
        UBorder* ClanFrame = Tree->ConstructWidget<UBorder>(
            UBorder::StaticClass(),
            TEXT("DashboardClanCardFrame")
        );
        ClanFrame->SetBrushColor(ClanColor);
        ClanFrame->SetPadding(FMargin(16.0f));
        UVerticalBox* ClanContent = Tree->ConstructWidget<UVerticalBox>(
            UVerticalBox::StaticClass(),
            TEXT("DashboardClanCardContent")
        );
        ClanFrame->SetContent(ClanContent);
        UTextBlock* ClanTitle = MakeText(Tree, TEXT("DashboardClanCardTitleText"), TEXT("KLANIM"), 18);
        ClanTitle->SetColorAndOpacity(FSlateColor(FLinearColor(0.35f, 0.90f, 0.82f, 1.0f)));
        AddVertical(ClanContent, ClanTitle, FMargin(0, 0, 0, 8));
        AddVertical(ClanContent, MakeText(Tree, TEXT("DashboardClanCardValueText"), TEXT("-"), 24), FMargin(0, 0, 0, 8));
        AddVertical(ClanContent, MakeText(Tree, TEXT("DashboardClanCardDetailText"), TEXT("Klan bilgisi bekleniyor."), 15));
        UHorizontalBoxSlot* ClanSlot = AddHorizontal(Cards, ClanFrame, FMargin(0, 0, 8, 0));
        ClanSlot->SetSize(FSlateChildSize(ESlateSizeRule::Fill));

        const FLinearColor DiplomacyColor(0.035f, 0.13f, 0.20f, 0.96f);
        UBorder* DiplomacyFrame = Tree->ConstructWidget<UBorder>(
            UBorder::StaticClass(),
            TEXT("DashboardDiplomacyCardFrame")
        );
        DiplomacyFrame->SetBrushColor(DiplomacyColor);
        DiplomacyFrame->SetPadding(FMargin(16.0f));
        UVerticalBox* DiplomacyContent = Tree->ConstructWidget<UVerticalBox>(
            UVerticalBox::StaticClass(),
            TEXT("DashboardDiplomacyCardContent")
        );
        DiplomacyFrame->SetContent(DiplomacyContent);
        UTextBlock* DiplomacyTitle = MakeText(Tree, TEXT("DashboardDiplomacyCardTitleText"), TEXT("DIPLOMASI"), 18);
        DiplomacyTitle->SetColorAndOpacity(FSlateColor(FLinearColor(0.92f, 0.68f, 0.25f, 1.0f)));
        AddVertical(DiplomacyContent, DiplomacyTitle, FMargin(0, 0, 0, 8));
        AddVertical(DiplomacyContent, MakeText(Tree, TEXT("DashboardDiplomacyCardValueText"), TEXT("Savas: 0 | Ittifak: 0 | Bekleyen: 0"), 18), FMargin(0, 0, 0, 8));
        AddVertical(DiplomacyContent, MakeText(Tree, TEXT("DashboardDiplomacyCardDetailText"), TEXT(""), 15));
        UHorizontalBoxSlot* DiplomacySlot = AddHorizontal(Cards, DiplomacyFrame, FMargin(8, 0, 0, 0));
        DiplomacySlot->SetSize(FSlateChildSize(ESlateSizeRule::Fill));

        UVerticalBoxSlot* CardsSlot = Cast<UVerticalBoxSlot>(ClanPage->InsertChildAt(1, Cards));
        if (!CardsSlot)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI status cards update failed: card slot could not be inserted."));
            return false;
        }
        CardsSlot->SetPadding(FMargin(0, 0, 0, 16));
        CardsSlot->SetHorizontalAlignment(HAlign_Fill);
        LegacyName->SetVisibility(ESlateVisibility::Collapsed);
        LegacySummary->SetVisibility(ESlateVisibility::Collapsed);

        FBlueprintEditorUtils::MarkBlueprintAsStructurallyModified(Panel);
        FKismetEditorUtilities::CompileBlueprint(Panel);
        if (!SaveAsset(Panel))
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI status cards update failed while saving panel."));
            return false;
        }

        UE_LOG(LogTemp, Display, TEXT("PALTR_UI_STATUS_CARDS_UPDATE_OK | changed=true"));
        return true;
    }

    bool UpdateDashboardRelationsPreview()
    {
        UWidgetBlueprint* Panel = LoadObject<UWidgetBlueprint>(
            nullptr,
            TEXT("/Game/Mods/PalTRUI/WBP_PalTRPanel.WBP_PalTRPanel")
        );
        if (!Panel || !Panel->WidgetTree)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI relations preview update failed: panel asset missing."));
            return false;
        }

        UWidgetTree* Tree = Panel->WidgetTree;
        UVerticalBox* ClanPage = Cast<UVerticalBox>(Tree->FindWidget(TEXT("ClanPage")));
        UBorder* Frame = Cast<UBorder>(Tree->FindWidget(TEXT("DashboardRelationsFrame")));
        UVerticalBox* Content = Cast<UVerticalBox>(Tree->FindWidget(TEXT("DashboardRelationsContent")));
        UTextBlock* Heading = Cast<UTextBlock>(Tree->FindWidget(TEXT("DashboardRelationsHeadingText")));
        UTextBlock* Relations = Cast<UTextBlock>(Tree->FindWidget(TEXT("DashboardRelationsText")));
        if (!ClanPage)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI relations preview update failed: clan page missing."));
            return false;
        }
        if (Frame && Content && Heading && Relations)
        {
            UE_LOG(LogTemp, Display, TEXT("PALTR_UI_RELATIONS_PREVIEW_UPDATE_OK | changed=false"));
            return true;
        }
        if (Frame || Content || Heading || Relations)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI relations preview update refused: partial controls exist."));
            return false;
        }

        Panel->Modify();
        Tree->Modify();
        ClanPage->Modify();
        Frame = Tree->ConstructWidget<UBorder>(
            UBorder::StaticClass(),
            TEXT("DashboardRelationsFrame")
        );
        Frame->SetBrushColor(FLinearColor(0.06f, 0.05f, 0.025f, 0.94f));
        Frame->SetPadding(FMargin(14.0f));
        Content = Tree->ConstructWidget<UVerticalBox>(
            UVerticalBox::StaticClass(),
            TEXT("DashboardRelationsContent")
        );
        Frame->SetContent(Content);
        Heading = MakeText(Tree, TEXT("DashboardRelationsHeadingText"), TEXT("ILISKILER"), 20);
        Heading->SetColorAndOpacity(FSlateColor(FLinearColor(0.92f, 0.68f, 0.25f, 1.0f)));
        Relations = MakeText(Tree, TEXT("DashboardRelationsText"), TEXT("Iliski kaydi yok."), 16);
        AddVertical(Content, Heading, FMargin(0, 0, 0, 8));
        AddVertical(Content, Relations);

        UVerticalBoxSlot* PreviewSlot = Cast<UVerticalBoxSlot>(ClanPage->InsertChildAt(2, Frame));
        if (!PreviewSlot)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI relations preview update failed: slot could not be inserted."));
            return false;
        }
        PreviewSlot->SetPadding(FMargin(0, 0, 0, 14));
        PreviewSlot->SetHorizontalAlignment(HAlign_Fill);

        FBlueprintEditorUtils::MarkBlueprintAsStructurallyModified(Panel);
        FKismetEditorUtilities::CompileBlueprint(Panel);
        if (!SaveAsset(Panel))
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI relations preview update failed while saving panel."));
            return false;
        }
        UE_LOG(LogTemp, Display, TEXT("PALTR_UI_RELATIONS_PREVIEW_UPDATE_OK | changed=true"));
        return true;
    }

    bool UpdateAllianceDetailPanel()
    {
        UWidgetBlueprint* Panel = LoadObject<UWidgetBlueprint>(
            nullptr,
            TEXT("/Game/Mods/PalTRUI/WBP_PalTRPanel.WBP_PalTRPanel")
        );
        if (!Panel || !Panel->WidgetTree)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI alliance detail update failed: panel asset missing."));
            return false;
        }

        UWidgetTree* Tree = Panel->WidgetTree;
        UVerticalBox* AlliancePage = Cast<UVerticalBox>(Tree->FindWidget(TEXT("AlliancePage")));
        static const FName DetailWidgets[] = {
            TEXT("AllianceDetailFrame"),
            TEXT("AllianceDetailContent"),
            TEXT("AllianceTitleText"),
            TEXT("AllianceStateText"),
            TEXT("AllianceDescriptionText"),
            TEXT("AllianceNavigation"),
            TEXT("PreviousAllianceButton"),
            TEXT("PreviousAllianceButtonText"),
            TEXT("NextAllianceButton"),
            TEXT("NextAllianceButtonText")
        };
        if (!AlliancePage)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI alliance detail update failed: alliance page missing."));
            return false;
        }
        int32 ExistingWidgetCount = 0;
        for (const FName WidgetName : DetailWidgets)
        {
            ExistingWidgetCount += Tree->FindWidget(WidgetName) ? 1 : 0;
        }
        if (ExistingWidgetCount == UE_ARRAY_COUNT(DetailWidgets))
        {
            UE_LOG(LogTemp, Display, TEXT("PALTR_UI_ALLIANCE_DETAIL_UPDATE_OK | changed=false"));
            return true;
        }
        if (ExistingWidgetCount != 0)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI alliance detail update refused: partial controls exist."));
            return false;
        }

        Panel->Modify();
        Tree->Modify();
        AlliancePage->Modify();
        UBorder* Frame = Tree->ConstructWidget<UBorder>(
            UBorder::StaticClass(),
            TEXT("AllianceDetailFrame")
        );
        Frame->SetBrushColor(FLinearColor(0.025f, 0.12f, 0.18f, 0.96f));
        Frame->SetPadding(FMargin(16.0f));
        UVerticalBox* Content = Tree->ConstructWidget<UVerticalBox>(
            UVerticalBox::StaticClass(),
            TEXT("AllianceDetailContent")
        );
        Frame->SetContent(Content);
        UTextBlock* Title = MakeText(Tree, TEXT("AllianceTitleText"), TEXT("Ittifak secin"), 24);
        Title->SetColorAndOpacity(FSlateColor(FLinearColor(0.92f, 0.68f, 0.25f, 1.0f)));
        AddVertical(Content, Title, FMargin(0, 0, 0, 8));
        AddVertical(Content, MakeText(Tree, TEXT("AllianceStateText"), TEXT("Ittifak durumu: -"), 18), FMargin(0, 0, 0, 8));
        AddVertical(Content, MakeText(Tree, TEXT("AllianceDescriptionText"), TEXT("Ittifak ayrintisi yok."), 16), FMargin(0, 0, 0, 12));
        UHorizontalBox* Navigation = Tree->ConstructWidget<UHorizontalBox>(
            UHorizontalBox::StaticClass(),
            TEXT("AllianceNavigation")
        );
        AddHorizontal(Navigation, MakeTabButton(Tree, TEXT("PreviousAllianceButton"), TEXT("PreviousAllianceButtonText"), TEXT("Onceki")), FMargin(0, 0, 8, 0));
        AddHorizontal(Navigation, MakeTabButton(Tree, TEXT("NextAllianceButton"), TEXT("NextAllianceButtonText"), TEXT("Sonraki")));
        AddVertical(Content, Navigation);
        StyleButton(Tree, TEXT("PreviousAllianceButton"), FLinearColor(0.42f, 0.25f, 0.06f, 1.0f));
        StyleButton(Tree, TEXT("NextAllianceButton"), FLinearColor(0.42f, 0.25f, 0.06f, 1.0f));

        UVerticalBoxSlot* DetailSlot = Cast<UVerticalBoxSlot>(AlliancePage->InsertChildAt(2, Frame));
        if (!DetailSlot)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI alliance detail update failed: slot could not be inserted."));
            return false;
        }
        DetailSlot->SetPadding(FMargin(0, 0, 0, 14));
        DetailSlot->SetHorizontalAlignment(HAlign_Fill);
        FBlueprintEditorUtils::MarkBlueprintAsStructurallyModified(Panel);
        FKismetEditorUtilities::CompileBlueprint(Panel);
        if (!SaveAsset(Panel))
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI alliance detail update failed while saving panel."));
            return false;
        }
        UE_LOG(LogTemp, Display, TEXT("PALTR_UI_ALLIANCE_DETAIL_UPDATE_OK | changed=true"));
        return true;
    }

    bool UpdateGuildCatalogCards()
    {
        UWidgetBlueprint* Panel = LoadObject<UWidgetBlueprint>(
            nullptr,
            TEXT("/Game/Mods/PalTRUI/WBP_PalTRPanel.WBP_PalTRPanel")
        );
        if (!Panel || !Panel->WidgetTree)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI guild cards update failed: panel asset missing."));
            return false;
        }
        UWidgetTree* Tree = Panel->WidgetTree;
        UVerticalBox* GuildPage = Cast<UVerticalBox>(Tree->FindWidget(TEXT("ChatPage")));
        UScrollBox* LegacyList = Cast<UScrollBox>(Tree->FindWidget(TEXT("ChatMessageList")));
        static const FName GuildCardWidgets[] = {
            TEXT("GuildCatalogSummaryText"),
            TEXT("GuildCatalogColumns"),
            TEXT("GuildCatalogActiveFrame"),
            TEXT("GuildCatalogActiveContent"),
            TEXT("GuildCatalogActiveHeadingText"),
            TEXT("GuildCatalogActiveText"),
            TEXT("GuildCatalogRegisteredFrame"),
            TEXT("GuildCatalogRegisteredContent"),
            TEXT("GuildCatalogRegisteredHeadingText"),
            TEXT("GuildCatalogRegisteredText")
        };
        if (!GuildPage || !LegacyList)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI guild cards update failed: guild page hierarchy missing."));
            return false;
        }
        int32 ExistingWidgetCount = 0;
        for (const FName WidgetName : GuildCardWidgets)
        {
            ExistingWidgetCount += Tree->FindWidget(WidgetName) ? 1 : 0;
        }
        if (ExistingWidgetCount == UE_ARRAY_COUNT(GuildCardWidgets))
        {
            UE_LOG(LogTemp, Display, TEXT("PALTR_UI_GUILD_CARDS_UPDATE_OK | changed=false"));
            return true;
        }
        if (ExistingWidgetCount != 0)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI guild cards update refused: partial controls exist."));
            return false;
        }

        Panel->Modify();
        Tree->Modify();
        GuildPage->Modify();
        LegacyList->Modify();
        UTextBlock* Summary = MakeText(Tree, TEXT("GuildCatalogSummaryText"), TEXT("0 klan | 0 aktif"), 18);
        Summary->SetColorAndOpacity(FSlateColor(FLinearColor(0.92f, 0.68f, 0.25f, 1.0f)));
        UVerticalBoxSlot* SummarySlot = Cast<UVerticalBoxSlot>(GuildPage->InsertChildAt(1, Summary));
        if (!SummarySlot)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI guild cards update failed: summary slot missing."));
            return false;
        }
        SummarySlot->SetPadding(FMargin(0, 0, 0, 14));

        UHorizontalBox* Columns = Tree->ConstructWidget<UHorizontalBox>(
            UHorizontalBox::StaticClass(),
            TEXT("GuildCatalogColumns")
        );
        UBorder* ActiveFrame = Tree->ConstructWidget<UBorder>(
            UBorder::StaticClass(),
            TEXT("GuildCatalogActiveFrame")
        );
        ActiveFrame->SetBrushColor(FLinearColor(0.025f, 0.20f, 0.18f, 0.96f));
        ActiveFrame->SetPadding(FMargin(16.0f));
        UVerticalBox* ActiveContent = Tree->ConstructWidget<UVerticalBox>(
            UVerticalBox::StaticClass(),
            TEXT("GuildCatalogActiveContent")
        );
        ActiveFrame->SetContent(ActiveContent);
        UTextBlock* ActiveHeading = MakeText(Tree, TEXT("GuildCatalogActiveHeadingText"), TEXT("AKTIF KLANLAR"), 20);
        ActiveHeading->SetColorAndOpacity(FSlateColor(FLinearColor(0.35f, 0.90f, 0.82f, 1.0f)));
        AddVertical(ActiveContent, ActiveHeading, FMargin(0, 0, 0, 10));
        AddVertical(ActiveContent, MakeText(Tree, TEXT("GuildCatalogActiveText"), TEXT("Aktif klan yok."), 16));
        UHorizontalBoxSlot* ActiveSlot = AddHorizontal(Columns, ActiveFrame, FMargin(0, 0, 8, 0));
        ActiveSlot->SetSize(FSlateChildSize(ESlateSizeRule::Fill));

        UBorder* RegisteredFrame = Tree->ConstructWidget<UBorder>(
            UBorder::StaticClass(),
            TEXT("GuildCatalogRegisteredFrame")
        );
        RegisteredFrame->SetBrushColor(FLinearColor(0.06f, 0.05f, 0.025f, 0.94f));
        RegisteredFrame->SetPadding(FMargin(16.0f));
        UVerticalBox* RegisteredContent = Tree->ConstructWidget<UVerticalBox>(
            UVerticalBox::StaticClass(),
            TEXT("GuildCatalogRegisteredContent")
        );
        RegisteredFrame->SetContent(RegisteredContent);
        UTextBlock* RegisteredHeading = MakeText(Tree, TEXT("GuildCatalogRegisteredHeadingText"), TEXT("KAYITLI KLANLAR"), 20);
        RegisteredHeading->SetColorAndOpacity(FSlateColor(FLinearColor(0.92f, 0.68f, 0.25f, 1.0f)));
        AddVertical(RegisteredContent, RegisteredHeading, FMargin(0, 0, 0, 10));
        AddVertical(RegisteredContent, MakeText(Tree, TEXT("GuildCatalogRegisteredText"), TEXT("Kayitli klan yok."), 16));
        UHorizontalBoxSlot* RegisteredSlot = AddHorizontal(Columns, RegisteredFrame, FMargin(8, 0, 0, 0));
        RegisteredSlot->SetSize(FSlateChildSize(ESlateSizeRule::Fill));

        UVerticalBoxSlot* ColumnsSlot = Cast<UVerticalBoxSlot>(GuildPage->InsertChildAt(2, Columns));
        if (!ColumnsSlot)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI guild cards update failed: columns slot missing."));
            return false;
        }
        ColumnsSlot->SetHorizontalAlignment(HAlign_Fill);
        ColumnsSlot->SetSize(FSlateChildSize(ESlateSizeRule::Fill));
        LegacyList->SetVisibility(ESlateVisibility::Collapsed);

        FBlueprintEditorUtils::MarkBlueprintAsStructurallyModified(Panel);
        FKismetEditorUtilities::CompileBlueprint(Panel);
        if (!SaveAsset(Panel))
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI guild cards update failed while saving panel."));
            return false;
        }
        UE_LOG(LogTemp, Display, TEXT("PALTR_UI_GUILD_CARDS_UPDATE_OK | changed=true"));
        return true;
    }

    bool UpdateHeaderStatusBadges()
    {
        UWidgetBlueprint* Panel = LoadObject<UWidgetBlueprint>(
            nullptr,
            TEXT("/Game/Mods/PalTRUI/WBP_PalTRPanel.WBP_PalTRPanel")
        );
        if (!Panel || !Panel->WidgetTree)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI header badges update failed: panel asset missing."));
            return false;
        }
        UWidgetTree* Tree = Panel->WidgetTree;
        UHorizontalBox* Header = Cast<UHorizontalBox>(Tree->FindWidget(TEXT("HeaderRow")));
        UBorder* GuildFrame = Cast<UBorder>(Tree->FindWidget(TEXT("HeaderGuildFrame")));
        UTextBlock* GuildText = Cast<UTextBlock>(Tree->FindWidget(TEXT("HeaderGuildText")));
        UBorder* RoleFrame = Cast<UBorder>(Tree->FindWidget(TEXT("HeaderRoleFrame")));
        UTextBlock* RoleText = Cast<UTextBlock>(Tree->FindWidget(TEXT("HeaderRoleText")));
        UBorder* NotificationFrame = Cast<UBorder>(Tree->FindWidget(TEXT("HeaderNotificationFrame")));
        UTextBlock* NotificationText = Cast<UTextBlock>(Tree->FindWidget(TEXT("HeaderNotificationText")));
        if (!Header)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI header badges update failed: header row missing."));
            return false;
        }
        if (GuildFrame && GuildText && RoleFrame && RoleText
            && NotificationFrame && NotificationText)
        {
            UE_LOG(LogTemp, Display, TEXT("PALTR_UI_HEADER_BADGES_UPDATE_OK | changed=false"));
            return true;
        }
        if (GuildFrame || GuildText || RoleFrame || RoleText
            || NotificationFrame || NotificationText)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI header badges update refused: partial controls exist."));
            return false;
        }

        Panel->Modify();
        Tree->Modify();
        Header->Modify();
        GuildFrame = Tree->ConstructWidget<UBorder>(
            UBorder::StaticClass(),
            TEXT("HeaderGuildFrame")
        );
        GuildFrame->SetBrushColor(FLinearColor(0.025f, 0.18f, 0.20f, 0.96f));
        GuildFrame->SetPadding(FMargin(10.0f, 6.0f));
        GuildText = MakeText(Tree, TEXT("HeaderGuildText"), TEXT("Klan: -"), 15);
        GuildText->SetColorAndOpacity(FSlateColor(FLinearColor(0.35f, 0.90f, 0.82f, 1.0f)));
        GuildFrame->SetContent(GuildText);
        UHorizontalBoxSlot* GuildSlot = Cast<UHorizontalBoxSlot>(Header->InsertChildAt(1, GuildFrame));
        if (!GuildSlot)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI header badges update failed: guild slot missing."));
            return false;
        }
        GuildSlot->SetPadding(FMargin(0, 0, 8, 0));
        GuildSlot->SetVerticalAlignment(VAlign_Center);

        RoleFrame = Tree->ConstructWidget<UBorder>(
            UBorder::StaticClass(),
            TEXT("HeaderRoleFrame")
        );
        RoleFrame->SetBrushColor(FLinearColor(0.20f, 0.12f, 0.025f, 0.96f));
        RoleFrame->SetPadding(FMargin(10.0f, 6.0f));
        RoleText = MakeText(Tree, TEXT("HeaderRoleText"), TEXT("Yetki: -"), 15);
        RoleText->SetColorAndOpacity(FSlateColor(FLinearColor(0.92f, 0.68f, 0.25f, 1.0f)));
        RoleFrame->SetContent(RoleText);
        UHorizontalBoxSlot* RoleSlot = Cast<UHorizontalBoxSlot>(Header->InsertChildAt(2, RoleFrame));
        if (!RoleSlot)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI header badges update failed: role slot missing."));
            return false;
        }
        RoleSlot->SetPadding(FMargin(0, 0, 12, 0));
        RoleSlot->SetVerticalAlignment(VAlign_Center);

        NotificationFrame = Tree->ConstructWidget<UBorder>(
            UBorder::StaticClass(),
            TEXT("HeaderNotificationFrame")
        );
        NotificationFrame->SetBrushColor(FLinearColor(0.32f, 0.055f, 0.035f, 0.96f));
        NotificationFrame->SetPadding(FMargin(10.0f, 6.0f));
        NotificationText = MakeText(Tree, TEXT("HeaderNotificationText"), TEXT("Bildirim: 0"), 15);
        NotificationText->SetColorAndOpacity(FSlateColor(FLinearColor(1.0f, 0.82f, 0.68f, 1.0f)));
        NotificationFrame->SetContent(NotificationText);
        UHorizontalBoxSlot* NotificationSlot = Cast<UHorizontalBoxSlot>(Header->InsertChildAt(3, NotificationFrame));
        if (!NotificationSlot)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI header badges update failed: notification slot missing."));
            return false;
        }
        NotificationSlot->SetPadding(FMargin(0, 0, 12, 0));
        NotificationSlot->SetVerticalAlignment(VAlign_Center);

        FBlueprintEditorUtils::MarkBlueprintAsStructurallyModified(Panel);
        FKismetEditorUtilities::CompileBlueprint(Panel);
        if (!SaveAsset(Panel))
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI header badges update failed while saving panel."));
            return false;
        }
        UE_LOG(LogTemp, Display, TEXT("PALTR_UI_HEADER_BADGES_UPDATE_OK | changed=true"));
        return true;
    }

    bool UpdateClanPageScroll()
    {
        UWidgetBlueprint* Panel = LoadObject<UWidgetBlueprint>(
            nullptr,
            TEXT("/Game/Mods/PalTRUI/WBP_PalTRPanel.WBP_PalTRPanel")
        );
        if (!Panel || !Panel->WidgetTree)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI clan scroll update failed: panel asset missing."));
            return false;
        }

        UWidgetTree* Tree = Panel->WidgetTree;
        UWidgetSwitcher* Switcher = Cast<UWidgetSwitcher>(
            Tree->FindWidget(TEXT("ContentSwitcher"))
        );
        UVerticalBox* ClanPage = Cast<UVerticalBox>(
            Tree->FindWidget(TEXT("ClanPage"))
        );
        UScrollBox* Scroll = Cast<UScrollBox>(
            Tree->FindWidget(TEXT("ClanPageScroll"))
        );
        if (!Switcher || !ClanPage)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI clan scroll update failed: switcher or clan page missing."));
            return false;
        }
        if (Scroll && Scroll->GetChildAt(0) == ClanPage
            && Scroll->GetParent() == Switcher)
        {
            Panel->Modify();
            Scroll->Modify();
            Scroll->SetConsumeMouseWheel(EConsumeMouseWheel::Always);
            Scroll->SetAllowOverscroll(false);
            FBlueprintEditorUtils::MarkBlueprintAsStructurallyModified(Panel);
            FKismetEditorUtilities::CompileBlueprint(Panel);
            if (!SaveAsset(Panel))
            {
                UE_LOG(LogTemp, Error, TEXT("PalTRUI clan scroll input update failed while saving panel."));
                return false;
            }
            UE_LOG(LogTemp, Display, TEXT("PALTR_UI_CLAN_SCROLL_UPDATE_OK | changed=true | consume_wheel=always"));
            return true;
        }
        if (Scroll || ClanPage->GetParent() != Switcher)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI clan scroll update refused: partial or unexpected hierarchy."));
            return false;
        }

        const int32 PageIndex = Switcher->GetChildIndex(ClanPage);
        if (PageIndex < 0)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI clan scroll update failed: page index missing."));
            return false;
        }
        const int32 ActiveIndex = Switcher->GetActiveWidgetIndex();

        Panel->Modify();
        Tree->Modify();
        Switcher->Modify();
        ClanPage->Modify();
        Switcher->RemoveChild(ClanPage);

        Scroll = Tree->ConstructWidget<UScrollBox>(
            UScrollBox::StaticClass(),
            TEXT("ClanPageScroll")
        );
        Scroll->SetScrollBarVisibility(ESlateVisibility::Visible);
        Scroll->SetScrollbarThickness(FVector2D(7.0f, 7.0f));
        Scroll->SetAlwaysShowScrollbar(false);
        Scroll->SetConsumeMouseWheel(EConsumeMouseWheel::Always);
        Scroll->SetAllowOverscroll(false);
        Scroll->AddChild(ClanPage);
        if (!Switcher->InsertChildAt(PageIndex, Scroll))
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI clan scroll update failed: scroll slot could not be inserted."));
            return false;
        }
        Switcher->SetActiveWidgetIndex(ActiveIndex);

        FBlueprintEditorUtils::MarkBlueprintAsStructurallyModified(Panel);
        FKismetEditorUtilities::CompileBlueprint(Panel);
        if (!SaveAsset(Panel))
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI clan scroll update failed while saving panel."));
            return false;
        }
        UE_LOG(LogTemp, Display, TEXT("PALTR_UI_CLAN_SCROLL_UPDATE_OK | changed=true"));
        return true;
    }

    bool UpdateAllPageScrollInput()
    {
        UWidgetBlueprint* Panel = LoadObject<UWidgetBlueprint>(
            nullptr,
            TEXT("/Game/Mods/PalTRUI/WBP_PalTRPanel.WBP_PalTRPanel")
        );
        if (!Panel || !Panel->WidgetTree)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI page scroll input update failed: panel asset missing."));
            return false;
        }

        UWidgetTree* Tree = Panel->WidgetTree;
        UWidgetSwitcher* Switcher = Cast<UWidgetSwitcher>(Tree->FindWidget(TEXT("ContentSwitcher")));
        if (!Switcher)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI page scroll input update failed: content switcher missing."));
            return false;
        }

        struct FPageScrollSpec
        {
            const TCHAR* PageName;
            const TCHAR* ScrollName;
        };
        static const FPageScrollSpec PageSpecs[] = {
            { TEXT("ClanPage"), TEXT("ClanPageScroll") },
            { TEXT("DiplomacyPage"), TEXT("DiplomacyPageScroll") },
            { TEXT("AlliancePage"), TEXT("AlliancePageScroll") },
            { TEXT("ChatPage"), TEXT("GuildPageScroll") }
        };

        Panel->Modify();
        Tree->Modify();
        Switcher->Modify();
        const int32 ActiveIndex = Switcher->GetActiveWidgetIndex();

        for (const FPageScrollSpec& Spec : PageSpecs)
        {
            UVerticalBox* Page = Cast<UVerticalBox>(Tree->FindWidget(FName(Spec.PageName)));
            UScrollBox* Scroll = Cast<UScrollBox>(Tree->FindWidget(FName(Spec.ScrollName)));
            if (!Page)
            {
                UE_LOG(LogTemp, Error, TEXT("PalTRUI page scroll input update failed: page missing: %s"), Spec.PageName);
                return false;
            }

            if (Scroll)
            {
                if (Scroll->GetChildrenCount() != 1
                    || Scroll->GetChildAt(0) != Page
                    || Scroll->GetParent() != Switcher)
                {
                    UE_LOG(LogTemp, Error, TEXT("PalTRUI page scroll input update refused: unexpected hierarchy: %s"), Spec.ScrollName);
                    return false;
                }
            }
            else
            {
                if (Page->GetParent() != Switcher)
                {
                    UE_LOG(LogTemp, Error, TEXT("PalTRUI page scroll input update refused: page is outside switcher: %s"), Spec.PageName);
                    return false;
                }
                const int32 PageIndex = Switcher->GetChildIndex(Page);
                if (PageIndex < 0)
                {
                    UE_LOG(LogTemp, Error, TEXT("PalTRUI page scroll input update failed: page index missing: %s"), Spec.PageName);
                    return false;
                }

                Page->Modify();
                Switcher->RemoveChild(Page);
                Scroll = Tree->ConstructWidget<UScrollBox>(UScrollBox::StaticClass(), FName(Spec.ScrollName));
                Scroll->AddChild(Page);
                if (!Switcher->InsertChildAt(PageIndex, Scroll))
                {
                    UE_LOG(LogTemp, Error, TEXT("PalTRUI page scroll input update failed: scroll slot could not be inserted: %s"), Spec.ScrollName);
                    return false;
                }
            }

            Scroll->Modify();
            Scroll->SetScrollBarVisibility(ESlateVisibility::Visible);
            Scroll->SetScrollbarThickness(FVector2D(7.0f, 7.0f));
            Scroll->SetAlwaysShowScrollbar(false);
            Scroll->SetConsumeMouseWheel(EConsumeMouseWheel::Always);
            Scroll->SetAllowOverscroll(false);
        }

        static const FName NestedScrollNames[] = {
            TEXT("RelationList"),
            TEXT("ChatMessageList")
        };
        for (const FName ScrollName : NestedScrollNames)
        {
            if (UScrollBox* NestedScroll = Cast<UScrollBox>(Tree->FindWidget(ScrollName)))
            {
                NestedScroll->Modify();
                NestedScroll->SetConsumeMouseWheel(EConsumeMouseWheel::Always);
                NestedScroll->SetAllowOverscroll(false);
            }
        }

        Switcher->SetActiveWidgetIndex(ActiveIndex);
        FBlueprintEditorUtils::MarkBlueprintAsStructurallyModified(Panel);
        FKismetEditorUtilities::CompileBlueprint(Panel);
        if (!SaveAsset(Panel))
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI page scroll input update failed while saving panel."));
            return false;
        }
        UE_LOG(LogTemp, Display, TEXT("PALTR_UI_PAGE_SCROLL_INPUT_UPDATE_OK | pages=4 | consume_wheel=always"));
        return true;
    }

    bool UpdateDashboardColumnLayout()
    {
        UWidgetBlueprint* Panel = LoadObject<UWidgetBlueprint>(
            nullptr,
            TEXT("/Game/Mods/PalTRUI/WBP_PalTRPanel.WBP_PalTRPanel")
        );
        if (!Panel || !Panel->WidgetTree)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI dashboard column layout failed: panel asset missing."));
            return false;
        }

        UWidgetTree* Tree = Panel->WidgetTree;
        UVerticalBox* ClanPage = Cast<UVerticalBox>(Tree->FindWidget(TEXT("ClanPage")));
        UHorizontalBox* Columns = Cast<UHorizontalBox>(Tree->FindWidget(TEXT("DashboardColumns")));
        UVerticalBox* MainColumn = Cast<UVerticalBox>(Tree->FindWidget(TEXT("DashboardMainColumn")));
        UVerticalBox* SidebarColumn = Cast<UVerticalBox>(Tree->FindWidget(TEXT("DashboardSidebarColumn")));
        UWidget* StatusCards = Tree->FindWidget(TEXT("DashboardStatusCardsFrame"));
        UWidget* Members = Tree->FindWidget(TEXT("ClanMembersFrame"));
        UWidget* Relations = Tree->FindWidget(TEXT("DashboardRelationsFrame"));
        UWidget* Offers = Tree->FindWidget(TEXT("PendingOffersFrame"));
        UWidget* QuickActions = Tree->FindWidget(TEXT("DashboardQuickActionsFrame"));
        if (!ClanPage || !StatusCards || !Members || !Relations || !Offers || !QuickActions)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI dashboard column layout failed: dashboard controls missing."));
            return false;
        }

        if (Columns && MainColumn && SidebarColumn)
        {
            const bool bValid = Columns->GetParent() == ClanPage
                && MainColumn->GetParent() == Columns
                && SidebarColumn->GetParent() == Columns
                && StatusCards->GetParent() == MainColumn
                && Members->GetParent() == MainColumn
                && Relations->GetParent() == SidebarColumn
                && Offers->GetParent() == SidebarColumn
                && QuickActions->GetParent() == SidebarColumn;
            if (!bValid)
            {
                UE_LOG(LogTemp, Error, TEXT("PalTRUI dashboard column layout refused: unexpected existing hierarchy."));
                return false;
            }
            UE_LOG(LogTemp, Display, TEXT("PALTR_UI_DASHBOARD_COLUMN_LAYOUT_OK | changed=false"));
            return true;
        }
        if (Columns || MainColumn || SidebarColumn)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI dashboard column layout refused: partial controls exist."));
            return false;
        }

        static const FName DashboardWidgetNames[] = {
            TEXT("DashboardStatusCardsFrame"),
            TEXT("ClanMembersFrame"),
            TEXT("DashboardRelationsFrame"),
            TEXT("PendingOffersFrame"),
            TEXT("DashboardQuickActionsFrame")
        };
        for (const FName WidgetName : DashboardWidgetNames)
        {
            if (Tree->FindWidget(WidgetName)->GetParent() != ClanPage)
            {
                UE_LOG(LogTemp, Error, TEXT("PalTRUI dashboard column layout refused: control is outside clan page: %s"), *WidgetName.ToString());
                return false;
            }
        }

        Panel->Modify();
        Tree->Modify();
        ClanPage->Modify();
        Columns = Tree->ConstructWidget<UHorizontalBox>(UHorizontalBox::StaticClass(), TEXT("DashboardColumns"));
        MainColumn = Tree->ConstructWidget<UVerticalBox>(UVerticalBox::StaticClass(), TEXT("DashboardMainColumn"));
        SidebarColumn = Tree->ConstructWidget<UVerticalBox>(UVerticalBox::StaticClass(), TEXT("DashboardSidebarColumn"));

        for (UWidget* Widget : { StatusCards, Members, Relations, Offers, QuickActions })
        {
            Widget->Modify();
            ClanPage->RemoveChild(Widget);
        }

        AddVertical(MainColumn, StatusCards, FMargin(0, 0, 0, 14));
        AddVertical(MainColumn, Members);
        AddVertical(SidebarColumn, Relations, FMargin(0, 0, 0, 14));
        AddVertical(SidebarColumn, Offers, FMargin(0, 0, 0, 14));
        AddVertical(SidebarColumn, QuickActions);

        UHorizontalBoxSlot* MainSlot = AddHorizontal(Columns, MainColumn, FMargin(0, 0, 10, 0));
        FSlateChildSize MainSize(ESlateSizeRule::Fill);
        MainSize.Value = 1.65f;
        MainSlot->SetSize(MainSize);
        MainSlot->SetVerticalAlignment(VAlign_Fill);
        UHorizontalBoxSlot* SidebarSlot = AddHorizontal(Columns, SidebarColumn, FMargin(10, 0, 0, 0));
        FSlateChildSize SidebarSize(ESlateSizeRule::Fill);
        SidebarSize.Value = 0.85f;
        SidebarSlot->SetSize(SidebarSize);
        SidebarSlot->SetVerticalAlignment(VAlign_Fill);

        UVerticalBoxSlot* ColumnsSlot = Cast<UVerticalBoxSlot>(ClanPage->InsertChildAt(1, Columns));
        if (!ColumnsSlot)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI dashboard column layout failed: columns slot missing."));
            return false;
        }
        ColumnsSlot->SetHorizontalAlignment(HAlign_Fill);
        ColumnsSlot->SetPadding(FMargin(0, 0, 0, 10));

        FBlueprintEditorUtils::MarkBlueprintAsStructurallyModified(Panel);
        FKismetEditorUtilities::CompileBlueprint(Panel);
        if (!SaveAsset(Panel))
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI dashboard column layout failed while saving panel."));
            return false;
        }
        UE_LOG(LogTemp, Display, TEXT("PALTR_UI_DASHBOARD_COLUMN_LAYOUT_OK | changed=true | layout=main_sidebar"));
        return true;
    }

    bool UpdatePresentationHierarchy()
    {
        UWidgetBlueprint* Panel = LoadObject<UWidgetBlueprint>(
            nullptr,
            TEXT("/Game/Mods/PalTRUI/WBP_PalTRPanel.WBP_PalTRPanel")
        );
        if (!Panel || !Panel->WidgetTree)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI presentation hierarchy update failed: panel asset missing."));
            return false;
        }

        UWidgetTree* Tree = Panel->WidgetTree;
        UVerticalBox* Layout = Cast<UVerticalBox>(Tree->FindWidget(TEXT("PanelLayout")));
        UHorizontalBox* Header = Cast<UHorizontalBox>(Tree->FindWidget(TEXT("HeaderRow")));
        UBorder* HeaderFrame = Cast<UBorder>(Tree->FindWidget(TEXT("HeaderFrame")));
        UVerticalBox* ClanPage = Cast<UVerticalBox>(Tree->FindWidget(TEXT("ClanPage")));
        UVerticalBox* DiplomacyPage = Cast<UVerticalBox>(Tree->FindWidget(TEXT("DiplomacyPage")));
        UVerticalBox* AlliancePage = Cast<UVerticalBox>(Tree->FindWidget(TEXT("AlliancePage")));
        UVerticalBox* GuildPage = Cast<UVerticalBox>(Tree->FindWidget(TEXT("ChatPage")));
        UVerticalBox* Sidebar = Cast<UVerticalBox>(Tree->FindWidget(TEXT("DashboardSidebarColumn")));
        UHorizontalBox* DiplomacyColumns = Cast<UHorizontalBox>(Tree->FindWidget(TEXT("DiplomacyColumns")));
        USizeBox* RelationListSize = Cast<USizeBox>(Tree->FindWidget(TEXT("RelationListSize")));
        UVerticalBox* RelationDetail = Cast<UVerticalBox>(Tree->FindWidget(TEXT("RelationDetail")));
        if (!Layout || !Header || !ClanPage || !DiplomacyPage || !AlliancePage || !GuildPage
            || !Sidebar || !DiplomacyColumns || !RelationListSize || !RelationDetail)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI presentation hierarchy update failed: required hierarchy missing."));
            return false;
        }

        Panel->Modify();
        Tree->Modify();

        if (HeaderFrame)
        {
            if (HeaderFrame->GetContent() != Header || HeaderFrame->GetParent() != Layout)
            {
                UE_LOG(LogTemp, Error, TEXT("PalTRUI presentation hierarchy update refused: unexpected header frame."));
                return false;
            }
        }
        else
        {
            if (Header->GetParent() != Layout)
            {
                UE_LOG(LogTemp, Error, TEXT("PalTRUI presentation hierarchy update refused: header is outside layout."));
                return false;
            }
            const int32 HeaderIndex = Layout->GetChildIndex(Header);
            Header->Modify();
            Layout->Modify();
            Layout->RemoveChild(Header);
            HeaderFrame = Tree->ConstructWidget<UBorder>(UBorder::StaticClass(), TEXT("HeaderFrame"));
            HeaderFrame->SetContent(Header);
            UVerticalBoxSlot* HeaderSlot = Cast<UVerticalBoxSlot>(Layout->InsertChildAt(HeaderIndex, HeaderFrame));
            if (!HeaderSlot)
            {
                UE_LOG(LogTemp, Error, TEXT("PalTRUI presentation hierarchy update failed: header slot missing."));
                return false;
            }
            HeaderSlot->SetPadding(FMargin(0, 0, 0, 12));
            HeaderSlot->SetHorizontalAlignment(HAlign_Fill);
        }
        HeaderFrame->Modify();
        HeaderFrame->SetBrushColor(FLinearColor(0.055f, 0.042f, 0.018f, 0.99f));
        HeaderFrame->SetPadding(FMargin(14.0f, 10.0f));

        struct FSubtitleSpec
        {
            UVerticalBox* Page;
            const TCHAR* Name;
            const TCHAR* Text;
        };
        const FSubtitleSpec Subtitles[] = {
            { ClanPage, TEXT("ClanSubtitleText"), TEXT("Klan durumunu, uyeleri ve diplomasi hareketlerini tek ekrandan izleyin.") },
            { DiplomacyPage, TEXT("DiplomacySubtitleText"), TEXT("Klan iliskilerini, savas durumunu ve bekleyen teklifleri yonetin.") },
            { AlliancePage, TEXT("AllianceSubtitleText"), TEXT("Ittifak yapisini ve uye klanlari birlikte goruntuleyin.") },
            { GuildPage, TEXT("GuildSubtitleText"), TEXT("Aktif ve kayitli klanlari sunucu verisinden inceleyin.") }
        };
        for (const FSubtitleSpec& Spec : Subtitles)
        {
            UTextBlock* Subtitle = Cast<UTextBlock>(Tree->FindWidget(FName(Spec.Name)));
            if (!Subtitle)
            {
                Spec.Page->Modify();
                Subtitle = MakeText(Tree, FName(Spec.Name), Spec.Text, 14);
                Subtitle->SetAutoWrapText(true);
                UVerticalBoxSlot* SubtitleSlot = Cast<UVerticalBoxSlot>(Spec.Page->InsertChildAt(1, Subtitle));
                if (!SubtitleSlot)
                {
                    UE_LOG(LogTemp, Error, TEXT("PalTRUI presentation hierarchy update failed: subtitle slot missing: %s"), Spec.Name);
                    return false;
                }
                SubtitleSlot->SetPadding(FMargin(0, 0, 0, 16));
            }
            else if (Subtitle->GetParent() != Spec.Page)
            {
                UE_LOG(LogTemp, Error, TEXT("PalTRUI presentation hierarchy update refused: unexpected subtitle parent: %s"), Spec.Name);
                return false;
            }
            Subtitle->Modify();
            Subtitle->SetColorAndOpacity(FSlateColor(FLinearColor(0.68f, 0.72f, 0.70f, 1.0f)));
        }

        UBorder* SidebarTitleFrame = Cast<UBorder>(Tree->FindWidget(TEXT("DashboardSidebarTitleFrame")));
        UTextBlock* SidebarTitle = Cast<UTextBlock>(Tree->FindWidget(TEXT("DashboardSidebarTitleText")));
        if (!SidebarTitleFrame && !SidebarTitle)
        {
            Sidebar->Modify();
            SidebarTitleFrame = Tree->ConstructWidget<UBorder>(UBorder::StaticClass(), TEXT("DashboardSidebarTitleFrame"));
            SidebarTitleFrame->SetBrushColor(FLinearColor(0.12f, 0.085f, 0.025f, 0.99f));
            SidebarTitleFrame->SetPadding(FMargin(12.0f, 8.0f));
            SidebarTitle = MakeText(Tree, TEXT("DashboardSidebarTitleText"), TEXT("ILISKILER VE ISLEMLER"), 16);
            SidebarTitle->SetColorAndOpacity(FSlateColor(FLinearColor(0.98f, 0.84f, 0.52f, 1.0f)));
            SidebarTitleFrame->SetContent(SidebarTitle);
            UVerticalBoxSlot* SidebarTitleSlot = Cast<UVerticalBoxSlot>(Sidebar->InsertChildAt(0, SidebarTitleFrame));
            if (!SidebarTitleSlot)
            {
                UE_LOG(LogTemp, Error, TEXT("PalTRUI presentation hierarchy update failed: sidebar title slot missing."));
                return false;
            }
            SidebarTitleSlot->SetPadding(FMargin(0, 0, 0, 10));
        }
        else if (!SidebarTitleFrame || !SidebarTitle
            || SidebarTitleFrame->GetContent() != SidebarTitle
            || SidebarTitleFrame->GetParent() != Sidebar)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI presentation hierarchy update refused: partial sidebar title."));
            return false;
        }

        UBorder* ListFrame = Cast<UBorder>(Tree->FindWidget(TEXT("DiplomacyListFrame")));
        UBorder* DetailFrame = Cast<UBorder>(Tree->FindWidget(TEXT("DiplomacyDetailFrame")));
        if (!ListFrame && !DetailFrame)
        {
            if (RelationListSize->GetParent() != DiplomacyColumns || RelationDetail->GetParent() != DiplomacyColumns)
            {
                UE_LOG(LogTemp, Error, TEXT("PalTRUI presentation hierarchy update refused: diplomacy columns changed."));
                return false;
            }
            DiplomacyColumns->Modify();
            RelationListSize->Modify();
            RelationDetail->Modify();
            DiplomacyColumns->RemoveChild(RelationListSize);
            DiplomacyColumns->RemoveChild(RelationDetail);

            ListFrame = Tree->ConstructWidget<UBorder>(UBorder::StaticClass(), TEXT("DiplomacyListFrame"));
            ListFrame->SetContent(RelationListSize);
            AddHorizontal(DiplomacyColumns, ListFrame, FMargin(0, 0, 10, 0));
            DetailFrame = Tree->ConstructWidget<UBorder>(UBorder::StaticClass(), TEXT("DiplomacyDetailFrame"));
            DetailFrame->SetContent(RelationDetail);
            UHorizontalBoxSlot* DetailSlot = AddHorizontal(DiplomacyColumns, DetailFrame, FMargin(10, 0, 0, 0));
            DetailSlot->SetSize(FSlateChildSize(ESlateSizeRule::Fill));
            DetailSlot->SetVerticalAlignment(VAlign_Fill);
        }
        else if (!ListFrame || !DetailFrame
            || ListFrame->GetContent() != RelationListSize
            || DetailFrame->GetContent() != RelationDetail
            || ListFrame->GetParent() != DiplomacyColumns
            || DetailFrame->GetParent() != DiplomacyColumns)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI presentation hierarchy update refused: partial diplomacy frames."));
            return false;
        }
        ListFrame->Modify();
        DetailFrame->Modify();
        ListFrame->SetBrushColor(FLinearColor(0.018f, 0.075f, 0.085f, 0.98f));
        ListFrame->SetPadding(FMargin(14.0f));
        DetailFrame->SetBrushColor(FLinearColor(0.022f, 0.055f, 0.075f, 0.98f));
        DetailFrame->SetPadding(FMargin(18.0f));

        FBlueprintEditorUtils::MarkBlueprintAsStructurallyModified(Panel);
        FKismetEditorUtilities::CompileBlueprint(Panel);
        if (!SaveAsset(Panel))
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI presentation hierarchy update failed while saving panel."));
            return false;
        }
        UE_LOG(LogTemp, Display, TEXT("PALTR_UI_PRESENTATION_HIERARCHY_OK | header=framed | subtitles=4 | diplomacy=cards"));
        return true;
    }

    bool UpdateArtDashboard()
    {
        const FString ArtDirectory = FPaths::ConvertRelativePathToFull(
            FPaths::ProjectPluginsDir() / TEXT("PalTRUIAssetBuilder/Resources")
        );
        UTexture2D* PanelTexture = ImportUITexture(
            TEXT("/Game/Mods/PalTRUI/Art/T_PalTRPanelFrame"),
            TEXT("T_PalTRPanelFrame"),
            ArtDirectory / TEXT("paltr_panel_frame.png")
        );
        UTexture2D* ClanIcon = ImportUITexture(
            TEXT("/Game/Mods/PalTRUI/Art/T_PalTRClanIcon"),
            TEXT("T_PalTRClanIcon"),
            ArtDirectory / TEXT("paltr_icon_clan.png")
        );
        UTexture2D* DiplomacyIcon = ImportUITexture(
            TEXT("/Game/Mods/PalTRUI/Art/T_PalTRDiplomacyIcon"),
            TEXT("T_PalTRDiplomacyIcon"),
            ArtDirectory / TEXT("paltr_icon_diplomacy.png")
        );
        UTexture2D* ProtectionIcon = ImportUITexture(
            TEXT("/Game/Mods/PalTRUI/Art/T_PalTRProtectionIcon"),
            TEXT("T_PalTRProtectionIcon"),
            ArtDirectory / TEXT("paltr_icon_protection.png")
        );
        UTexture2D* BuildingsIcon = ImportUITexture(
            TEXT("/Game/Mods/PalTRUI/Art/T_PalTRBuildingsIcon"),
            TEXT("T_PalTRBuildingsIcon"),
            ArtDirectory / TEXT("paltr_icon_buildings.png")
        );
        if (!PanelTexture || !ClanIcon || !DiplomacyIcon || !ProtectionIcon || !BuildingsIcon)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI art dashboard update failed: texture import incomplete."));
            return false;
        }

        UWidgetBlueprint* Panel = LoadObject<UWidgetBlueprint>(
            nullptr,
            TEXT("/Game/Mods/PalTRUI/WBP_PalTRPanel.WBP_PalTRPanel")
        );
        if (!Panel || !Panel->WidgetTree)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI art dashboard update failed: panel asset missing."));
            return false;
        }
        UWidgetTree* Tree = Panel->WidgetTree;
        UBorder* Background = Cast<UBorder>(Tree->FindWidget(TEXT("PanelBackground")));
        UVerticalBox* Layout = Cast<UVerticalBox>(Tree->FindWidget(TEXT("PanelLayout")));
        UBorder* HeaderFrame = Cast<UBorder>(Tree->FindWidget(TEXT("HeaderFrame")));
        UHorizontalBox* HeaderRow = Cast<UHorizontalBox>(Tree->FindWidget(TEXT("HeaderRow")));
        UBorder* TabFrame = Cast<UBorder>(Tree->FindWidget(TEXT("TabFrame")));
        UHorizontalBox* TabBar = Cast<UHorizontalBox>(Tree->FindWidget(TEXT("TabBar")));
        UBorder* ContentFrame = Cast<UBorder>(Tree->FindWidget(TEXT("ContentFrame")));
        UBorder* FooterFrame = Cast<UBorder>(Tree->FindWidget(TEXT("FooterFrame")));
        UHorizontalBox* StatusCards = Cast<UHorizontalBox>(Tree->FindWidget(TEXT("DashboardStatusCardsFrame")));
        UVerticalBox* MainColumn = Cast<UVerticalBox>(Tree->FindWidget(TEXT("DashboardMainColumn")));
        UVerticalBox* Sidebar = Cast<UVerticalBox>(Tree->FindWidget(TEXT("DashboardSidebarColumn")));
        UVerticalBox* ClanCard = Cast<UVerticalBox>(Tree->FindWidget(TEXT("DashboardClanCardContent")));
        UVerticalBox* DiplomacyCard = Cast<UVerticalBox>(Tree->FindWidget(TEXT("DashboardDiplomacyCardContent")));
        UBorder* QuickActions = Cast<UBorder>(Tree->FindWidget(TEXT("DashboardQuickActionsFrame")));
        const bool bHasExistingNavigation = Tree->FindWidget(TEXT("LeftNavigation")) != nullptr;
        if (!Background || !Layout || !HeaderFrame || !HeaderRow || !ContentFrame || !FooterFrame
            || !StatusCards || !MainColumn || !Sidebar || !ClanCard || !DiplomacyCard || !QuickActions
            || (!bHasExistingNavigation && (!TabFrame || !TabBar)))
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI art dashboard update failed: required widget hierarchy missing."));
            return false;
        }

        Panel->Modify();
        Tree->Modify();
        Background->Modify();
        Layout->Modify();

        UOverlay* ArtOverlay = Cast<UOverlay>(Tree->FindWidget(TEXT("PanelArtOverlay")));
        UImage* ArtImage = Cast<UImage>(Tree->FindWidget(TEXT("PanelArtImage")));
        UBorder* ContentPadding = Cast<UBorder>(Tree->FindWidget(TEXT("PanelArtContentPadding")));
        if (!ArtOverlay && !ArtImage && !ContentPadding)
        {
            if (Background->GetContent() != Layout)
            {
                UE_LOG(LogTemp, Error, TEXT("PalTRUI art dashboard update refused: background content changed."));
                return false;
            }
            Background->RemoveChild(Layout);
            ArtOverlay = Tree->ConstructWidget<UOverlay>(UOverlay::StaticClass(), TEXT("PanelArtOverlay"));
            ArtImage = Tree->ConstructWidget<UImage>(UImage::StaticClass(), TEXT("PanelArtImage"));
            ContentPadding = Tree->ConstructWidget<UBorder>(UBorder::StaticClass(), TEXT("PanelArtContentPadding"));
            ContentPadding->SetBrushColor(FLinearColor(0, 0, 0, 0));
            ContentPadding->SetPadding(FMargin(16.0f, 12.0f));
            ContentPadding->SetContent(Layout);
            ArtOverlay->AddChildToOverlay(ArtImage);
            ArtOverlay->AddChildToOverlay(ContentPadding);
            Background->SetContent(ArtOverlay);
        }
        else if (!ArtOverlay || !ArtImage || !ContentPadding
            || Background->GetContent() != ArtOverlay
            || ArtImage->GetParent() != ArtOverlay
            || ContentPadding->GetContent() != Layout
            || ContentPadding->GetParent() != ArtOverlay)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI art dashboard update refused: partial art overlay."));
            return false;
        }
        Background->SetHorizontalAlignment(HAlign_Fill);
        Background->SetVerticalAlignment(VAlign_Fill);
        if (UBorderSlot* ArtOverlaySlot = Cast<UBorderSlot>(ArtOverlay->Slot))
        {
            ArtOverlaySlot->Modify();
            ArtOverlaySlot->SetHorizontalAlignment(HAlign_Fill);
            ArtOverlaySlot->SetVerticalAlignment(VAlign_Fill);
        }
        if (UOverlaySlot* ArtImageSlot = Cast<UOverlaySlot>(ArtImage->Slot))
        {
            ArtImageSlot->Modify();
            ArtImageSlot->SetHorizontalAlignment(HAlign_Fill);
            ArtImageSlot->SetVerticalAlignment(VAlign_Fill);
        }
        if (UOverlaySlot* ContentPaddingSlot = Cast<UOverlaySlot>(ContentPadding->Slot))
        {
            ContentPaddingSlot->Modify();
            ContentPaddingSlot->SetHorizontalAlignment(HAlign_Fill);
            ContentPaddingSlot->SetVerticalAlignment(VAlign_Fill);
        }
        ContentPadding->SetHorizontalAlignment(HAlign_Fill);
        ContentPadding->SetVerticalAlignment(VAlign_Fill);
        ContentPadding->SetBrushFromTexture(PanelTexture);
        ContentPadding->SetBrushColor(FLinearColor::White);
        ContentPadding->SetPadding(FMargin(16.0f, 12.0f));
        ArtImage->Modify();
        ArtImage->SetBrushFromTexture(PanelTexture, true);
        ArtImage->SetColorAndOpacity(FLinearColor::White);
        ArtImage->SetVisibility(ESlateVisibility::Collapsed);
        // Runtime fallback: the imported ornamental texture may fail to draw on
        // some UE4SS/Palworld builds. Keep the panel independently opaque so
        // gameplay never bleeds through the dashboard.
        Background->SetBrush(FSlateRoundedBoxBrush(
            FLinearColor(0.008f, 0.025f, 0.045f, 0.995f),
            12.0f,
            FLinearColor(0.62f, 0.43f, 0.16f, 0.98f),
            2.0f
        ));
        Background->SetBrushColor(FLinearColor::White);
        Background->SetPadding(FMargin(0));
        if (UButton* InputShield = Cast<UButton>(Tree->FindWidget(TEXT("PanelInputShield"))))
        {
            if (UCanvasPanelSlot* ShieldSlot = Cast<UCanvasPanelSlot>(InputShield->Slot))
            {
                ShieldSlot->Modify();
                ShieldSlot->SetAnchors(FAnchors(0.04f, 0.05f, 0.96f, 0.95f));
                ShieldSlot->SetAlignment(FVector2D::ZeroVector);
                ShieldSlot->SetOffsets(FMargin(0.0f));
            }
            if (UButtonSlot* ContentSlot = Cast<UButtonSlot>(Background->Slot))
            {
                ContentSlot->Modify();
                ContentSlot->SetHorizontalAlignment(HAlign_Fill);
                ContentSlot->SetVerticalAlignment(VAlign_Fill);
            }
        }
        else if (UCanvasPanelSlot* BackgroundSlot = Cast<UCanvasPanelSlot>(Background->Slot))
        {
            BackgroundSlot->Modify();
            BackgroundSlot->SetAnchors(FAnchors(0.04f, 0.05f, 0.96f, 0.95f));
            BackgroundSlot->SetAlignment(FVector2D::ZeroVector);
            BackgroundSlot->SetOffsets(FMargin(0.0f));
        }

        USizeBox* HeaderCrestSpacer = Cast<USizeBox>(Tree->FindWidget(TEXT("HeaderCrestSpacer")));
        if (!HeaderCrestSpacer)
        {
            HeaderCrestSpacer = Tree->ConstructWidget<USizeBox>(USizeBox::StaticClass(), TEXT("HeaderCrestSpacer"));
            HeaderCrestSpacer->SetWidthOverride(18.0f);
            UHorizontalBoxSlot* CrestSlot = Cast<UHorizontalBoxSlot>(HeaderRow->InsertChildAt(0, HeaderCrestSpacer));
            if (!CrestSlot)
            {
                UE_LOG(LogTemp, Error, TEXT("PalTRUI art dashboard update failed: header crest spacer slot."));
                return false;
            }
        }
        else if (HeaderCrestSpacer->GetParent() != HeaderRow)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI art dashboard update refused: header crest spacer moved."));
            return false;
        }
        HeaderCrestSpacer->SetWidthOverride(18.0f);

        USizeBox* HeaderCrestImageSize = Cast<USizeBox>(Tree->FindWidget(TEXT("HeaderCrestImageSize")));
        UImage* HeaderCrestImage = Cast<UImage>(Tree->FindWidget(TEXT("HeaderCrestImage")));
        if (!HeaderCrestImageSize && !HeaderCrestImage)
        {
            HeaderCrestImageSize = Tree->ConstructWidget<USizeBox>(USizeBox::StaticClass(), TEXT("HeaderCrestImageSize"));
            HeaderCrestImageSize->SetWidthOverride(84.0f);
            HeaderCrestImageSize->SetHeightOverride(78.0f);
            HeaderCrestImage = Tree->ConstructWidget<UImage>(UImage::StaticClass(), TEXT("HeaderCrestImage"));
            HeaderCrestImageSize->SetContent(HeaderCrestImage);
            UHorizontalBoxSlot* CrestImageSlot = Cast<UHorizontalBoxSlot>(HeaderRow->InsertChildAt(0, HeaderCrestImageSize));
            if (!CrestImageSlot)
            {
                UE_LOG(LogTemp, Error, TEXT("PalTRUI art dashboard update failed: header crest image slot."));
                return false;
            }
            CrestImageSlot->SetPadding(FMargin(0, 0, 8, 0));
            CrestImageSlot->SetVerticalAlignment(VAlign_Center);
        }
        else if (!HeaderCrestImageSize || !HeaderCrestImage
            || HeaderCrestImageSize->GetContent() != HeaderCrestImage
            || HeaderCrestImageSize->GetParent() != HeaderRow)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI art dashboard update refused: partial header crest image."));
            return false;
        }
        HeaderCrestImageSize->SetWidthOverride(84.0f);
        HeaderCrestImageSize->SetHeightOverride(78.0f);
        HeaderCrestImage->SetBrushFromTexture(ClanIcon, true);

        if (UScrollBox* ClanPageScroll = Cast<UScrollBox>(Tree->FindWidget(TEXT("ClanPageScroll"))))
        {
            ClanPageScroll->SetScrollBarVisibility(ESlateVisibility::Collapsed);
            ClanPageScroll->SetAlwaysShowScrollbar(false);
        }
        if (UBorder* ClanMembersFrame = Cast<UBorder>(Tree->FindWidget(TEXT("ClanMembersFrame"))))
        {
            ClanMembersFrame->SetVisibility(ESlateVisibility::Collapsed);
        }

        UHorizontalBox* BodyRow = Cast<UHorizontalBox>(Tree->FindWidget(TEXT("PanelBodyRow")));
        USizeBox* NavigationSize = Cast<USizeBox>(Tree->FindWidget(TEXT("LeftNavigationSize")));
        UBorder* NavigationFrame = Cast<UBorder>(Tree->FindWidget(TEXT("LeftNavigationFrame")));
        UVerticalBox* Navigation = Cast<UVerticalBox>(Tree->FindWidget(TEXT("LeftNavigation")));
        UTextBlock* NavigationHeading = Cast<UTextBlock>(Tree->FindWidget(TEXT("LeftNavigationHeadingText")));
        if (!BodyRow && !NavigationSize && !NavigationFrame && !Navigation && !NavigationHeading)
        {
            if (TabFrame->GetParent() != Layout || ContentFrame->GetParent() != Layout)
            {
                UE_LOG(LogTemp, Error, TEXT("PalTRUI art dashboard update refused: tab/content frames moved."));
                return false;
            }
            BodyRow = Tree->ConstructWidget<UHorizontalBox>(UHorizontalBox::StaticClass(), TEXT("PanelBodyRow"));
            NavigationSize = Tree->ConstructWidget<USizeBox>(USizeBox::StaticClass(), TEXT("LeftNavigationSize"));
            NavigationSize->SetWidthOverride(278.0f);
            NavigationFrame = Tree->ConstructWidget<UBorder>(UBorder::StaticClass(), TEXT("LeftNavigationFrame"));
            NavigationFrame->SetBrushColor(FLinearColor(0.01f, 0.035f, 0.05f, 0.18f));
            NavigationFrame->SetPadding(FMargin(12.0f));
            Navigation = Tree->ConstructWidget<UVerticalBox>(UVerticalBox::StaticClass(), TEXT("LeftNavigation"));
            NavigationHeading = MakeText(Tree, TEXT("LeftNavigationHeadingText"), TEXT("MENU"), 14);
            NavigationHeading->SetColorAndOpacity(FSlateColor(FLinearColor(0.72f, 0.62f, 0.40f, 1.0f)));
            AddVertical(Navigation, NavigationHeading, FMargin(8, 4, 0, 14));
            for (const FName ButtonName : {
                FName(TEXT("ClanTabButton")),
                FName(TEXT("DiplomacyTabButton")),
                FName(TEXT("AllianceTabButton")),
                FName(TEXT("ChatTabButton"))
            })
            {
                UButton* Button = Cast<UButton>(Tree->FindWidget(ButtonName));
                if (!Button || Button->GetParent() != TabBar)
                {
                    UE_LOG(LogTemp, Error, TEXT("PalTRUI art dashboard update failed: navigation button missing: %s"), *ButtonName.ToString());
                    return false;
                }
                TabBar->RemoveChild(Button);
                UVerticalBoxSlot* ButtonSlot = AddVertical(Navigation, Button, FMargin(0, 0, 0, 10));
                ButtonSlot->SetHorizontalAlignment(HAlign_Fill);
            }
            Layout->RemoveChild(TabFrame);
            Layout->RemoveChild(ContentFrame);
            NavigationFrame->SetContent(Navigation);
            NavigationSize->SetContent(NavigationFrame);
            AddHorizontal(BodyRow, NavigationSize, FMargin(0, 0, 18, 0));
            UHorizontalBoxSlot* ContentSlot = AddHorizontal(BodyRow, ContentFrame);
            ContentSlot->SetSize(FSlateChildSize(ESlateSizeRule::Fill));
            ContentSlot->SetVerticalAlignment(VAlign_Fill);
            UVerticalBoxSlot* BodySlot = Cast<UVerticalBoxSlot>(Layout->InsertChildAt(1, BodyRow));
            if (!BodySlot)
            {
                UE_LOG(LogTemp, Error, TEXT("PalTRUI art dashboard update failed: body slot missing."));
                return false;
            }
            BodySlot->SetSize(FSlateChildSize(ESlateSizeRule::Fill));
            BodySlot->SetHorizontalAlignment(HAlign_Fill);
            TabFrame->SetVisibility(ESlateVisibility::Collapsed);
        }
        else if (!BodyRow || !NavigationSize || !NavigationFrame || !Navigation || !NavigationHeading
            || BodyRow->GetParent() != Layout
            || NavigationSize->GetParent() != BodyRow
            || ContentFrame->GetParent() != BodyRow)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI art dashboard update refused: partial navigation shell."));
            return false;
        }
        NavigationSize->SetWidthOverride(278.0f);

        auto EnsureCardIcon = [Tree](
            UVerticalBox* Card,
            const FName SizeName,
            const FName ImageName,
            UTexture2D* Texture
        ) -> bool
        {
            USizeBox* IconSize = Cast<USizeBox>(Tree->FindWidget(SizeName));
            UImage* Icon = Cast<UImage>(Tree->FindWidget(ImageName));
            if (!IconSize && !Icon)
            {
                IconSize = Tree->ConstructWidget<USizeBox>(USizeBox::StaticClass(), SizeName);
                IconSize->SetWidthOverride(76.0f);
                IconSize->SetHeightOverride(76.0f);
                Icon = Tree->ConstructWidget<UImage>(UImage::StaticClass(), ImageName);
                IconSize->SetContent(Icon);
                UVerticalBoxSlot* IconSlot = Cast<UVerticalBoxSlot>(Card->InsertChildAt(1, IconSize));
                if (!IconSlot)
                {
                    return false;
                }
                IconSlot->SetHorizontalAlignment(HAlign_Center);
                IconSlot->SetPadding(FMargin(0, 2, 0, 8));
            }
            else if (!IconSize || !Icon || IconSize->GetContent() != Icon || IconSize->GetParent() != Card)
            {
                return false;
            }
            Icon->SetBrushFromTexture(Texture, true);
            return true;
        };
        if (!EnsureCardIcon(ClanCard, TEXT("DashboardClanIconSize"), TEXT("DashboardClanIcon"), ClanIcon)
            || !EnsureCardIcon(DiplomacyCard, TEXT("DashboardDiplomacyIconSize"), TEXT("DashboardDiplomacyIcon"), DiplomacyIcon))
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI art dashboard update failed: live card icon hierarchy."));
            return false;
        }

        auto AddMockCard = [Tree, StatusCards, &EnsureCardIcon](
            const FName FrameName,
            const FName ContentName,
            const FName TitleName,
            const TCHAR* Title,
            const FName IconSizeName,
            const FName IconName,
            UTexture2D* IconTexture,
            const FName ValueName,
            const TCHAR* Value,
            const FName DetailName,
            const TCHAR* Detail,
            const FLinearColor Tint
        ) -> bool
        {
            UBorder* Frame = Cast<UBorder>(Tree->FindWidget(FrameName));
            UVerticalBox* Content = Cast<UVerticalBox>(Tree->FindWidget(ContentName));
            if (!Frame && !Content)
            {
                Frame = Tree->ConstructWidget<UBorder>(UBorder::StaticClass(), FrameName);
                Frame->SetBrushColor(Tint);
                Frame->SetPadding(FMargin(14.0f));
                Content = Tree->ConstructWidget<UVerticalBox>(UVerticalBox::StaticClass(), ContentName);
                Frame->SetContent(Content);
                UTextBlock* TitleText = MakeText(Tree, TitleName, Title, 17);
                TitleText->SetJustification(ETextJustify::Center);
                TitleText->SetColorAndOpacity(FSlateColor(FLinearColor(0.95f, 0.80f, 0.48f, 1.0f)));
                AddVertical(Content, TitleText, FMargin(0, 0, 0, 4));
                if (!EnsureCardIcon(Content, IconSizeName, IconName, IconTexture))
                {
                    return false;
                }
                UTextBlock* ValueText = MakeText(Tree, ValueName, Value, 18);
                ValueText->SetJustification(ETextJustify::Center);
                AddVertical(Content, ValueText, FMargin(0, 0, 0, 6));
                UTextBlock* DetailText = MakeText(Tree, DetailName, Detail, 13);
                DetailText->SetJustification(ETextJustify::Center);
                DetailText->SetAutoWrapText(true);
                AddVertical(Content, DetailText);
                UHorizontalBoxSlot* FrameSlot = AddHorizontal(StatusCards, Frame, FMargin(6, 0));
                FrameSlot->SetSize(FSlateChildSize(ESlateSizeRule::Fill));
                FrameSlot->SetVerticalAlignment(VAlign_Fill);
            }
            else if (!Frame || !Content || Frame->GetContent() != Content || Frame->GetParent() != StatusCards)
            {
                return false;
            }
            return true;
        };
        if (!AddMockCard(
                TEXT("DashboardProtectionCardFrame"), TEXT("DashboardProtectionCardContent"),
                TEXT("DashboardProtectionCardTitleText"), TEXT("KORUMA"),
                TEXT("DashboardProtectionIconSize"), TEXT("DashboardProtectionIcon"), ProtectionIcon,
                TEXT("DashboardProtectionCardValueText"), TEXT("YAKINDA"),
                TEXT("DashboardProtectionCardDetailText"), TEXT("Offline koruma ve baskin penceresi hazirlaniyor."),
                FLinearColor(0.18f, 0.12f, 0.035f, 0.96f)
            )
            || !AddMockCard(
                TEXT("DashboardBuildingsCardFrame"), TEXT("DashboardBuildingsCardContent"),
                TEXT("DashboardBuildingsCardTitleText"), TEXT("YAPILAR"),
                TEXT("DashboardBuildingsIconSize"), TEXT("DashboardBuildingsIcon"), BuildingsIcon,
                TEXT("DashboardBuildingsCardValueText"), TEXT("YAKINDA"),
                TEXT("DashboardBuildingsCardDetailText"), TEXT("Us ve yapi takibi sonraki fazda baglanacak."),
                FLinearColor(0.16f, 0.085f, 0.025f, 0.96f)
            ))
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI art dashboard update failed: mock card hierarchy."));
            return false;
        }

        UHorizontalBox* LowerRow = Cast<UHorizontalBox>(Tree->FindWidget(TEXT("DashboardLowerRow")));
        UBorder* RecentFrame = Cast<UBorder>(Tree->FindWidget(TEXT("DashboardRecentEventsFrame")));
        UVerticalBox* RecentContent = Cast<UVerticalBox>(Tree->FindWidget(TEXT("DashboardRecentEventsContent")));
        if (!LowerRow && !RecentFrame && !RecentContent)
        {
            if (QuickActions->GetParent() != Sidebar)
            {
                UE_LOG(LogTemp, Error, TEXT("PalTRUI art dashboard update refused: quick actions moved."));
                return false;
            }
            Sidebar->RemoveChild(QuickActions);
            LowerRow = Tree->ConstructWidget<UHorizontalBox>(UHorizontalBox::StaticClass(), TEXT("DashboardLowerRow"));
            RecentFrame = Tree->ConstructWidget<UBorder>(UBorder::StaticClass(), TEXT("DashboardRecentEventsFrame"));
            RecentFrame->SetBrushColor(FLinearColor(0.015f, 0.045f, 0.065f, 0.18f));
            RecentFrame->SetPadding(FMargin(16.0f));
            RecentContent = Tree->ConstructWidget<UVerticalBox>(UVerticalBox::StaticClass(), TEXT("DashboardRecentEventsContent"));
            RecentFrame->SetContent(RecentContent);
            UTextBlock* RecentHeading = MakeText(Tree, TEXT("DashboardRecentEventsHeadingText"), TEXT("SON OLAYLAR"), 18);
            RecentHeading->SetColorAndOpacity(FSlateColor(FLinearColor(0.95f, 0.80f, 0.48f, 1.0f)));
            AddVertical(RecentContent, RecentHeading, FMargin(0, 0, 0, 10));
            AddVertical(RecentContent, MakeText(
                Tree,
                TEXT("DashboardRecentEventsText"),
                TEXT("Exceed ile savas devam ediyor.\nSaru tarafsiz durumda.\nKoruma sistemi sonraki fazda.\nYapi takibi sonraki fazda."),
                14
            ));
            UHorizontalBoxSlot* RecentSlot = AddHorizontal(LowerRow, RecentFrame, FMargin(0, 0, 8, 0));
            RecentSlot->SetSize(FSlateChildSize(ESlateSizeRule::Fill));
            UHorizontalBoxSlot* QuickSlot = AddHorizontal(LowerRow, QuickActions, FMargin(8, 0, 0, 0));
            QuickSlot->SetSize(FSlateChildSize(ESlateSizeRule::Fill));
            UVerticalBoxSlot* LowerSlot = Cast<UVerticalBoxSlot>(MainColumn->InsertChildAt(1, LowerRow));
            if (!LowerSlot)
            {
                UE_LOG(LogTemp, Error, TEXT("PalTRUI art dashboard update failed: lower row slot missing."));
                return false;
            }
            LowerSlot->SetPadding(FMargin(0, 14, 0, 14));
            LowerSlot->SetHorizontalAlignment(HAlign_Fill);
        }
        else if (!LowerRow || !RecentFrame || !RecentContent
            || LowerRow->GetParent() != MainColumn
            || RecentFrame->GetParent() != LowerRow
            || QuickActions->GetParent() != LowerRow)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI art dashboard update refused: partial lower row."));
            return false;
        }
        const FLinearColor GoldEdge(0.62f, 0.43f, 0.16f, 0.96f);
        const FLinearColor SoftGoldEdge(0.48f, 0.34f, 0.14f, 0.82f);
        const FLinearColor CyanEdge(0.12f, 0.66f, 0.70f, 0.92f);
        const FLinearColor BlueEdge(0.17f, 0.48f, 0.66f, 0.90f);
        StyleRoundedFrame(Tree, TEXT("HeaderFrame"), FLinearColor(0.008f, 0.02f, 0.035f, 0.78f), GoldEdge, 8.0f, 1.5f, FMargin(8.0f));
        StyleRoundedFrame(Tree, TEXT("ContentFrame"), FLinearColor(0.008f, 0.025f, 0.045f, 0.20f), SoftGoldEdge, 8.0f, 1.0f, FMargin(12.0f));
        StyleRoundedFrame(Tree, TEXT("FooterFrame"), FLinearColor(0.008f, 0.02f, 0.035f, 0.72f), GoldEdge, 7.0f, 1.25f, FMargin(10.0f, 7.0f));
        StyleRoundedFrame(Tree, TEXT("LeftNavigationFrame"), FLinearColor(0.006f, 0.025f, 0.04f, 0.48f), GoldEdge, 9.0f, 1.5f, FMargin(14.0f));
        StyleRoundedFrame(Tree, TEXT("DashboardClanCardFrame"), FLinearColor(0.015f, 0.13f, 0.13f, 0.80f), CyanEdge, 9.0f, 1.5f, FMargin(14.0f));
        StyleRoundedFrame(Tree, TEXT("DashboardDiplomacyCardFrame"), FLinearColor(0.02f, 0.08f, 0.14f, 0.80f), BlueEdge, 9.0f, 1.5f, FMargin(14.0f));
        StyleRoundedFrame(Tree, TEXT("DashboardProtectionCardFrame"), FLinearColor(0.14f, 0.095f, 0.028f, 0.80f), GoldEdge, 9.0f, 1.5f, FMargin(14.0f));
        StyleRoundedFrame(Tree, TEXT("DashboardBuildingsCardFrame"), FLinearColor(0.12f, 0.065f, 0.02f, 0.80f), FLinearColor(0.68f, 0.34f, 0.12f, 0.94f), 9.0f, 1.5f, FMargin(14.0f));
        StyleRoundedFrame(Tree, TEXT("DashboardRecentEventsFrame"), FLinearColor(0.012f, 0.045f, 0.07f, 0.74f), SoftGoldEdge, 8.0f, 1.0f, FMargin(16.0f));
        StyleRoundedFrame(Tree, TEXT("DashboardRelationsFrame"), FLinearColor(0.055f, 0.04f, 0.015f, 0.72f), GoldEdge, 8.0f, 1.25f, FMargin(14.0f));
        StyleRoundedFrame(Tree, TEXT("PendingOffersFrame"), FLinearColor(0.055f, 0.04f, 0.015f, 0.72f), GoldEdge, 8.0f, 1.25f, FMargin(14.0f));
        StyleRoundedFrame(Tree, TEXT("DashboardQuickActionsFrame"), FLinearColor(0.01f, 0.055f, 0.08f, 0.76f), CyanEdge, 8.0f, 1.25f, FMargin(14.0f));
        StyleRoundedFrame(Tree, TEXT("DashboardSidebarTitleFrame"), FLinearColor(0.18f, 0.12f, 0.04f, 0.76f), GoldEdge, 7.0f, 1.25f, FMargin(12.0f, 8.0f));
        for (const FName CardTextName : {
            FName(TEXT("DashboardClanCardTitleText")),
            FName(TEXT("DashboardClanCardValueText")),
            FName(TEXT("DashboardClanCardDetailText")),
            FName(TEXT("DashboardDiplomacyCardTitleText")),
            FName(TEXT("DashboardDiplomacyCardValueText")),
            FName(TEXT("DashboardDiplomacyCardDetailText")),
            FName(TEXT("DashboardProtectionCardTitleText")),
            FName(TEXT("DashboardProtectionCardValueText")),
            FName(TEXT("DashboardProtectionCardDetailText")),
            FName(TEXT("DashboardBuildingsCardTitleText")),
            FName(TEXT("DashboardBuildingsCardValueText")),
            FName(TEXT("DashboardBuildingsCardDetailText"))
        })
        {
            if (UTextBlock* CardText = Cast<UTextBlock>(Tree->FindWidget(CardTextName)))
            {
                CardText->SetJustification(ETextJustify::Center);
                CardText->SetAutoWrapText(true);
            }
        }
        SetTextFontSize(Tree, TEXT("DashboardClanCardDetailText"), 13);
        SetTextFontSize(Tree, TEXT("DashboardDiplomacyCardValueText"), 16);
        SetTextFontSize(Tree, TEXT("DashboardDiplomacyCardDetailText"), 13);
        SetTextFontSize(Tree, TEXT("DashboardProtectionCardDetailText"), 12);
        SetTextFontSize(Tree, TEXT("DashboardBuildingsCardDetailText"), 12);
        for (const FName NavigationButton : {
            FName(TEXT("ClanTabButton")),
            FName(TEXT("DiplomacyTabButton")),
            FName(TEXT("AllianceTabButton")),
            FName(TEXT("ChatTabButton"))
        })
        {
            StyleButton(Tree, NavigationButton, FLinearColor(0.01f, 0.055f, 0.075f, 0.96f));
        }
        StyleButton(Tree, TEXT("DashboardDiplomacyButton"), FLinearColor(0.015f, 0.20f, 0.24f, 0.98f));
        StyleButton(Tree, TEXT("DashboardOffersButton"), FLinearColor(0.015f, 0.16f, 0.20f, 0.98f));
        StyleButton(Tree, TEXT("DashboardGuildsButton"), FLinearColor(0.015f, 0.16f, 0.20f, 0.98f));
        StyleButton(Tree, TEXT("CloseButton"), FLinearColor(0.32f, 0.055f, 0.04f, 0.98f));
        if (UTextBlock* Title = Cast<UTextBlock>(Tree->FindWidget(TEXT("TitleText"))))
        {
            Title->SetText(FText::FromString(TEXT("PALTR PANEL")));
            FSlateFontInfo TitleFont = Title->GetFont();
            TitleFont.Size = 30;
            Title->SetFont(TitleFont);
        }

        FBlueprintEditorUtils::MarkBlueprintAsStructurallyModified(Panel);
        FKismetEditorUtilities::CompileBlueprint(Panel);
        if (!SaveAsset(Panel))
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI art dashboard update failed while saving panel."));
            return false;
        }
        UE_LOG(LogTemp, Display, TEXT("PALTR_UI_ART_DASHBOARD_OK | art=5 | navigation=left | mock_cards=2"));
        return true;
    }

    bool UpdatePanelInputShield()
    {
        UWidgetBlueprint* Panel = LoadObject<UWidgetBlueprint>(
            nullptr,
            TEXT("/Game/Mods/PalTRUI/WBP_PalTRPanel.WBP_PalTRPanel")
        );
        if (!Panel || !Panel->WidgetTree)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI input shield update failed: panel asset missing."));
            return false;
        }

        UWidgetTree* Tree = Panel->WidgetTree;
        UCanvasPanel* Root = Cast<UCanvasPanel>(Tree->FindWidget(TEXT("RootCanvas")));
        UBorder* Background = Cast<UBorder>(Tree->FindWidget(TEXT("PanelBackground")));
        UButton* Shield = Cast<UButton>(Tree->FindWidget(TEXT("PanelInputShield")));
        if (!Root || !Background)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI input shield update failed: root or background missing."));
            return false;
        }
        if (Shield && Shield->GetContent() == Background
            && Shield->GetParent() == Root)
        {
            UE_LOG(LogTemp, Display, TEXT("PALTR_UI_INPUT_SHIELD_UPDATE_OK | changed=false"));
            return true;
        }
        if (Shield || Background->GetParent() != Root)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI input shield update refused: partial or unexpected hierarchy."));
            return false;
        }

        Panel->Modify();
        Tree->Modify();
        Root->Modify();
        Background->Modify();
        Root->RemoveChild(Background);

        Shield = Tree->ConstructWidget<UButton>(
            UButton::StaticClass(),
            TEXT("PanelInputShield")
        );
        FButtonStyle ShieldStyle = Shield->WidgetStyle;
        const FSlateNoResource EmptyBrush;
        ShieldStyle.SetNormal(EmptyBrush);
        ShieldStyle.SetHovered(EmptyBrush);
        ShieldStyle.SetPressed(EmptyBrush);
        ShieldStyle.SetDisabled(EmptyBrush);
        ShieldStyle.SetNormalPadding(FMargin(0.0f));
        ShieldStyle.SetPressedPadding(FMargin(0.0f));
        Shield->SetStyle(ShieldStyle);
        Shield->SetBackgroundColor(FLinearColor::Transparent);
        Shield->SetColorAndOpacity(FLinearColor::White);
        Shield->IsFocusable = false;
        Shield->SetContent(Background);
        UButtonSlot* ContentSlot = Cast<UButtonSlot>(Background->Slot);
        if (!ContentSlot)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI input shield update failed: button content slot missing."));
            return false;
        }
        ContentSlot->SetHorizontalAlignment(HAlign_Fill);
        ContentSlot->SetVerticalAlignment(VAlign_Fill);

        UCanvasPanelSlot* ShieldSlot = Root->AddChildToCanvas(Shield);
        ShieldSlot->SetAnchors(FAnchors(0.04f, 0.05f, 0.96f, 0.95f));
        ShieldSlot->SetAlignment(FVector2D::ZeroVector);
        ShieldSlot->SetOffsets(FMargin(0.0f));

        FBlueprintEditorUtils::MarkBlueprintAsStructurallyModified(Panel);
        FKismetEditorUtilities::CompileBlueprint(Panel);
        if (!SaveAsset(Panel))
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI input shield update failed while saving panel."));
            return false;
        }
        UE_LOG(LogTemp, Display, TEXT("PALTR_UI_INPUT_SHIELD_UPDATE_OK | changed=true"));
        return true;
    }

    bool UpdateClanMembersPanel()
    {
        UWidgetBlueprint* Panel = LoadObject<UWidgetBlueprint>(
            nullptr,
            TEXT("/Game/Mods/PalTRUI/WBP_PalTRPanel.WBP_PalTRPanel")
        );
        if (!Panel || !Panel->WidgetTree)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI clan members panel update failed: panel asset missing."));
            return false;
        }

        UWidgetTree* Tree = Panel->WidgetTree;
        UVerticalBox* ClanPage = Cast<UVerticalBox>(Tree->FindWidget(TEXT("ClanPage")));
        UTextBlock* Members = Cast<UTextBlock>(Tree->FindWidget(TEXT("ClanMembersText")));
        static const FName MemberPanelWidgets[] = {
            TEXT("ClanMembersFrame"),
            TEXT("ClanMembersContent"),
            TEXT("ClanMembersHeadingText"),
            TEXT("ClanMembersStatusText")
        };
        if (!ClanPage || !Members)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI clan members panel update failed: clan page or member list missing."));
            return false;
        }

        int32 ExistingWidgetCount = 0;
        for (const FName WidgetName : MemberPanelWidgets)
        {
            ExistingWidgetCount += Tree->FindWidget(WidgetName) ? 1 : 0;
        }
        if (ExistingWidgetCount == UE_ARRAY_COUNT(MemberPanelWidgets))
        {
            UE_LOG(LogTemp, Display, TEXT("PALTR_UI_CLAN_MEMBERS_PANEL_UPDATE_OK | changed=false"));
            return true;
        }
        if (ExistingWidgetCount != 0 || Members->GetParent() != ClanPage)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI clan members panel update refused: partial or unexpected hierarchy."));
            return false;
        }

        const int32 MemberIndex = ClanPage->GetChildIndex(Members);
        if (MemberIndex < 0)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI clan members panel update failed: member slot missing."));
            return false;
        }

        Panel->Modify();
        Tree->Modify();
        ClanPage->Modify();
        Members->Modify();
        ClanPage->RemoveChild(Members);

        UBorder* Frame = Tree->ConstructWidget<UBorder>(
            UBorder::StaticClass(),
            TEXT("ClanMembersFrame")
        );
        Frame->SetBrushColor(FLinearColor(0.025f, 0.11f, 0.13f, 0.96f));
        Frame->SetPadding(FMargin(16.0f));
        UVerticalBox* Content = Tree->ConstructWidget<UVerticalBox>(
            UVerticalBox::StaticClass(),
            TEXT("ClanMembersContent")
        );
        Frame->SetContent(Content);
        UTextBlock* Heading = MakeText(
            Tree,
            TEXT("ClanMembersHeadingText"),
            TEXT("KLAN ÜYELERİ (0)"),
            20
        );
        Heading->SetColorAndOpacity(FSlateColor(FLinearColor(0.35f, 0.90f, 0.82f, 1.0f)));
        UTextBlock* Status = MakeText(
            Tree,
            TEXT("ClanMembersStatusText"),
            TEXT("0 çevrimiçi | 0 çevrimdışı"),
            15
        );
        Status->SetColorAndOpacity(FSlateColor(FLinearColor(0.78f, 0.84f, 0.82f, 1.0f)));
        AddVertical(Content, Heading, FMargin(0, 0, 0, 6));
        AddVertical(Content, Status, FMargin(0, 0, 0, 12));
        AddVertical(Content, Members);

        UVerticalBoxSlot* MemberSlot = Cast<UVerticalBoxSlot>(
            ClanPage->InsertChildAt(MemberIndex, Frame)
        );
        if (!MemberSlot)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI clan members panel update failed: panel slot could not be inserted."));
            return false;
        }
        MemberSlot->SetPadding(FMargin(0, 0, 0, 14));
        MemberSlot->SetHorizontalAlignment(HAlign_Fill);

        FBlueprintEditorUtils::MarkBlueprintAsStructurallyModified(Panel);
        FKismetEditorUtilities::CompileBlueprint(Panel);
        if (!SaveAsset(Panel))
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI clan members panel update failed while saving panel."));
            return false;
        }
        UE_LOG(LogTemp, Display, TEXT("PALTR_UI_CLAN_MEMBERS_PANEL_UPDATE_OK | changed=true"));
        return true;
    }

    bool UpdateFooterHints()
    {
        UWidgetBlueprint* Panel = LoadObject<UWidgetBlueprint>(
            nullptr,
            TEXT("/Game/Mods/PalTRUI/WBP_PalTRPanel.WBP_PalTRPanel")
        );
        if (!Panel || !Panel->WidgetTree)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI footer update failed: panel asset missing."));
            return false;
        }
        UWidgetTree* Tree = Panel->WidgetTree;
        UVerticalBox* Layout = Cast<UVerticalBox>(Tree->FindWidget(TEXT("PanelLayout")));
        UBorder* Frame = Cast<UBorder>(Tree->FindWidget(TEXT("FooterFrame")));
        UTextBlock* Hint = Cast<UTextBlock>(Tree->FindWidget(TEXT("FooterHintText")));
        if (!Layout)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI footer update failed: panel layout missing."));
            return false;
        }
        if (Frame && Hint)
        {
            UE_LOG(LogTemp, Display, TEXT("PALTR_UI_FOOTER_UPDATE_OK | changed=false"));
            return true;
        }
        if (Frame || Hint)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI footer update refused: partial controls exist."));
            return false;
        }

        Panel->Modify();
        Tree->Modify();
        Layout->Modify();
        Frame = Tree->ConstructWidget<UBorder>(
            UBorder::StaticClass(),
            TEXT("FooterFrame")
        );
        Frame->SetBrushColor(FLinearColor(0.015f, 0.035f, 0.045f, 0.98f));
        Frame->SetPadding(FMargin(12.0f, 8.0f));
        Hint = MakeText(
            Tree,
            TEXT("FooterHintText"),
            TEXT("F6  Panel   |   Tab  Kapat"),
            15
        );
        Hint->SetColorAndOpacity(FSlateColor(FLinearColor(0.92f, 0.68f, 0.25f, 1.0f)));
        Frame->SetContent(Hint);
        AddVertical(Layout, Frame, FMargin(0, 12, 0, 0));

        FBlueprintEditorUtils::MarkBlueprintAsStructurallyModified(Panel);
        FKismetEditorUtilities::CompileBlueprint(Panel);
        if (!SaveAsset(Panel))
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI footer update failed while saving panel."));
            return false;
        }
        UE_LOG(LogTemp, Display, TEXT("PALTR_UI_FOOTER_UPDATE_OK | changed=true"));
        return true;
    }

    bool UpdatePremiumTheme()
    {
        UWidgetBlueprint* Panel = LoadObject<UWidgetBlueprint>(
            nullptr,
            TEXT("/Game/Mods/PalTRUI/WBP_PalTRPanel.WBP_PalTRPanel")
        );
        if (!Panel || !Panel->WidgetTree)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI premium theme update failed: panel asset missing."));
            return false;
        }

        UWidgetTree* Tree = Panel->WidgetTree;
        UBorder* Background = Cast<UBorder>(Tree->FindWidget(TEXT("PanelBackground")));
        UHorizontalBox* TabBar = Cast<UHorizontalBox>(Tree->FindWidget(TEXT("TabBar")));
        UBorder* TabFrame = Cast<UBorder>(Tree->FindWidget(TEXT("TabFrame")));
        UBorder* ContentFrame = Cast<UBorder>(Tree->FindWidget(TEXT("ContentFrame")));
        if (!Background || !TabBar || !TabFrame || !ContentFrame)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI premium theme update failed: core themed hierarchy missing."));
            return false;
        }

        Panel->Modify();
        Tree->Modify();
        Background->Modify();
        TabBar->Modify();

        const FLinearColor DeepNavy(0.006f, 0.014f, 0.024f, 0.985f);
        const FLinearColor Navy(0.012f, 0.035f, 0.052f, 0.985f);
        const FLinearColor RaisedNavy(0.022f, 0.070f, 0.092f, 0.98f);
        const FLinearColor Gold(0.88f, 0.64f, 0.23f, 1.0f);
        const FLinearColor PaleGold(0.98f, 0.84f, 0.52f, 1.0f);
        const FLinearColor Ivory(0.94f, 0.91f, 0.82f, 1.0f);
        const FLinearColor Teal(0.025f, 0.19f, 0.22f, 1.0f);
        const FLinearColor Green(0.035f, 0.24f, 0.14f, 1.0f);
        const FLinearColor Amber(0.25f, 0.16f, 0.045f, 1.0f);
        const FLinearColor Red(0.30f, 0.055f, 0.045f, 1.0f);

        Background->SetBrushColor(DeepNavy);
        Background->SetPadding(FMargin(20.0f));
        StyleFrame(Tree, TEXT("TabFrame"), FLinearColor(0.12f, 0.085f, 0.025f, 0.99f), FMargin(2.0f));
        StyleFrame(Tree, TEXT("ContentFrame"), Navy, FMargin(20.0f));
        StyleFrame(Tree, TEXT("HeaderGuildFrame"), FLinearColor(0.02f, 0.16f, 0.18f, 1.0f), FMargin(10.0f, 6.0f));
        StyleFrame(Tree, TEXT("HeaderRoleFrame"), FLinearColor(0.22f, 0.14f, 0.035f, 1.0f), FMargin(10.0f, 6.0f));
        StyleFrame(Tree, TEXT("HeaderNotificationFrame"), FLinearColor(0.30f, 0.055f, 0.04f, 1.0f), FMargin(10.0f, 6.0f));
        StyleFrame(Tree, TEXT("DashboardClanCardFrame"), FLinearColor(0.018f, 0.16f, 0.16f, 0.98f), FMargin(17.0f));
        StyleFrame(Tree, TEXT("DashboardDiplomacyCardFrame"), FLinearColor(0.022f, 0.10f, 0.17f, 0.98f), FMargin(17.0f));
        StyleFrame(Tree, TEXT("DashboardRelationsFrame"), FLinearColor(0.10f, 0.075f, 0.025f, 0.98f), FMargin(15.0f));
        StyleFrame(Tree, TEXT("ClanMembersFrame"), FLinearColor(0.018f, 0.105f, 0.13f, 0.98f), FMargin(16.0f));
        StyleFrame(Tree, TEXT("PendingOffersFrame"), FLinearColor(0.085f, 0.060f, 0.020f, 0.98f), FMargin(15.0f));
        StyleFrame(Tree, TEXT("DashboardQuickActionsFrame"), RaisedNavy, FMargin(15.0f));
        StyleFrame(Tree, TEXT("AllianceDetailFrame"), FLinearColor(0.025f, 0.095f, 0.13f, 0.98f), FMargin(16.0f));
        StyleFrame(Tree, TEXT("GuildCatalogActiveFrame"), FLinearColor(0.018f, 0.14f, 0.13f, 0.98f), FMargin(16.0f));
        StyleFrame(Tree, TEXT("GuildCatalogRegisteredFrame"), FLinearColor(0.05f, 0.07f, 0.10f, 0.98f), FMargin(16.0f));
        StyleFrame(Tree, TEXT("FooterFrame"), FLinearColor(0.10f, 0.07f, 0.02f, 0.99f), FMargin(12.0f, 8.0f));

        for (const FName Tab : {
            FName(TEXT("ClanTabButton")),
            FName(TEXT("DiplomacyTabButton")),
            FName(TEXT("AllianceTabButton")),
            FName(TEXT("ChatTabButton"))
        })
        {
            StyleButton(Tree, Tab, RaisedNavy);
            if (UButton* Button = Cast<UButton>(Tree->FindWidget(Tab)))
            {
                if (UHorizontalBoxSlot* Slot = Cast<UHorizontalBoxSlot>(Button->Slot))
                {
                    Slot->Modify();
                    Slot->SetSize(FSlateChildSize(ESlateSizeRule::Fill));
                    Slot->SetHorizontalAlignment(HAlign_Fill);
                    Slot->SetPadding(FMargin(3.0f, 2.0f));
                }
                if (UTextBlock* Label = Cast<UTextBlock>(Button->GetContent()))
                {
                    Label->SetJustification(ETextJustify::Center);
                }
            }
        }

        StyleButton(Tree, TEXT("PreviousRelationButton"), Amber);
        StyleButton(Tree, TEXT("NextRelationButton"), Amber);
        StyleButton(Tree, TEXT("PreviousAllianceButton"), Amber);
        StyleButton(Tree, TEXT("NextAllianceButton"), Amber);
        StyleButton(Tree, TEXT("DashboardDiplomacyButton"), Teal);
        StyleButton(Tree, TEXT("DashboardOffersButton"), Teal);
        StyleButton(Tree, TEXT("DashboardGuildsButton"), Teal);
        StyleButton(Tree, TEXT("AllianceRequestButton"), Teal);
        StyleButton(Tree, TEXT("WarRequestButton"), Red);
        StyleButton(Tree, TEXT("AcceptButton"), Green);
        StyleButton(Tree, TEXT("RejectButton"), Red);
        StyleButton(Tree, TEXT("CancelButton"), Amber);
        StyleButton(Tree, TEXT("CloseButton"), Red);

        SetTextColor(Tree, TEXT("TitleText"), PaleGold);
        SetTextColor(Tree, TEXT("ConnectionStatusText"), Ivory);
        SetTextColor(Tree, TEXT("FooterHintText"), PaleGold);
        for (const FName Heading : {
            FName(TEXT("ClanHeadingText")),
            FName(TEXT("DiplomacyHeadingText")),
            FName(TEXT("AllianceHeadingText")),
            FName(TEXT("ChatHeadingText")),
            FName(TEXT("DashboardDiplomacyCardTitleText")),
            FName(TEXT("DashboardRelationsHeadingText")),
            FName(TEXT("PendingOffersHeadingText")),
            FName(TEXT("DashboardQuickActionsHeadingText"))
        })
        {
            SetTextColor(Tree, Heading, PaleGold);
        }
        SetTextColor(Tree, TEXT("DashboardClanCardTitleText"), FLinearColor(0.40f, 0.90f, 0.84f, 1.0f));
        SetTextColor(Tree, TEXT("ClanMembersHeadingText"), FLinearColor(0.40f, 0.90f, 0.84f, 1.0f));
        SetTextFontSize(Tree, TEXT("TitleText"), 30);
        SetTextFontSize(Tree, TEXT("ClanHeadingText"), 24);
        SetTextFontSize(Tree, TEXT("DiplomacyHeadingText"), 24);
        SetTextFontSize(Tree, TEXT("AllianceHeadingText"), 24);
        SetTextFontSize(Tree, TEXT("ChatHeadingText"), 24);

        FBlueprintEditorUtils::MarkBlueprintAsStructurallyModified(Panel);
        FKismetEditorUtilities::CompileBlueprint(Panel);
        if (!SaveAsset(Panel))
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI premium theme update failed while saving panel."));
            return false;
        }
        UE_LOG(LogTemp, Display, TEXT("PALTR_UI_PREMIUM_THEME_UPDATE_OK | palette=navy_gold | tabs=equal"));
        return true;
    }

    bool VerifyAssets()
    {
        UBlueprint* ModActor = LoadObject<UBlueprint>(
            nullptr,
            TEXT("/Game/Mods/PalTRUI/ModActor.ModActor")
        );
        UWidgetBlueprint* Panel = LoadObject<UWidgetBlueprint>(
            nullptr,
            TEXT("/Game/Mods/PalTRUI/WBP_PalTRPanel.WBP_PalTRPanel")
        );
        if (!ModActor || !ModActor->GeneratedClass || !Panel || !Panel->GeneratedClass || !Panel->WidgetTree)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI asset verification failed while loading generated classes."));
            return false;
        }

        static const TCHAR* RequiredTextures[] = {
            TEXT("/Game/Mods/PalTRUI/Art/T_PalTRPanelFrame.T_PalTRPanelFrame"),
            TEXT("/Game/Mods/PalTRUI/Art/T_PalTRClanIcon.T_PalTRClanIcon"),
            TEXT("/Game/Mods/PalTRUI/Art/T_PalTRDiplomacyIcon.T_PalTRDiplomacyIcon"),
            TEXT("/Game/Mods/PalTRUI/Art/T_PalTRProtectionIcon.T_PalTRProtectionIcon"),
            TEXT("/Game/Mods/PalTRUI/Art/T_PalTRBuildingsIcon.T_PalTRBuildingsIcon")
        };
        for (const TCHAR* TexturePath : RequiredTextures)
        {
            if (!LoadObject<UTexture2D>(nullptr, TexturePath))
            {
                UE_LOG(LogTemp, Error, TEXT("PalTRUI asset verification failed: missing texture '%s'."), TexturePath);
                return false;
            }
        }

        static const FName RequiredWidgets[] = {
            TEXT("RootCanvas"),
            TEXT("PanelInputShield"),
            TEXT("PanelBackground"),
            TEXT("TitleText"),
            TEXT("ConnectionStatusText"),
            TEXT("CloseButton"),
            TEXT("ClanTabButton"),
            TEXT("DiplomacyTabButton"),
            TEXT("AllianceTabButton"),
            TEXT("ChatTabButton"),
            TEXT("ContentFrame"),
            TEXT("ContentSwitcher"),
            TEXT("ClanPageScroll"),
            TEXT("DiplomacyPageScroll"),
            TEXT("AlliancePageScroll"),
            TEXT("GuildPageScroll"),
            TEXT("DashboardColumns"),
            TEXT("DashboardMainColumn"),
            TEXT("DashboardSidebarColumn"),
            TEXT("HeaderFrame"),
            TEXT("ClanSubtitleText"),
            TEXT("DiplomacySubtitleText"),
            TEXT("AllianceSubtitleText"),
            TEXT("GuildSubtitleText"),
            TEXT("DashboardSidebarTitleFrame"),
            TEXT("DashboardSidebarTitleText"),
            TEXT("DiplomacyListFrame"),
            TEXT("DiplomacyDetailFrame"),
            TEXT("PanelArtOverlay"),
            TEXT("PanelArtImage"),
            TEXT("PanelArtContentPadding"),
            TEXT("PanelBodyRow"),
            TEXT("LeftNavigationSize"),
            TEXT("LeftNavigationFrame"),
            TEXT("LeftNavigation"),
            TEXT("LeftNavigationHeadingText"),
            TEXT("HeaderCrestSpacer"),
            TEXT("HeaderCrestImageSize"),
            TEXT("HeaderCrestImage"),
            TEXT("DashboardClanIcon"),
            TEXT("DashboardDiplomacyIcon"),
            TEXT("DashboardProtectionCardFrame"),
            TEXT("DashboardProtectionIcon"),
            TEXT("DashboardBuildingsCardFrame"),
            TEXT("DashboardBuildingsIcon"),
            TEXT("DashboardLowerRow"),
            TEXT("DashboardRecentEventsFrame"),
            TEXT("DashboardRecentEventsHeadingText"),
            TEXT("DashboardRecentEventsText"),
            TEXT("ClanNameText"),
            TEXT("ClanSummaryText"),
            TEXT("ClanMembersFrame"),
            TEXT("ClanMembersContent"),
            TEXT("ClanMembersHeadingText"),
            TEXT("ClanMembersStatusText"),
            TEXT("ClanMembersText"),
            TEXT("PendingOffersFrame"),
            TEXT("PendingOffersHeadingText"),
            TEXT("PendingOffersText"),
            TEXT("DashboardQuickActionsFrame"),
            TEXT("DashboardQuickActionsContent"),
            TEXT("DashboardQuickActionsHeadingText"),
            TEXT("DashboardDiplomacyButton"),
            TEXT("DashboardDiplomacyButtonText"),
            TEXT("DashboardOffersButton"),
            TEXT("DashboardOffersButtonText"),
            TEXT("DashboardGuildsButton"),
            TEXT("DashboardGuildsButtonText"),
            TEXT("DashboardStatusCardsFrame"),
            TEXT("DashboardClanCardFrame"),
            TEXT("DashboardClanCardContent"),
            TEXT("DashboardClanCardTitleText"),
            TEXT("DashboardClanCardValueText"),
            TEXT("DashboardClanCardDetailText"),
            TEXT("DashboardDiplomacyCardFrame"),
            TEXT("DashboardDiplomacyCardContent"),
            TEXT("DashboardDiplomacyCardTitleText"),
            TEXT("DashboardDiplomacyCardValueText"),
            TEXT("DashboardDiplomacyCardDetailText"),
            TEXT("DashboardRelationsFrame"),
            TEXT("DashboardRelationsContent"),
            TEXT("DashboardRelationsHeadingText"),
            TEXT("DashboardRelationsText"),
            TEXT("AllianceDetailFrame"),
            TEXT("AllianceDetailContent"),
            TEXT("AllianceTitleText"),
            TEXT("AllianceStateText"),
            TEXT("AllianceDescriptionText"),
            TEXT("AllianceNavigation"),
            TEXT("PreviousAllianceButton"),
            TEXT("PreviousAllianceButtonText"),
            TEXT("NextAllianceButton"),
            TEXT("NextAllianceButtonText"),
            TEXT("GuildCatalogSummaryText"),
            TEXT("GuildCatalogColumns"),
            TEXT("GuildCatalogActiveFrame"),
            TEXT("GuildCatalogActiveContent"),
            TEXT("GuildCatalogActiveHeadingText"),
            TEXT("GuildCatalogActiveText"),
            TEXT("GuildCatalogRegisteredFrame"),
            TEXT("GuildCatalogRegisteredContent"),
            TEXT("GuildCatalogRegisteredHeadingText"),
            TEXT("GuildCatalogRegisteredText"),
            TEXT("HeaderGuildFrame"),
            TEXT("HeaderGuildText"),
            TEXT("HeaderRoleFrame"),
            TEXT("HeaderRoleText"),
            TEXT("HeaderNotificationFrame"),
            TEXT("HeaderNotificationText"),
            TEXT("FooterFrame"),
            TEXT("FooterHintText"),
            TEXT("RelationList"),
            TEXT("RelationTitleText"),
            TEXT("RelationStateText"),
            TEXT("RelationDescriptionText"),
            TEXT("PreviousRelationButton"),
            TEXT("PreviousRelationButtonText"),
            TEXT("NextRelationButton"),
            TEXT("NextRelationButtonText"),
            TEXT("AllianceRequestButton"),
            TEXT("WarRequestButton"),
            TEXT("AcceptButton"),
            TEXT("RejectButton"),
            TEXT("CancelButton"),
            TEXT("AllianceSummaryText"),
            TEXT("AllianceMembersText"),
            TEXT("ChatMessageList"),
            TEXT("ChatInput"),
            TEXT("ChatSendButton")
        };

        for (const FName WidgetName : RequiredWidgets)
        {
            if (!Panel->WidgetTree->FindWidget(WidgetName))
            {
                UE_LOG(LogTemp, Error, TEXT("PalTRUI asset verification failed: missing widget '%s'."), *WidgetName.ToString());
                return false;
            }
        }

        UButton* InputShield = Cast<UButton>(Panel->WidgetTree->FindWidget(TEXT("PanelInputShield")));
        UCanvasPanelSlot* InputShieldSlot = InputShield
            ? Cast<UCanvasPanelSlot>(InputShield->Slot)
            : nullptr;
        UBorder* PanelBackground = Cast<UBorder>(Panel->WidgetTree->FindWidget(TEXT("PanelBackground")));
        UButtonSlot* PanelContentSlot = PanelBackground
            ? Cast<UButtonSlot>(PanelBackground->Slot)
            : nullptr;
        UOverlay* PanelArtOverlay = Cast<UOverlay>(Panel->WidgetTree->FindWidget(TEXT("PanelArtOverlay")));
        UBorder* PanelContentPadding = Cast<UBorder>(Panel->WidgetTree->FindWidget(TEXT("PanelArtContentPadding")));
        UBorderSlot* PanelArtOverlaySlot = PanelArtOverlay
            ? Cast<UBorderSlot>(PanelArtOverlay->Slot)
            : nullptr;
        UOverlaySlot* PanelContentPaddingSlot = PanelContentPadding
            ? Cast<UOverlaySlot>(PanelContentPadding->Slot)
            : nullptr;
        const FAnchors ExpectedPanelAnchors(0.04f, 0.05f, 0.96f, 0.95f);
        const FAnchors ActualPanelAnchors = InputShieldSlot
            ? InputShieldSlot->GetAnchors()
            : FAnchors();
        const FMargin ActualPanelOffsets = InputShieldSlot
            ? InputShieldSlot->GetOffsets()
            : FMargin();
        if (!InputShieldSlot
            || !ActualPanelAnchors.Minimum.Equals(ExpectedPanelAnchors.Minimum, KINDA_SMALL_NUMBER)
            || !ActualPanelAnchors.Maximum.Equals(ExpectedPanelAnchors.Maximum, KINDA_SMALL_NUMBER)
            || !InputShieldSlot->GetAlignment().Equals(FVector2D::ZeroVector, KINDA_SMALL_NUMBER)
            || !FMath::IsNearlyZero(ActualPanelOffsets.Left)
            || !FMath::IsNearlyZero(ActualPanelOffsets.Top)
            || !FMath::IsNearlyZero(ActualPanelOffsets.Right)
            || !FMath::IsNearlyZero(ActualPanelOffsets.Bottom))
        {
            UE_LOG(
                LogTemp,
                Error,
                TEXT("PalTRUI asset verification failed: responsive panel anchors or offsets are invalid.")
            );
            return false;
        }
        if (!PanelContentSlot
            || PanelContentSlot->GetHorizontalAlignment() != HAlign_Fill
            || PanelContentSlot->GetVerticalAlignment() != VAlign_Fill
            || !PanelBackground
            || PanelBackground->GetHorizontalAlignment() != HAlign_Fill
            || PanelBackground->GetVerticalAlignment() != VAlign_Fill
            || !PanelArtOverlaySlot
            || PanelArtOverlaySlot->GetHorizontalAlignment() != HAlign_Fill
            || PanelArtOverlaySlot->GetVerticalAlignment() != VAlign_Fill
            || !PanelContentPaddingSlot
            || PanelContentPaddingSlot->GetHorizontalAlignment() != HAlign_Fill
            || PanelContentPaddingSlot->GetVerticalAlignment() != VAlign_Fill
            || PanelContentPadding->GetHorizontalAlignment() != HAlign_Fill
            || PanelContentPadding->GetVerticalAlignment() != VAlign_Fill)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI asset verification failed: panel fill chain is incomplete."));
            return false;
        }

        UE_LOG(
            LogTemp,
            Display,
            TEXT("PALTR_UI_ASSET_VERIFY_OK | mod_actor=%s | panel=%s | widgets=%d | textures=%d | viewport=92x90pct | fill_chain=complete"),
            *ModActor->GeneratedClass->GetPathName(),
            *Panel->GeneratedClass->GetPathName(),
            UE_ARRAY_COUNT(RequiredWidgets),
            UE_ARRAY_COUNT(RequiredTextures)
        );
        return true;
    }
}

UPalTRUIAssetBuilderCommandlet::UPalTRUIAssetBuilderCommandlet()
{
    IsClient = false;
    IsEditor = true;
    IsServer = false;
    LogToConsole = true;
    ShowErrorCount = true;
}

int32 UPalTRUIAssetBuilderCommandlet::Main(const FString& Params)
{
    using namespace PalTRUIAssetBuilder;

    if (FParse::Param(*Params, TEXT("Verify")))
    {
        return VerifyAssets() ? 0 : 5;
    }

    if (FParse::Param(*Params, TEXT("UpdateRelationNavigation")))
    {
        return UpdateRelationNavigation() ? 0 : 6;
    }

    if (FParse::Param(*Params, TEXT("UpdateGuildCatalogPage")))
    {
        return UpdateGuildCatalogPage() ? 0 : 7;
    }

    if (FParse::Param(*Params, TEXT("UpdateDiplomacyTheme")))
    {
        return UpdateDiplomacyTheme() ? 0 : 8;
    }

    if (FParse::Param(*Params, TEXT("UpdatePendingOffersPanel")))
    {
        return UpdatePendingOffersPanel() ? 0 : 9;
    }

    if (FParse::Param(*Params, TEXT("UpdateDashboardQuickActions")))
    {
        return UpdateDashboardQuickActions() ? 0 : 10;
    }

    if (FParse::Param(*Params, TEXT("UpdateDashboardStatusCards")))
    {
        return UpdateDashboardStatusCards() ? 0 : 11;
    }

    if (FParse::Param(*Params, TEXT("UpdateDashboardRelationsPreview")))
    {
        return UpdateDashboardRelationsPreview() ? 0 : 12;
    }

    if (FParse::Param(*Params, TEXT("UpdateAllianceDetailPanel")))
    {
        return UpdateAllianceDetailPanel() ? 0 : 13;
    }

    if (FParse::Param(*Params, TEXT("UpdateGuildCatalogCards")))
    {
        return UpdateGuildCatalogCards() ? 0 : 14;
    }

    if (FParse::Param(*Params, TEXT("UpdateHeaderStatusBadges")))
    {
        return UpdateHeaderStatusBadges() ? 0 : 15;
    }

    if (FParse::Param(*Params, TEXT("UpdateFooterHints")))
    {
        return UpdateFooterHints() ? 0 : 16;
    }

    if (FParse::Param(*Params, TEXT("UpdateClanMembersPanel")))
    {
        return UpdateClanMembersPanel() ? 0 : 17;
    }

    if (FParse::Param(*Params, TEXT("UpdatePanelInputShield")))
    {
        return UpdatePanelInputShield() ? 0 : 18;
    }

    if (FParse::Param(*Params, TEXT("UpdateClanPageScroll")))
    {
        return UpdateClanPageScroll() ? 0 : 19;
    }

    if (FParse::Param(*Params, TEXT("UpdatePremiumTheme")))
    {
        return UpdatePremiumTheme() ? 0 : 20;
    }

    if (FParse::Param(*Params, TEXT("UpdateAllPageScrollInput")))
    {
        return UpdateAllPageScrollInput() ? 0 : 21;
    }

    if (FParse::Param(*Params, TEXT("UpdateDashboardColumnLayout")))
    {
        return UpdateDashboardColumnLayout() ? 0 : 22;
    }

    if (FParse::Param(*Params, TEXT("UpdatePresentationHierarchy")))
    {
        return UpdatePresentationHierarchy() ? 0 : 23;
    }

    if (FParse::Param(*Params, TEXT("UpdateArtDashboard")))
    {
        return UpdateArtDashboard() ? 0 : 24;
    }

    const FString ModActorPackage = FString(AssetRoot) / TEXT("ModActor");
    const FString PanelPackage = FString(AssetRoot) / TEXT("WBP_PalTRPanel");
    if (FPackageName::DoesPackageExist(ModActorPackage) || FPackageName::DoesPackageExist(PanelPackage))
    {
        UE_LOG(LogTemp, Error, TEXT("PalTRUI asset generation refused: target assets already exist."));
        return 2;
    }

    UBlueprint* ModActor = CreateModActor();
    UWidgetBlueprint* Panel = CreatePanelWidget();
    if (!ModActor || !Panel)
    {
        UE_LOG(LogTemp, Error, TEXT("PalTRUI asset generation failed while constructing assets."));
        return 3;
    }

    if (!SaveAsset(ModActor) || !SaveAsset(Panel))
    {
        UE_LOG(LogTemp, Error, TEXT("PalTRUI asset generation failed while saving packages."));
        return 4;
    }

    UE_LOG(LogTemp, Display, TEXT("PALTR_UI_ASSET_BUILD_OK | root=%s"), AssetRoot);
    return 0;
}
