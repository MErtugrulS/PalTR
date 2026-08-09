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
