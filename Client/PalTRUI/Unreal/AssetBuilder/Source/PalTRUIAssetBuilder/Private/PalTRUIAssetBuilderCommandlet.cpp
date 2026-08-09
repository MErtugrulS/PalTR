#include "PalTRUIAssetBuilderCommandlet.h"

#include "AssetRegistry/AssetRegistryModule.h"
#include "Blueprint/UserWidget.h"
#include "Blueprint/WidgetBlueprintGeneratedClass.h"
#include "Blueprint/WidgetTree.h"
#include "Components/Border.h"
#include "Components/Button.h"
#include "Components/CanvasPanel.h"
#include "Components/CanvasPanelSlot.h"
#include "Components/EditableTextBox.h"
#include "Components/HorizontalBox.h"
#include "Components/HorizontalBoxSlot.h"
#include "Components/PanelWidget.h"
#include "Components/ScrollBox.h"
#include "Components/SizeBox.h"
#include "Components/TextBlock.h"
#include "Components/VerticalBox.h"
#include "Components/VerticalBoxSlot.h"
#include "Components/WidgetSwitcher.h"
#include "Engine/Blueprint.h"
#include "GameFramework/Actor.h"
#include "Kismet2/KismetEditorUtilities.h"
#include "Kismet2/BlueprintEditorUtils.h"
#include "Misc/Parse.h"
#include "Misc/PackageName.h"
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
        Button->SetBackgroundColor(Color);
        if (UTextBlock* Label = Cast<UTextBlock>(Button->GetContent()))
        {
            Label->Modify();
            Label->SetColorAndOpacity(FSlateColor(FLinearColor(0.95f, 0.88f, 0.70f, 1.0f)));
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
        BackgroundSlot->SetAnchors(FAnchors(0.5f));
        BackgroundSlot->SetAlignment(FVector2D(0.5f, 0.5f));
        BackgroundSlot->SetSize(FVector2D(1180.0f, 720.0f));

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

        static const FName RequiredWidgets[] = {
            TEXT("RootCanvas"),
            TEXT("PanelBackground"),
            TEXT("TitleText"),
            TEXT("ConnectionStatusText"),
            TEXT("CloseButton"),
            TEXT("ClanTabButton"),
            TEXT("DiplomacyTabButton"),
            TEXT("AllianceTabButton"),
            TEXT("ChatTabButton"),
            TEXT("TabFrame"),
            TEXT("ContentFrame"),
            TEXT("ContentSwitcher"),
            TEXT("ClanNameText"),
            TEXT("ClanSummaryText"),
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

        UE_LOG(
            LogTemp,
            Display,
            TEXT("PALTR_UI_ASSET_VERIFY_OK | mod_actor=%s | panel=%s | widgets=%d"),
            *ModActor->GeneratedClass->GetPathName(),
            *Panel->GeneratedClass->GetPathName(),
            UE_ARRAY_COUNT(RequiredWidgets)
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
