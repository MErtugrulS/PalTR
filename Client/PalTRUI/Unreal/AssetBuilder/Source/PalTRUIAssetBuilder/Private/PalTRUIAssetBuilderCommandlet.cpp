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
#include "Components/SizeBoxSlot.h"
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

    namespace PixelTheme
    {
        FLinearColor FromSRGB(const uint8 R, const uint8 G, const uint8 B, const float Alpha = 1.0f)
        {
            FLinearColor Result = FLinearColor::FromSRGBColor(FColor(R, G, B, 255));
            Result.A = Alpha;
            return Result;
        }

        // Slate consumes linear colors. Keeping the palette in authored sRGB avoids
        // the washed-out gray result produced by passing sRGB channel values directly.
        const FLinearColor Background = FromSRGB(7, 18, 27, 0.995f);
        const FLinearColor PanelDark = FromSRGB(11, 27, 40, 0.985f);
        const FLinearColor PanelBlue = FromSRGB(24, 52, 70, 0.96f);
        const FLinearColor Gold = FromSRGB(198, 154, 72, 0.98f);
        const FLinearColor GoldMuted = FromSRGB(131, 107, 60, 0.96f);
        const FLinearColor Cyan = FromSRGB(40, 217, 237, 0.96f);
        const FLinearColor CyanDark = FromSRGB(14, 58, 70, 0.98f);
        const FLinearColor Parchment = FromSRGB(195, 164, 123, 1.0f);
        const FLinearColor TextPrimary = FromSRGB(242, 232, 213, 1.0f);
        const FLinearColor TextSecondary = FromSRGB(184, 185, 181, 1.0f);
        const FLinearColor RelationDark = FromSRGB(28, 29, 25, 0.97f);
    }

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
        const FLinearColor Outline = PixelTheme::GoldMuted;
        const FLinearColor Hover(
            FMath::Min(Color.R * 1.20f, 1.0f),
            FMath::Min(Color.G * 1.20f, 1.0f),
            FMath::Min(Color.B * 1.20f, 1.0f),
            Color.A
        );
        const FLinearColor Pressed(Color.R * 0.82f, Color.G * 0.82f, Color.B * 0.82f, Color.A);
        FButtonStyle Style = Button->WidgetStyle;
        Style.SetNormal(FSlateRoundedBoxBrush(Color, 6.0f, Outline, 1.5f));
        Style.SetHovered(FSlateRoundedBoxBrush(Hover, 6.0f, PixelTheme::Cyan, 2.0f));
        Style.SetPressed(FSlateRoundedBoxBrush(Pressed, 5.0f, PixelTheme::Gold, 2.0f));
        Style.SetDisabled(FSlateRoundedBoxBrush(PixelTheme::FromSRGB(25, 31, 34, 0.78f), 6.0f, PixelTheme::FromSRGB(67, 71, 70, 0.72f), 1.0f));
        Style.SetNormalPadding(FMargin(7.0f, 5.0f));
        Style.SetPressedPadding(FMargin(7.0f, 6.0f, 7.0f, 4.0f));
        Button->SetStyle(Style);
        Button->SetBackgroundColor(FLinearColor::White);
        if (UTextBlock* Label = Cast<UTextBlock>(Button->GetContent()))
        {
            Label->Modify();
            Label->SetColorAndOpacity(FSlateColor(PixelTheme::TextPrimary));
            Label->SetShadowOffset(FVector2D(1.0f, 2.0f));
            Label->SetShadowColorAndOpacity(FLinearColor(0, 0, 0, 0.85f));
        }
    }

    void StyleTextShadow(
        UWidgetTree* Tree,
        const FName Name,
        const FVector2D Offset = FVector2D(1.0f, 2.0f),
        const FLinearColor Color = FLinearColor(0, 0, 0, 0.86f)
    )
    {
        if (UTextBlock* Text = Cast<UTextBlock>(Tree->FindWidget(Name)))
        {
            Text->Modify();
            Text->SetShadowOffset(Offset);
            Text->SetShadowColorAndOpacity(Color);
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

    void StyleTextureFrame(
        UWidgetTree* Tree,
        const FName Name,
        UTexture2D* Texture,
        const FMargin BrushMargin,
        const FMargin Padding,
        const FLinearColor Tint = FLinearColor::White
    )
    {
        UBorder* Frame = Cast<UBorder>(Tree->FindWidget(Name));
        if (!Frame || !Texture)
        {
            return;
        }

        Frame->Modify();
        FSlateBrush Brush;
        Brush.SetResourceObject(Texture);
        Brush.ImageSize = FVector2D(Texture->GetSizeX(), Texture->GetSizeY());
        Brush.DrawAs = ESlateBrushDrawType::Box;
        Brush.Margin = BrushMargin;
        Brush.TintColor = FSlateColor(Tint);
        Frame->SetBrush(Brush);
        Frame->SetBrushColor(FLinearColor::White);
        Frame->SetPadding(Padding);
    }

    void StyleTransparentFrame(UWidgetTree* Tree, const FName Name, const FMargin Padding)
    {
        if (UBorder* Frame = Cast<UBorder>(Tree->FindWidget(Name)))
        {
            Frame->Modify();
            Frame->SetBrush(FSlateNoResource());
            Frame->SetBrushColor(FLinearColor::Transparent);
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
        if (UHorizontalBoxSlot* NavigationOuterSlot = Cast<UHorizontalBoxSlot>(NavigationSize->Slot))
        {
            NavigationOuterSlot->Modify();
            NavigationOuterSlot->SetVerticalAlignment(VAlign_Fill);
        }
        if (USizeBoxSlot* NavigationInnerSlot = Cast<USizeBoxSlot>(NavigationFrame->Slot))
        {
            NavigationInnerSlot->Modify();
            NavigationInnerSlot->SetHorizontalAlignment(HAlign_Fill);
            NavigationInnerSlot->SetVerticalAlignment(VAlign_Fill);
        }
        NavigationFrame->SetHorizontalAlignment(HAlign_Fill);
        NavigationFrame->SetVerticalAlignment(VAlign_Fill);
        if (UVerticalBoxSlot* BodySlot = Cast<UVerticalBoxSlot>(BodyRow->Slot))
        {
            BodySlot->Modify();
            BodySlot->SetSize(FSlateChildSize(ESlateSizeRule::Fill));
            BodySlot->SetHorizontalAlignment(HAlign_Fill);
            BodySlot->SetVerticalAlignment(VAlign_Fill);
        }

        struct FFutureNavigationSpec
        {
            const TCHAR* ButtonName;
            const TCHAR* TextName;
            const TCHAR* Label;
        };
        const FFutureNavigationSpec FutureNavigation[] = {
            { TEXT("FutureProtectionButton"), TEXT("FutureProtectionButtonText"), TEXT("Savas / Koruma") },
            { TEXT("FutureStructuresButton"), TEXT("FutureStructuresButtonText"), TEXT("Yapilar") },
            { TEXT("FutureRegionsButton"), TEXT("FutureRegionsButtonText"), TEXT("Bolgeler") },
            { TEXT("FuturePlayersButton"), TEXT("FuturePlayersButtonText"), TEXT("Oyuncular") },
            { TEXT("FutureNotificationsButton"), TEXT("FutureNotificationsButtonText"), TEXT("Bildirimler") },
            { TEXT("FutureSettingsButton"), TEXT("FutureSettingsButtonText"), TEXT("Ayarlar") }
        };
        for (const FFutureNavigationSpec& Spec : FutureNavigation)
        {
            UButton* Button = Cast<UButton>(Tree->FindWidget(FName(Spec.ButtonName)));
            UTextBlock* ButtonText = Cast<UTextBlock>(Tree->FindWidget(FName(Spec.TextName)));
            if (!ButtonText && Button)
            {
                ButtonText = Cast<UTextBlock>(Button->GetContent());
            }
            if (!Button && !ButtonText)
            {
                Button = MakeTabButton(Tree, FName(Spec.ButtonName), FName(Spec.TextName), Spec.Label);
                ButtonText = Cast<UTextBlock>(Button->GetContent());
                UVerticalBoxSlot* ButtonSlot = AddVertical(Navigation, Button, FMargin(0, 0, 0, 6));
                ButtonSlot->SetHorizontalAlignment(HAlign_Fill);
            }
            else if (!Button || !ButtonText || Button->GetParent() != Navigation)
            {
                UE_LOG(LogTemp, Error, TEXT("PalTRUI art dashboard update refused: partial future navigation: %s"), Spec.ButtonName);
                return false;
            }
            Button->SetIsEnabled(false);
            ButtonText->SetText(FText::FromString(FString::Printf(TEXT("%s  |  YAKINDA"), Spec.Label)));
            SetTextFontSize(Tree, FName(Spec.TextName), 13);
            StyleButton(Tree, FName(Spec.ButtonName), FLinearColor(0.012f, 0.04f, 0.055f, 0.84f));
        }
        for (const FName LiveNavigationButton : {
            FName(TEXT("ClanTabButton")),
            FName(TEXT("DiplomacyTabButton")),
            FName(TEXT("AllianceTabButton")),
            FName(TEXT("ChatTabButton"))
        })
        {
            if (UButton* Button = Cast<UButton>(Tree->FindWidget(LiveNavigationButton)))
            {
                if (UVerticalBoxSlot* ButtonSlot = Cast<UVerticalBoxSlot>(Button->Slot))
                {
                    ButtonSlot->SetPadding(FMargin(0, 0, 0, 6));
                }
            }
        }

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
        UHorizontalBox* DashboardColumns = Cast<UHorizontalBox>(Tree->FindWidget(TEXT("DashboardColumns")));
        USizeBox* DashboardColumnsSize = Cast<USizeBox>(Tree->FindWidget(TEXT("DashboardColumnsSize")));
        if (!DashboardColumns)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI art dashboard update failed: dashboard columns missing."));
            return false;
        }
        if (!DashboardColumnsSize)
        {
            if (DashboardColumns->GetParent() != Cast<UVerticalBox>(Tree->FindWidget(TEXT("ClanPage"))))
            {
                UE_LOG(LogTemp, Error, TEXT("PalTRUI art dashboard update refused: dashboard columns parent changed."));
                return false;
            }
            UVerticalBox* ClanPage = Cast<UVerticalBox>(DashboardColumns->GetParent());
            const int32 ColumnsIndex = ClanPage->GetChildIndex(DashboardColumns);
            ClanPage->RemoveChild(DashboardColumns);
            DashboardColumnsSize = Tree->ConstructWidget<USizeBox>(USizeBox::StaticClass(), TEXT("DashboardColumnsSize"));
            DashboardColumnsSize->SetContent(DashboardColumns);
            UVerticalBoxSlot* ColumnsSizeSlot = Cast<UVerticalBoxSlot>(ClanPage->InsertChildAt(ColumnsIndex, DashboardColumnsSize));
            if (!ColumnsSizeSlot)
            {
                UE_LOG(LogTemp, Error, TEXT("PalTRUI art dashboard update failed: dashboard size slot missing."));
                return false;
            }
            ColumnsSizeSlot->SetHorizontalAlignment(HAlign_Fill);
        }
        else if (DashboardColumnsSize->GetContent() != DashboardColumns)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI art dashboard update refused: dashboard size wrapper changed."));
            return false;
        }
        DashboardColumnsSize->SetHeightOverride(650.0f);
        if (USizeBoxSlot* ColumnsInnerSlot = Cast<USizeBoxSlot>(DashboardColumns->Slot))
        {
            ColumnsInnerSlot->SetHorizontalAlignment(HAlign_Fill);
            ColumnsInnerSlot->SetVerticalAlignment(VAlign_Fill);
        }
        if (UHorizontalBoxSlot* MainSlot = Cast<UHorizontalBoxSlot>(MainColumn->Slot))
        {
            MainSlot->SetVerticalAlignment(VAlign_Fill);
        }
        if (UHorizontalBoxSlot* SidebarSlot = Cast<UHorizontalBoxSlot>(Sidebar->Slot))
        {
            SidebarSlot->SetVerticalAlignment(VAlign_Fill);
        }
        if (UVerticalBoxSlot* LowerSlot = Cast<UVerticalBoxSlot>(LowerRow->Slot))
        {
            LowerSlot->SetSize(FSlateChildSize(ESlateSizeRule::Fill));
            LowerSlot->SetVerticalAlignment(VAlign_Fill);
        }
        if (UHorizontalBoxSlot* RecentSlot = Cast<UHorizontalBoxSlot>(RecentFrame->Slot))
        {
            RecentSlot->SetVerticalAlignment(VAlign_Fill);
        }
        if (UHorizontalBoxSlot* QuickSlot = Cast<UHorizontalBoxSlot>(QuickActions->Slot))
        {
            QuickSlot->SetVerticalAlignment(VAlign_Fill);
        }
        if (UBorder* RelationsFrame = Cast<UBorder>(Tree->FindWidget(TEXT("DashboardRelationsFrame"))))
        {
            if (UVerticalBoxSlot* RelationsSlot = Cast<UVerticalBoxSlot>(RelationsFrame->Slot))
            {
                FSlateChildSize FillSize(ESlateSizeRule::Fill);
                FillSize.Value = 1.0f;
                RelationsSlot->SetSize(FillSize);
                RelationsSlot->SetVerticalAlignment(VAlign_Fill);
            }
        }
        if (UBorder* OffersFrame = Cast<UBorder>(Tree->FindWidget(TEXT("PendingOffersFrame"))))
        {
            if (UVerticalBoxSlot* OffersSlot = Cast<UVerticalBoxSlot>(OffersFrame->Slot))
            {
                FSlateChildSize FillSize(ESlateSizeRule::Fill);
                FillSize.Value = 1.0f;
                OffersSlot->SetSize(FillSize);
                OffersSlot->SetVerticalAlignment(VAlign_Fill);
            }
        }
        if (UTextBlock* RecentEvents = Cast<UTextBlock>(Tree->FindWidget(TEXT("DashboardRecentEventsText"))))
        {
            RecentEvents->SetVisibility(ESlateVisibility::Collapsed);
        }
        struct FRecentEventSpec
        {
            const TCHAR* FrameName;
            const TCHAR* RowName;
            const TCHAR* MessageName;
            const TCHAR* TimeName;
            const TCHAR* Message;
            const TCHAR* Time;
        };
        const FRecentEventSpec RecentEventSpecs[] = {
            { TEXT("DashboardRecentEvent1Frame"), TEXT("DashboardRecentEvent1Row"), TEXT("DashboardRecentEvent1MessageText"), TEXT("DashboardRecentEvent1TimeText"), TEXT("Exceed ile savas devam ediyor."), TEXT("5 dk once") },
            { TEXT("DashboardRecentEvent2Frame"), TEXT("DashboardRecentEvent2Row"), TEXT("DashboardRecentEvent2MessageText"), TEXT("DashboardRecentEvent2TimeText"), TEXT("Saru tarafsiz durumda."), TEXT("18 dk once") },
            { TEXT("DashboardRecentEvent3Frame"), TEXT("DashboardRecentEvent3Row"), TEXT("DashboardRecentEvent3MessageText"), TEXT("DashboardRecentEvent3TimeText"), TEXT("Ana us koruma kontrolu tamamlandi."), TEXT("1 saat once") },
            { TEXT("DashboardRecentEvent4Frame"), TEXT("DashboardRecentEvent4Row"), TEXT("DashboardRecentEvent4MessageText"), TEXT("DashboardRecentEvent4TimeText"), TEXT("Bir teklif cevap bekliyor."), TEXT("2 saat once") },
            { TEXT("DashboardRecentEvent5Frame"), TEXT("DashboardRecentEvent5Row"), TEXT("DashboardRecentEvent5MessageText"), TEXT("DashboardRecentEvent5TimeText"), TEXT("Yapi takibi sonraki fazda baglanacak."), TEXT("3 saat once") }
        };
        for (int32 EventIndex = 0; EventIndex < UE_ARRAY_COUNT(RecentEventSpecs); ++EventIndex)
        {
            const FRecentEventSpec& Spec = RecentEventSpecs[EventIndex];
            UBorder* EventFrame = Cast<UBorder>(Tree->FindWidget(FName(Spec.FrameName)));
            UHorizontalBox* EventRow = Cast<UHorizontalBox>(Tree->FindWidget(FName(Spec.RowName)));
            UTextBlock* EventMessage = Cast<UTextBlock>(Tree->FindWidget(FName(Spec.MessageName)));
            UTextBlock* EventTime = Cast<UTextBlock>(Tree->FindWidget(FName(Spec.TimeName)));
            if (!EventFrame && !EventRow && !EventMessage && !EventTime)
            {
                EventFrame = Tree->ConstructWidget<UBorder>(UBorder::StaticClass(), FName(Spec.FrameName));
                EventFrame->SetBrushColor(EventIndex % 2 == 0
                    ? FLinearColor(0.02f, 0.085f, 0.11f, 0.72f)
                    : FLinearColor(0.012f, 0.055f, 0.075f, 0.72f));
                EventFrame->SetPadding(FMargin(10.0f, 7.0f));
                EventRow = Tree->ConstructWidget<UHorizontalBox>(UHorizontalBox::StaticClass(), FName(Spec.RowName));
                EventFrame->SetContent(EventRow);
                EventMessage = MakeText(Tree, FName(Spec.MessageName), Spec.Message, 13);
                EventMessage->SetAutoWrapText(false);
                UHorizontalBoxSlot* MessageSlot = AddHorizontal(EventRow, EventMessage);
                MessageSlot->SetSize(FSlateChildSize(ESlateSizeRule::Fill));
                MessageSlot->SetVerticalAlignment(VAlign_Center);
                EventTime = MakeText(Tree, FName(Spec.TimeName), Spec.Time, 11);
                EventTime->SetColorAndOpacity(FSlateColor(FLinearColor(0.88f, 0.72f, 0.42f, 1.0f)));
                EventTime->SetJustification(ETextJustify::Right);
                UHorizontalBoxSlot* TimeSlot = AddHorizontal(EventRow, EventTime, FMargin(12.0f, 0, 0, 0));
                TimeSlot->SetVerticalAlignment(VAlign_Center);
                AddVertical(RecentContent, EventFrame, FMargin(0, 0, 0, EventIndex + 1 == UE_ARRAY_COUNT(RecentEventSpecs) ? 0.0f : 5.0f));
            }
            else if (!EventFrame || !EventRow || !EventMessage || !EventTime
                || EventFrame->GetContent() != EventRow
                || EventFrame->GetParent() != RecentContent
                || EventMessage->GetParent() != EventRow
                || EventTime->GetParent() != EventRow)
            {
                UE_LOG(LogTemp, Error, TEXT("PalTRUI art dashboard update refused: partial recent event row: %s"), Spec.FrameName);
                return false;
            }
            EventMessage->SetText(FText::FromString(Spec.Message));
            EventTime->SetText(FText::FromString(Spec.Time));
        }
        UVerticalBox* QuickActionsContent = Cast<UVerticalBox>(Tree->FindWidget(TEXT("DashboardQuickActionsContent")));
        UButton* ProtectionAction = Cast<UButton>(Tree->FindWidget(TEXT("DashboardProtectionButton")));
        UTextBlock* ProtectionActionText = Cast<UTextBlock>(Tree->FindWidget(TEXT("DashboardProtectionButtonText")));
        if (!ProtectionActionText && ProtectionAction)
        {
            ProtectionActionText = Cast<UTextBlock>(ProtectionAction->GetContent());
        }
        if (!ProtectionAction && !ProtectionActionText && QuickActionsContent)
        {
            ProtectionAction = MakeTabButton(Tree, TEXT("DashboardProtectionButton"), TEXT("DashboardProtectionButtonText"), TEXT("Koruma Durumu  |  YAKINDA"));
            ProtectionActionText = Cast<UTextBlock>(ProtectionAction->GetContent());
            UVerticalBoxSlot* ProtectionActionSlot = AddVertical(QuickActionsContent, ProtectionAction);
            ProtectionActionSlot->SetHorizontalAlignment(HAlign_Fill);
        }
        else if (!ProtectionAction || !ProtectionActionText || !QuickActionsContent
            || ProtectionAction->GetParent() != QuickActionsContent)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI art dashboard update refused: partial protection quick action."));
            return false;
        }
        ProtectionAction->SetIsEnabled(false);
        ProtectionActionText->SetText(FText::FromString(TEXT("Koruma Durumu  |  YAKINDA")));
        StyleButton(Tree, TEXT("DashboardProtectionButton"), FLinearColor(0.012f, 0.10f, 0.12f, 0.92f));

        if (UTextBlock* ClanHeading = Cast<UTextBlock>(Tree->FindWidget(TEXT("ClanHeadingText"))))
        {
            ClanHeading->SetText(FText::FromString(TEXT("KLAN DURUMU")));
        }
        if (UTextBlock* ClanSubtitle = Cast<UTextBlock>(Tree->FindWidget(TEXT("ClanSubtitleText"))))
        {
            ClanSubtitle->SetText(FText::FromString(TEXT("Klaninizin genel durumunu ve onemli bilgileri buradan takip edin.")));
        }
        if (UTextBlock* SidebarTitle = Cast<UTextBlock>(Tree->FindWidget(TEXT("DashboardSidebarTitleText"))))
        {
            SidebarTitle->SetText(FText::FromString(TEXT("ILISKILER")));
        }
        if (UTextBlock* RelationsHeading = Cast<UTextBlock>(Tree->FindWidget(TEXT("DashboardRelationsHeadingText"))))
        {
            RelationsHeading->SetVisibility(ESlateVisibility::Collapsed);
        }

        UTextBlock* ConnectionStatus = Cast<UTextBlock>(Tree->FindWidget(TEXT("ConnectionStatusText")));
        UBorder* HeaderServerFrame = Cast<UBorder>(Tree->FindWidget(TEXT("HeaderServerFrame")));
        UHorizontalBox* HeaderServerContent = Cast<UHorizontalBox>(Tree->FindWidget(TEXT("HeaderServerContent")));
        UTextBlock* HeaderServerDot = Cast<UTextBlock>(Tree->FindWidget(TEXT("HeaderServerDotText")));
        UBorder* HeaderGuildFrame = Cast<UBorder>(Tree->FindWidget(TEXT("HeaderGuildFrame")));
        if (!HeaderServerFrame && !HeaderServerContent && !HeaderServerDot)
        {
            if (!ConnectionStatus || ConnectionStatus->GetParent() != HeaderRow || !HeaderGuildFrame)
            {
                UE_LOG(LogTemp, Error, TEXT("PalTRUI art dashboard update failed: server badge source hierarchy."));
                return false;
            }
            const int32 GuildIndex = HeaderRow->GetChildIndex(HeaderGuildFrame);
            HeaderRow->RemoveChild(ConnectionStatus);
            HeaderServerFrame = Tree->ConstructWidget<UBorder>(UBorder::StaticClass(), TEXT("HeaderServerFrame"));
            HeaderServerContent = Tree->ConstructWidget<UHorizontalBox>(UHorizontalBox::StaticClass(), TEXT("HeaderServerContent"));
            HeaderServerFrame->SetContent(HeaderServerContent);
            HeaderServerDot = MakeText(Tree, TEXT("HeaderServerDotText"), TEXT("●"), 14);
            HeaderServerDot->SetColorAndOpacity(FSlateColor(FLinearColor(0.28f, 0.92f, 0.42f, 1.0f)));
            AddHorizontal(HeaderServerContent, HeaderServerDot, FMargin(0, 0, 7, 0));
            AddHorizontal(HeaderServerContent, ConnectionStatus);
            UHorizontalBoxSlot* ServerSlot = Cast<UHorizontalBoxSlot>(HeaderRow->InsertChildAt(GuildIndex, HeaderServerFrame));
            if (!ServerSlot)
            {
                UE_LOG(LogTemp, Error, TEXT("PalTRUI art dashboard update failed: server badge slot."));
                return false;
            }
            ServerSlot->SetPadding(FMargin(0, 0, 8, 0));
            ServerSlot->SetVerticalAlignment(VAlign_Center);
        }
        else if (!HeaderServerFrame || !HeaderServerContent || !HeaderServerDot || !ConnectionStatus
            || HeaderServerFrame->GetContent() != HeaderServerContent
            || HeaderServerFrame->GetParent() != HeaderRow
            || ConnectionStatus->GetParent() != HeaderServerContent)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI art dashboard update refused: partial server badge."));
            return false;
        }
        StyleRoundedFrame(Tree, TEXT("HeaderServerFrame"), FLinearColor(0.012f, 0.045f, 0.055f, 0.96f), FLinearColor(0.44f, 0.34f, 0.16f, 0.96f), 6.0f, 1.25f, FMargin(11.0f, 7.0f));

        struct FQuickVisualSpec
        {
            const TCHAR* ButtonName;
            const TCHAR* TextName;
            const TCHAR* ContentName;
            const TCHAR* IconSizeName;
            const TCHAR* IconName;
            const TCHAR* ArrowName;
            UTexture2D* Texture;
        };
        const FQuickVisualSpec QuickVisualSpecs[] = {
            { TEXT("DashboardDiplomacyButton"), TEXT("DashboardDiplomacyButtonText"), TEXT("DashboardDiplomacyButtonContent"), TEXT("DashboardDiplomacyButtonIconSize"), TEXT("DashboardDiplomacyButtonIcon"), TEXT("DashboardDiplomacyButtonArrowText"), DiplomacyIcon },
            { TEXT("DashboardOffersButton"), TEXT("DashboardOffersButtonText"), TEXT("DashboardOffersButtonContent"), TEXT("DashboardOffersButtonIconSize"), TEXT("DashboardOffersButtonIcon"), TEXT("DashboardOffersButtonArrowText"), DiplomacyIcon },
            { TEXT("DashboardGuildsButton"), TEXT("DashboardGuildsButtonText"), TEXT("DashboardGuildsButtonContent"), TEXT("DashboardGuildsButtonIconSize"), TEXT("DashboardGuildsButtonIcon"), TEXT("DashboardGuildsButtonArrowText"), ClanIcon },
            { TEXT("DashboardProtectionButton"), TEXT("DashboardProtectionButtonText"), TEXT("DashboardProtectionButtonContent"), TEXT("DashboardProtectionButtonIconSize"), TEXT("DashboardProtectionButtonIcon"), TEXT("DashboardProtectionButtonArrowText"), ProtectionIcon }
        };
        for (const FQuickVisualSpec& Spec : QuickVisualSpecs)
        {
            UButton* Button = Cast<UButton>(Tree->FindWidget(FName(Spec.ButtonName)));
            UTextBlock* Label = Cast<UTextBlock>(Tree->FindWidget(FName(Spec.TextName)));
            UHorizontalBox* ButtonContent = Cast<UHorizontalBox>(Tree->FindWidget(FName(Spec.ContentName)));
            USizeBox* IconSize = Cast<USizeBox>(Tree->FindWidget(FName(Spec.IconSizeName)));
            UImage* Icon = Cast<UImage>(Tree->FindWidget(FName(Spec.IconName)));
            UTextBlock* Arrow = Cast<UTextBlock>(Tree->FindWidget(FName(Spec.ArrowName)));
            if (!ButtonContent && !IconSize && !Icon && !Arrow)
            {
                if (!Button || !Label || Button->GetContent() != Label)
                {
                    UE_LOG(LogTemp, Error, TEXT("PalTRUI art dashboard update failed: quick action source: %s"), Spec.ButtonName);
                    return false;
                }
                Button->RemoveChild(Label);
                ButtonContent = Tree->ConstructWidget<UHorizontalBox>(UHorizontalBox::StaticClass(), FName(Spec.ContentName));
                IconSize = Tree->ConstructWidget<USizeBox>(USizeBox::StaticClass(), FName(Spec.IconSizeName));
                IconSize->SetWidthOverride(30.0f);
                IconSize->SetHeightOverride(30.0f);
                Icon = Tree->ConstructWidget<UImage>(UImage::StaticClass(), FName(Spec.IconName));
                IconSize->SetContent(Icon);
                AddHorizontal(ButtonContent, IconSize, FMargin(2, 0, 10, 0));
                UHorizontalBoxSlot* LabelSlot = AddHorizontal(ButtonContent, Label);
                LabelSlot->SetSize(FSlateChildSize(ESlateSizeRule::Fill));
                LabelSlot->SetVerticalAlignment(VAlign_Center);
                Label->SetJustification(ETextJustify::Left);
                Arrow = MakeText(Tree, FName(Spec.ArrowName), TEXT(">"), 19);
                Arrow->SetColorAndOpacity(FSlateColor(FLinearColor(0.92f, 0.72f, 0.34f, 1.0f)));
                AddHorizontal(ButtonContent, Arrow, FMargin(10, 0, 3, 0));
                Button->SetContent(ButtonContent);
            }
            else if (!Button || !Label || !ButtonContent || !IconSize || !Icon || !Arrow
                || Button->GetContent() != ButtonContent
                || IconSize->GetContent() != Icon
                || Label->GetParent() != ButtonContent)
            {
                UE_LOG(LogTemp, Error, TEXT("PalTRUI art dashboard update refused: partial quick action visual: %s"), Spec.ButtonName);
                return false;
            }
            Icon->SetBrushFromTexture(Spec.Texture, true);
            StyleTextShadow(Tree, FName(Spec.TextName));
            StyleTextShadow(Tree, FName(Spec.ArrowName));
        }

        UVerticalBox* RelationsContent = Cast<UVerticalBox>(Tree->FindWidget(TEXT("DashboardRelationsContent")));
        UTextBlock* LegacyRelationsText = Cast<UTextBlock>(Tree->FindWidget(TEXT("DashboardRelationsText")));
        if (!RelationsContent || !LegacyRelationsText)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI art dashboard update failed: relation card source."));
            return false;
        }
        LegacyRelationsText->SetVisibility(ESlateVisibility::Collapsed);
        for (int32 RelationIndex = 1; RelationIndex <= 3; ++RelationIndex)
        {
            const FName FrameName(*FString::Printf(TEXT("DashboardRelationRow%dFrame"), RelationIndex));
            const FName ContentName(*FString::Printf(TEXT("DashboardRelationRow%dContent"), RelationIndex));
            const FName IconSizeName(*FString::Printf(TEXT("DashboardRelationRow%dIconSize"), RelationIndex));
            const FName IconName(*FString::Printf(TEXT("DashboardRelationRow%dIcon"), RelationIndex));
            const FName NameTextName(*FString::Printf(TEXT("DashboardRelationRow%dNameText"), RelationIndex));
            const FName BadgeFrameName(*FString::Printf(TEXT("DashboardRelationRow%dBadgeFrame"), RelationIndex));
            const FName StateTextName(*FString::Printf(TEXT("DashboardRelationRow%dStateText"), RelationIndex));
            UBorder* RowFrame = Cast<UBorder>(Tree->FindWidget(FrameName));
            UHorizontalBox* RowContent = Cast<UHorizontalBox>(Tree->FindWidget(ContentName));
            if (!RowFrame && !RowContent)
            {
                RowFrame = Tree->ConstructWidget<UBorder>(UBorder::StaticClass(), FrameName);
                RowContent = Tree->ConstructWidget<UHorizontalBox>(UHorizontalBox::StaticClass(), ContentName);
                RowFrame->SetContent(RowContent);
                USizeBox* RelationIconSize = Tree->ConstructWidget<USizeBox>(USizeBox::StaticClass(), IconSizeName);
                RelationIconSize->SetWidthOverride(52.0f);
                RelationIconSize->SetHeightOverride(52.0f);
                UImage* RelationIcon = Tree->ConstructWidget<UImage>(UImage::StaticClass(), IconName);
                RelationIcon->SetBrushFromTexture(ClanIcon, true);
                RelationIconSize->SetContent(RelationIcon);
                AddHorizontal(RowContent, RelationIconSize, FMargin(0, 0, 10, 0));
                UTextBlock* RelationName = MakeText(Tree, NameTextName, TEXT("-"), 16);
                UHorizontalBoxSlot* RelationNameSlot = AddHorizontal(RowContent, RelationName);
                RelationNameSlot->SetSize(FSlateChildSize(ESlateSizeRule::Fill));
                UBorder* BadgeFrame = Tree->ConstructWidget<UBorder>(UBorder::StaticClass(), BadgeFrameName);
                UTextBlock* StateText = MakeText(Tree, StateTextName, TEXT(""), 12);
                StateText->SetJustification(ETextJustify::Center);
                BadgeFrame->SetContent(StateText);
                AddHorizontal(RowContent, BadgeFrame, FMargin(8, 0, 0, 0));
                AddVertical(RelationsContent, RowFrame, FMargin(0, 0, 0, RelationIndex < 3 ? 7.0f : 0.0f));
            }
            else if (!RowFrame || !RowContent || RowFrame->GetContent() != RowContent
                || RowFrame->GetParent() != RelationsContent)
            {
                UE_LOG(LogTemp, Error, TEXT("PalTRUI art dashboard update refused: partial relation row: %d"), RelationIndex);
                return false;
            }
            StyleRoundedFrame(Tree, FrameName, FLinearColor(0.018f, 0.024f, 0.026f, 0.92f), FLinearColor(0.28f, 0.24f, 0.16f, 0.92f), 6.0f, 1.0f, FMargin(10.0f, 8.0f));
            const FLinearColor BadgeFill = RelationIndex == 1
                ? FLinearColor(0.11f, 0.11f, 0.10f, 0.96f)
                : (RelationIndex == 2
                    ? FLinearColor(0.10f, 0.22f, 0.13f, 0.96f)
                    : FLinearColor(0.20f, 0.075f, 0.05f, 0.96f));
            const FLinearColor BadgeEdge = RelationIndex == 1
                ? FLinearColor(0.34f, 0.32f, 0.28f, 0.96f)
                : (RelationIndex == 2
                    ? FLinearColor(0.24f, 0.62f, 0.36f, 0.96f)
                    : FLinearColor(0.66f, 0.22f, 0.16f, 0.96f));
            StyleRoundedFrame(Tree, BadgeFrameName, BadgeFill, BadgeEdge, 5.0f, 1.0f, FMargin(12.0f, 5.0f));
            StyleTextShadow(Tree, NameTextName);
            StyleTextShadow(Tree, StateTextName);
        }

        UVerticalBox* PendingContent = Cast<UVerticalBox>(Tree->FindWidget(TEXT("PendingOffersContent")));
        UTextBlock* PendingHeading = Cast<UTextBlock>(Tree->FindWidget(TEXT("PendingOffersHeadingText")));
        UTextBlock* LegacyPendingText = Cast<UTextBlock>(Tree->FindWidget(TEXT("PendingOffersText")));
        UBorder* PendingTitleFrame = Cast<UBorder>(Tree->FindWidget(TEXT("PendingOffersTitleFrame")));
        UBorder* PendingCardFrame = Cast<UBorder>(Tree->FindWidget(TEXT("DashboardPendingCardFrame")));
        UVerticalBox* PendingCardContent = Cast<UVerticalBox>(Tree->FindWidget(TEXT("DashboardPendingCardContent")));
        if (!PendingContent || !PendingHeading || !LegacyPendingText)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI art dashboard update failed: pending card source."));
            return false;
        }
        if (!PendingTitleFrame)
        {
            if (PendingHeading->GetParent() != PendingContent)
            {
                UE_LOG(LogTemp, Error, TEXT("PalTRUI art dashboard update failed: pending heading parent."));
                return false;
            }
            PendingContent->RemoveChild(PendingHeading);
            PendingTitleFrame = Tree->ConstructWidget<UBorder>(UBorder::StaticClass(), TEXT("PendingOffersTitleFrame"));
            PendingTitleFrame->SetContent(PendingHeading);
            PendingContent->InsertChildAt(0, PendingTitleFrame);
        }
        LegacyPendingText->SetVisibility(ESlateVisibility::Collapsed);
        if (!PendingCardFrame && !PendingCardContent)
        {
            PendingCardFrame = Tree->ConstructWidget<UBorder>(UBorder::StaticClass(), TEXT("DashboardPendingCardFrame"));
            PendingCardContent = Tree->ConstructWidget<UVerticalBox>(UVerticalBox::StaticClass(), TEXT("DashboardPendingCardContent"));
            PendingCardFrame->SetContent(PendingCardContent);
            UHorizontalBox* PendingIdentity = Tree->ConstructWidget<UHorizontalBox>(UHorizontalBox::StaticClass(), TEXT("DashboardPendingIdentity"));
            USizeBox* PendingIconSize = Tree->ConstructWidget<USizeBox>(USizeBox::StaticClass(), TEXT("DashboardPendingIconSize"));
            PendingIconSize->SetWidthOverride(58.0f);
            PendingIconSize->SetHeightOverride(58.0f);
            UImage* PendingIcon = Tree->ConstructWidget<UImage>(UImage::StaticClass(), TEXT("DashboardPendingIcon"));
            PendingIcon->SetBrushFromTexture(ClanIcon, true);
            PendingIconSize->SetContent(PendingIcon);
            AddHorizontal(PendingIdentity, PendingIconSize, FMargin(0, 0, 12, 0));
            UVerticalBox* PendingCopy = Tree->ConstructWidget<UVerticalBox>(UVerticalBox::StaticClass(), TEXT("DashboardPendingCopy"));
            AddVertical(PendingCopy, MakeText(Tree, TEXT("DashboardPendingGuildText"), TEXT("Bekleyen teklif yok."), 17), FMargin(0, 0, 0, 5));
            AddVertical(PendingCopy, MakeText(Tree, TEXT("DashboardPendingStateText"), TEXT(""), 13));
            UHorizontalBoxSlot* PendingCopySlot = AddHorizontal(PendingIdentity, PendingCopy);
            PendingCopySlot->SetSize(FSlateChildSize(ESlateSizeRule::Fill));
            AddVertical(PendingCardContent, PendingIdentity, FMargin(0, 0, 0, 12));
            UHorizontalBox* PendingActions = Tree->ConstructWidget<UHorizontalBox>(UHorizontalBox::StaticClass(), TEXT("DashboardPendingActions"));
            UButton* PendingAccept = MakeTabButton(Tree, TEXT("DashboardPendingAcceptButton"), TEXT("DashboardPendingAcceptButtonText"), TEXT("Kabul"));
            UHorizontalBoxSlot* PendingAcceptSlot = AddHorizontal(PendingActions, PendingAccept, FMargin(0, 0, 6, 0));
            PendingAcceptSlot->SetSize(FSlateChildSize(ESlateSizeRule::Fill));
            UButton* PendingReject = MakeTabButton(Tree, TEXT("DashboardPendingRejectButton"), TEXT("DashboardPendingRejectButtonText"), TEXT("Reddet"));
            UHorizontalBoxSlot* PendingRejectSlot = AddHorizontal(PendingActions, PendingReject, FMargin(6, 0, 0, 0));
            PendingRejectSlot->SetSize(FSlateChildSize(ESlateSizeRule::Fill));
            AddVertical(PendingCardContent, PendingActions);
            AddVertical(PendingContent, PendingCardFrame, FMargin(0, 10, 0, 0));
        }
        else if (!PendingCardFrame || !PendingCardContent
            || PendingCardFrame->GetContent() != PendingCardContent
            || PendingCardFrame->GetParent() != PendingContent)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI art dashboard update refused: partial pending card."));
            return false;
        }
        StyleRoundedFrame(Tree, TEXT("PendingOffersTitleFrame"), FLinearColor(0.72f, 0.54f, 0.30f, 0.98f), FLinearColor(0.88f, 0.70f, 0.38f, 1.0f), 5.0f, 1.5f, FMargin(12.0f, 8.0f));
        PendingHeading->SetColorAndOpacity(FSlateColor(FLinearColor(0.12f, 0.085f, 0.035f, 1.0f)));
        StyleRoundedFrame(Tree, TEXT("DashboardPendingCardFrame"), FLinearColor(0.018f, 0.024f, 0.026f, 0.94f), FLinearColor(0.32f, 0.26f, 0.15f, 0.96f), 7.0f, 1.25f, FMargin(12.0f));
        StyleButton(Tree, TEXT("DashboardPendingAcceptButton"), FLinearColor(0.035f, 0.26f, 0.12f, 0.98f));
        StyleButton(Tree, TEXT("DashboardPendingRejectButton"), FLinearColor(0.34f, 0.055f, 0.04f, 0.98f));
        StyleTextShadow(Tree, TEXT("DashboardPendingGuildText"));
        StyleTextShadow(Tree, TEXT("DashboardPendingStateText"));
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
        StyleRoundedFrame(Tree, TEXT("DashboardSidebarTitleFrame"), FLinearColor(0.72f, 0.54f, 0.30f, 0.98f), FLinearColor(0.90f, 0.72f, 0.40f, 1.0f), 6.0f, 1.5f, FMargin(12.0f, 8.0f));
        if (UTextBlock* SidebarTitleText = Cast<UTextBlock>(Tree->FindWidget(TEXT("DashboardSidebarTitleText"))))
        {
            SidebarTitleText->SetColorAndOpacity(FSlateColor(FLinearColor(0.12f, 0.085f, 0.035f, 1.0f)));
        }
        StyleRoundedFrame(Tree, TEXT("HeaderGuildFrame"), FLinearColor(0.015f, 0.15f, 0.17f, 0.98f), FLinearColor(0.12f, 0.48f, 0.52f, 0.96f), 6.0f, 1.25f, FMargin(10.0f, 7.0f));
        StyleRoundedFrame(Tree, TEXT("HeaderRoleFrame"), FLinearColor(0.24f, 0.16f, 0.045f, 0.98f), GoldEdge, 6.0f, 1.25f, FMargin(10.0f, 7.0f));
        StyleRoundedFrame(Tree, TEXT("HeaderNotificationFrame"), FLinearColor(0.32f, 0.055f, 0.04f, 0.98f), FLinearColor(0.68f, 0.22f, 0.14f, 0.98f), 6.0f, 1.25f, FMargin(10.0f, 7.0f));
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
        for (const FName ShadowText : {
            FName(TEXT("TitleText")),
            FName(TEXT("ClanHeadingText")),
            FName(TEXT("ClanSubtitleText")),
            FName(TEXT("DashboardClanCardTitleText")),
            FName(TEXT("DashboardClanCardValueText")),
            FName(TEXT("DashboardClanCardDetailText")),
            FName(TEXT("DashboardDiplomacyCardTitleText")),
            FName(TEXT("DashboardDiplomacyCardValueText")),
            FName(TEXT("DashboardProtectionCardTitleText")),
            FName(TEXT("DashboardProtectionCardValueText")),
            FName(TEXT("DashboardBuildingsCardTitleText")),
            FName(TEXT("DashboardBuildingsCardValueText")),
            FName(TEXT("DashboardRecentEventsHeadingText")),
            FName(TEXT("DashboardQuickActionsHeadingText")),
            FName(TEXT("HeaderGuildText")),
            FName(TEXT("HeaderRoleText")),
            FName(TEXT("HeaderNotificationText")),
            FName(TEXT("ConnectionStatusText")),
            FName(TEXT("FooterHintText"))
        })
        {
            StyleTextShadow(Tree, ShadowText);
        }
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

    bool UpdateReferenceSecondaryPages()
    {
        UWidgetBlueprint* Panel = LoadObject<UWidgetBlueprint>(
            nullptr,
            TEXT("/Game/Mods/PalTRUI/WBP_PalTRPanel.WBP_PalTRPanel")
        );
        if (!Panel || !Panel->WidgetTree)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI secondary reference update failed: panel asset missing."));
            return false;
        }

        UWidgetTree* Tree = Panel->WidgetTree;
        UVerticalBox* DiplomacyPage = Cast<UVerticalBox>(Tree->FindWidget(TEXT("DiplomacyPage")));
        UHorizontalBox* DiplomacyColumns = Cast<UHorizontalBox>(Tree->FindWidget(TEXT("DiplomacyColumns")));
        UBorder* DiplomacyListFrame = Cast<UBorder>(Tree->FindWidget(TEXT("DiplomacyListFrame")));
        UBorder* DiplomacyDetailFrame = Cast<UBorder>(Tree->FindWidget(TEXT("DiplomacyDetailFrame")));
        USizeBox* RelationListSize = Cast<USizeBox>(Tree->FindWidget(TEXT("RelationListSize")));
        UVerticalBox* RelationDetail = Cast<UVerticalBox>(Tree->FindWidget(TEXT("RelationDetail")));
        UHorizontalBox* RelationActions = Cast<UHorizontalBox>(Tree->FindWidget(TEXT("RelationActions")));
        UVerticalBox* AlliancePage = Cast<UVerticalBox>(Tree->FindWidget(TEXT("AlliancePage")));
        UTextBlock* AllianceSummary = Cast<UTextBlock>(Tree->FindWidget(TEXT("AllianceSummaryText")));
        UBorder* AllianceDetailFrame = Cast<UBorder>(Tree->FindWidget(TEXT("AllianceDetailFrame")));
        UTextBlock* AllianceMembers = Cast<UTextBlock>(Tree->FindWidget(TEXT("AllianceMembersText")));
        UVerticalBox* GuildPage = Cast<UVerticalBox>(Tree->FindWidget(TEXT("ChatPage")));
        UHorizontalBox* GuildColumns = Cast<UHorizontalBox>(Tree->FindWidget(TEXT("GuildCatalogColumns")));
        UBorder* GuildActiveFrame = Cast<UBorder>(Tree->FindWidget(TEXT("GuildCatalogActiveFrame")));
        UVerticalBox* GuildActiveContent = Cast<UVerticalBox>(Tree->FindWidget(TEXT("GuildCatalogActiveContent")));
        UTextBlock* GuildActiveHeading = Cast<UTextBlock>(Tree->FindWidget(TEXT("GuildCatalogActiveHeadingText")));
        UBorder* GuildRegisteredFrame = Cast<UBorder>(Tree->FindWidget(TEXT("GuildCatalogRegisteredFrame")));
        UVerticalBox* GuildRegisteredContent = Cast<UVerticalBox>(Tree->FindWidget(TEXT("GuildCatalogRegisteredContent")));
        UTextBlock* GuildRegisteredHeading = Cast<UTextBlock>(Tree->FindWidget(TEXT("GuildCatalogRegisteredHeadingText")));
        if (!DiplomacyPage || !DiplomacyColumns || !DiplomacyListFrame || !DiplomacyDetailFrame
            || !RelationListSize || !RelationDetail || !RelationActions || !AlliancePage
            || !AllianceSummary || !AllianceDetailFrame || !AllianceMembers || !GuildPage
            || !GuildColumns || !GuildActiveFrame || !GuildActiveContent || !GuildActiveHeading
            || !GuildRegisteredFrame || !GuildRegisteredContent || !GuildRegisteredHeading)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI secondary reference update failed: required hierarchy missing."));
            return false;
        }

        Panel->Modify();
        Tree->Modify();

        UVerticalBox* DiplomacyListContent = Cast<UVerticalBox>(Tree->FindWidget(TEXT("ReferenceDiplomacyListContent")));
        UBorder* DiplomacyListTitleFrame = Cast<UBorder>(Tree->FindWidget(TEXT("ReferenceDiplomacyListTitleFrame")));
        UTextBlock* DiplomacyListTitleText = Cast<UTextBlock>(Tree->FindWidget(TEXT("ReferenceDiplomacyListTitleText")));
        UVerticalBox* DiplomacyDetailContent = Cast<UVerticalBox>(Tree->FindWidget(TEXT("ReferenceDiplomacyDetailContent")));
        UBorder* DiplomacyDetailTitleFrame = Cast<UBorder>(Tree->FindWidget(TEXT("ReferenceDiplomacyDetailTitleFrame")));
        UTextBlock* DiplomacyDetailTitleText = Cast<UTextBlock>(Tree->FindWidget(TEXT("ReferenceDiplomacyDetailTitleText")));
        if (!DiplomacyListContent && !DiplomacyListTitleFrame && !DiplomacyListTitleText
            && !DiplomacyDetailContent && !DiplomacyDetailTitleFrame && !DiplomacyDetailTitleText)
        {
            if (DiplomacyListFrame->GetContent() != RelationListSize
                || DiplomacyDetailFrame->GetContent() != RelationDetail)
            {
                UE_LOG(LogTemp, Error, TEXT("PalTRUI secondary reference update refused: diplomacy source changed."));
                return false;
            }
            DiplomacyListFrame->RemoveChild(RelationListSize);
            DiplomacyListContent = Tree->ConstructWidget<UVerticalBox>(UVerticalBox::StaticClass(), TEXT("ReferenceDiplomacyListContent"));
            DiplomacyListTitleFrame = Tree->ConstructWidget<UBorder>(UBorder::StaticClass(), TEXT("ReferenceDiplomacyListTitleFrame"));
            DiplomacyListTitleText = MakeText(Tree, TEXT("ReferenceDiplomacyListTitleText"), TEXT("KLANLAR"), 18);
            DiplomacyListTitleFrame->SetContent(DiplomacyListTitleText);
            AddVertical(DiplomacyListContent, DiplomacyListTitleFrame, FMargin(0, 0, 0, 10));
            UVerticalBoxSlot* RelationListSlot = AddVertical(DiplomacyListContent, RelationListSize);
            RelationListSlot->SetSize(FSlateChildSize(ESlateSizeRule::Fill));
            DiplomacyListFrame->SetContent(DiplomacyListContent);

            DiplomacyDetailFrame->RemoveChild(RelationDetail);
            DiplomacyDetailContent = Tree->ConstructWidget<UVerticalBox>(UVerticalBox::StaticClass(), TEXT("ReferenceDiplomacyDetailContent"));
            DiplomacyDetailTitleFrame = Tree->ConstructWidget<UBorder>(UBorder::StaticClass(), TEXT("ReferenceDiplomacyDetailTitleFrame"));
            DiplomacyDetailTitleText = MakeText(Tree, TEXT("ReferenceDiplomacyDetailTitleText"), TEXT("ILISKI DETAYI"), 18);
            DiplomacyDetailTitleFrame->SetContent(DiplomacyDetailTitleText);
            AddVertical(DiplomacyDetailContent, DiplomacyDetailTitleFrame, FMargin(0, 0, 0, 12));
            UVerticalBoxSlot* RelationDetailSlot = AddVertical(DiplomacyDetailContent, RelationDetail);
            RelationDetailSlot->SetSize(FSlateChildSize(ESlateSizeRule::Fill));
            DiplomacyDetailFrame->SetContent(DiplomacyDetailContent);
        }
        else if (!DiplomacyListContent || !DiplomacyListTitleFrame || !DiplomacyListTitleText
            || !DiplomacyDetailContent || !DiplomacyDetailTitleFrame || !DiplomacyDetailTitleText
            || DiplomacyListFrame->GetContent() != DiplomacyListContent
            || DiplomacyDetailFrame->GetContent() != DiplomacyDetailContent
            || RelationListSize->GetParent() != DiplomacyListContent
            || RelationDetail->GetParent() != DiplomacyDetailContent)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI secondary reference update refused: partial diplomacy layout."));
            return false;
        }
        RelationListSize->SetWidthOverride(380.0f);
        StyleRoundedFrame(Tree, TEXT("DiplomacyListFrame"), FLinearColor(0.008f, 0.035f, 0.050f, 0.96f), FLinearColor(0.62f, 0.45f, 0.18f, 0.96f), 9.0f, 1.5f, FMargin(14.0f));
        StyleRoundedFrame(Tree, TEXT("DiplomacyDetailFrame"), FLinearColor(0.012f, 0.055f, 0.075f, 0.96f), FLinearColor(0.62f, 0.45f, 0.18f, 0.96f), 9.0f, 1.5f, FMargin(14.0f));
        StyleRoundedFrame(Tree, TEXT("ReferenceDiplomacyListTitleFrame"), FLinearColor(0.70f, 0.52f, 0.29f, 0.98f), FLinearColor(0.91f, 0.74f, 0.42f, 1.0f), 5.0f, 1.5f, FMargin(12.0f, 8.0f));
        StyleRoundedFrame(Tree, TEXT("ReferenceDiplomacyDetailTitleFrame"), FLinearColor(0.70f, 0.52f, 0.29f, 0.98f), FLinearColor(0.91f, 0.74f, 0.42f, 1.0f), 5.0f, 1.5f, FMargin(12.0f, 8.0f));
        DiplomacyListTitleText->SetColorAndOpacity(FSlateColor(FLinearColor(0.11f, 0.075f, 0.025f, 1.0f)));
        DiplomacyDetailTitleText->SetColorAndOpacity(FSlateColor(FLinearColor(0.11f, 0.075f, 0.025f, 1.0f)));
        for (int32 ActionIndex = 0; ActionIndex < RelationActions->GetChildrenCount(); ++ActionIndex)
        {
            if (UHorizontalBoxSlot* ActionSlot = Cast<UHorizontalBoxSlot>(RelationActions->GetChildAt(ActionIndex)->Slot))
            {
                ActionSlot->SetSize(FSlateChildSize(ESlateSizeRule::Fill));
                ActionSlot->SetPadding(FMargin(ActionIndex == 0 ? 0.0f : 4.0f, 0, ActionIndex + 1 == RelationActions->GetChildrenCount() ? 0.0f : 4.0f, 0));
            }
        }
        StyleButton(Tree, TEXT("AllianceRequestButton"), FLinearColor(0.025f, 0.28f, 0.32f, 0.98f));
        StyleButton(Tree, TEXT("WarRequestButton"), FLinearColor(0.36f, 0.055f, 0.04f, 0.98f));
        StyleButton(Tree, TEXT("AcceptButton"), FLinearColor(0.035f, 0.26f, 0.12f, 0.98f));
        StyleButton(Tree, TEXT("RejectButton"), FLinearColor(0.34f, 0.055f, 0.04f, 0.98f));
        StyleButton(Tree, TEXT("CancelButton"), FLinearColor(0.28f, 0.21f, 0.08f, 0.98f));

        USizeBox* AllianceColumnsSize = Cast<USizeBox>(Tree->FindWidget(TEXT("ReferenceAllianceColumnsSize")));
        UHorizontalBox* AllianceColumns = Cast<UHorizontalBox>(Tree->FindWidget(TEXT("ReferenceAllianceColumns")));
        UBorder* AllianceSummaryFrame = Cast<UBorder>(Tree->FindWidget(TEXT("ReferenceAllianceSummaryFrame")));
        UVerticalBox* AllianceSummaryContent = Cast<UVerticalBox>(Tree->FindWidget(TEXT("ReferenceAllianceSummaryContent")));
        UBorder* AllianceMembersFrame = Cast<UBorder>(Tree->FindWidget(TEXT("ReferenceAllianceMembersFrame")));
        UVerticalBox* AllianceMembersContent = Cast<UVerticalBox>(Tree->FindWidget(TEXT("ReferenceAllianceMembersContent")));
        if (!AllianceColumnsSize && !AllianceColumns && !AllianceSummaryFrame && !AllianceSummaryContent
            && !AllianceMembersFrame && !AllianceMembersContent)
        {
            if (AllianceSummary->GetParent() != AlliancePage || AllianceDetailFrame->GetParent() != AlliancePage
                || AllianceMembers->GetParent() != AlliancePage)
            {
                UE_LOG(LogTemp, Error, TEXT("PalTRUI secondary reference update refused: alliance source changed."));
                return false;
            }
            const int32 AllianceInsertIndex = FMath::Min(
                AlliancePage->GetChildIndex(AllianceSummary),
                AlliancePage->GetChildIndex(AllianceDetailFrame)
            );
            AlliancePage->RemoveChild(AllianceSummary);
            AlliancePage->RemoveChild(AllianceDetailFrame);
            AlliancePage->RemoveChild(AllianceMembers);
            AllianceColumnsSize = Tree->ConstructWidget<USizeBox>(USizeBox::StaticClass(), TEXT("ReferenceAllianceColumnsSize"));
            AllianceColumnsSize->SetHeightOverride(620.0f);
            AllianceColumns = Tree->ConstructWidget<UHorizontalBox>(UHorizontalBox::StaticClass(), TEXT("ReferenceAllianceColumns"));
            AllianceColumnsSize->SetContent(AllianceColumns);
            AllianceSummaryFrame = Tree->ConstructWidget<UBorder>(UBorder::StaticClass(), TEXT("ReferenceAllianceSummaryFrame"));
            AllianceSummaryContent = Tree->ConstructWidget<UVerticalBox>(UVerticalBox::StaticClass(), TEXT("ReferenceAllianceSummaryContent"));
            AllianceSummaryFrame->SetContent(AllianceSummaryContent);
            AddVertical(AllianceSummaryContent, MakeText(Tree, TEXT("ReferenceAllianceSummaryTitleText"), TEXT("ITTIFAK OZETI"), 18), FMargin(0, 0, 0, 14));
            AddVertical(AllianceSummaryContent, AllianceSummary);
            UHorizontalBoxSlot* SummarySlot = AddHorizontal(AllianceColumns, AllianceSummaryFrame, FMargin(0, 0, 8, 0));
            SummarySlot->SetSize(FSlateChildSize(ESlateSizeRule::Fill));
            SummarySlot->SetVerticalAlignment(VAlign_Fill);
            UHorizontalBoxSlot* DetailSlot = AddHorizontal(AllianceColumns, AllianceDetailFrame, FMargin(8, 0, 8, 0));
            DetailSlot->SetSize(FSlateChildSize(ESlateSizeRule::Fill));
            DetailSlot->SetVerticalAlignment(VAlign_Fill);
            AllianceMembersFrame = Tree->ConstructWidget<UBorder>(UBorder::StaticClass(), TEXT("ReferenceAllianceMembersFrame"));
            AllianceMembersContent = Tree->ConstructWidget<UVerticalBox>(UVerticalBox::StaticClass(), TEXT("ReferenceAllianceMembersContent"));
            AllianceMembersFrame->SetContent(AllianceMembersContent);
            AddVertical(AllianceMembersContent, MakeText(Tree, TEXT("ReferenceAllianceMembersTitleText"), TEXT("UYE KLANLAR"), 18), FMargin(0, 0, 0, 14));
            AddVertical(AllianceMembersContent, AllianceMembers);
            UHorizontalBoxSlot* MembersSlot = AddHorizontal(AllianceColumns, AllianceMembersFrame, FMargin(8, 0, 0, 0));
            MembersSlot->SetSize(FSlateChildSize(ESlateSizeRule::Fill));
            MembersSlot->SetVerticalAlignment(VAlign_Fill);
            UVerticalBoxSlot* AllianceColumnsSlot = Cast<UVerticalBoxSlot>(AlliancePage->InsertChildAt(AllianceInsertIndex, AllianceColumnsSize));
            if (!AllianceColumnsSlot)
            {
                UE_LOG(LogTemp, Error, TEXT("PalTRUI secondary reference update failed: alliance columns slot."));
                return false;
            }
            AllianceColumnsSlot->SetHorizontalAlignment(HAlign_Fill);
        }
        else if (!AllianceColumnsSize || !AllianceColumns || !AllianceSummaryFrame || !AllianceSummaryContent
            || !AllianceMembersFrame || !AllianceMembersContent
            || AllianceColumnsSize->GetContent() != AllianceColumns
            || AllianceColumnsSize->GetParent() != AlliancePage
            || AllianceSummaryFrame->GetParent() != AllianceColumns
            || AllianceDetailFrame->GetParent() != AllianceColumns
            || AllianceMembersFrame->GetParent() != AllianceColumns)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI secondary reference update refused: partial alliance layout."));
            return false;
        }
        StyleRoundedFrame(Tree, TEXT("ReferenceAllianceSummaryFrame"), FLinearColor(0.02f, 0.16f, 0.17f, 0.94f), FLinearColor(0.15f, 0.68f, 0.70f, 0.95f), 9.0f, 1.5f, FMargin(18.0f));
        StyleRoundedFrame(Tree, TEXT("AllianceDetailFrame"), FLinearColor(0.015f, 0.075f, 0.105f, 0.96f), FLinearColor(0.62f, 0.45f, 0.18f, 0.96f), 9.0f, 1.5f, FMargin(18.0f));
        StyleRoundedFrame(Tree, TEXT("ReferenceAllianceMembersFrame"), FLinearColor(0.055f, 0.04f, 0.015f, 0.94f), FLinearColor(0.62f, 0.45f, 0.18f, 0.96f), 9.0f, 1.5f, FMargin(18.0f));

        UBorder* GuildActiveTitleFrame = Cast<UBorder>(Tree->FindWidget(TEXT("ReferenceGuildActiveTitleFrame")));
        UBorder* GuildRegisteredTitleFrame = Cast<UBorder>(Tree->FindWidget(TEXT("ReferenceGuildRegisteredTitleFrame")));
        UBorder* GuildInfoFrame = Cast<UBorder>(Tree->FindWidget(TEXT("ReferenceGuildInfoFrame")));
        UVerticalBox* GuildInfoContent = Cast<UVerticalBox>(Tree->FindWidget(TEXT("ReferenceGuildInfoContent")));
        if (!GuildActiveTitleFrame && !GuildRegisteredTitleFrame && !GuildInfoFrame && !GuildInfoContent)
        {
            if (GuildActiveHeading->GetParent() != GuildActiveContent
                || GuildRegisteredHeading->GetParent() != GuildRegisteredContent)
            {
                UE_LOG(LogTemp, Error, TEXT("PalTRUI secondary reference update refused: guild source changed."));
                return false;
            }
            GuildActiveContent->RemoveChild(GuildActiveHeading);
            GuildActiveTitleFrame = Tree->ConstructWidget<UBorder>(UBorder::StaticClass(), TEXT("ReferenceGuildActiveTitleFrame"));
            GuildActiveTitleFrame->SetContent(GuildActiveHeading);
            GuildActiveContent->InsertChildAt(0, GuildActiveTitleFrame);
            GuildRegisteredContent->RemoveChild(GuildRegisteredHeading);
            GuildRegisteredTitleFrame = Tree->ConstructWidget<UBorder>(UBorder::StaticClass(), TEXT("ReferenceGuildRegisteredTitleFrame"));
            GuildRegisteredTitleFrame->SetContent(GuildRegisteredHeading);
            GuildRegisteredContent->InsertChildAt(0, GuildRegisteredTitleFrame);
            GuildInfoFrame = Tree->ConstructWidget<UBorder>(UBorder::StaticClass(), TEXT("ReferenceGuildInfoFrame"));
            GuildInfoContent = Tree->ConstructWidget<UVerticalBox>(UVerticalBox::StaticClass(), TEXT("ReferenceGuildInfoContent"));
            GuildInfoFrame->SetContent(GuildInfoContent);
            AddVertical(GuildInfoContent, MakeText(Tree, TEXT("ReferenceGuildInfoTitleText"), TEXT("KLAN REHBERI"), 18), FMargin(0, 0, 0, 14));
            UTextBlock* GuildInfoText = MakeText(Tree, TEXT("ReferenceGuildInfoText"), TEXT("Sunucudaki aktif ve kayitli klanlari inceleyin.\n\nDiplomasi islemi icin bir klani Diplomasi ekranindan secin."), 15);
            GuildInfoText->SetAutoWrapText(true);
            AddVertical(GuildInfoContent, GuildInfoText);
            UHorizontalBoxSlot* GuildInfoSlot = AddHorizontal(GuildColumns, GuildInfoFrame, FMargin(8, 0, 0, 0));
            GuildInfoSlot->SetSize(FSlateChildSize(ESlateSizeRule::Fill));
            GuildInfoSlot->SetVerticalAlignment(VAlign_Fill);
        }
        else if (!GuildActiveTitleFrame || !GuildRegisteredTitleFrame || !GuildInfoFrame || !GuildInfoContent
            || GuildActiveTitleFrame->GetContent() != GuildActiveHeading
            || GuildRegisteredTitleFrame->GetContent() != GuildRegisteredHeading
            || GuildInfoFrame->GetContent() != GuildInfoContent
            || GuildInfoFrame->GetParent() != GuildColumns)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI secondary reference update refused: partial guild layout."));
            return false;
        }
        for (int32 GuildColumnIndex = 0; GuildColumnIndex < GuildColumns->GetChildrenCount(); ++GuildColumnIndex)
        {
            if (UHorizontalBoxSlot* GuildColumnSlot = Cast<UHorizontalBoxSlot>(GuildColumns->GetChildAt(GuildColumnIndex)->Slot))
            {
                GuildColumnSlot->SetSize(FSlateChildSize(ESlateSizeRule::Fill));
                GuildColumnSlot->SetVerticalAlignment(VAlign_Fill);
                GuildColumnSlot->SetPadding(FMargin(GuildColumnIndex == 0 ? 0.0f : 8.0f, 0, GuildColumnIndex + 1 == GuildColumns->GetChildrenCount() ? 0.0f : 8.0f, 0));
            }
        }
        StyleRoundedFrame(Tree, TEXT("GuildCatalogActiveFrame"), FLinearColor(0.015f, 0.15f, 0.16f, 0.95f), FLinearColor(0.15f, 0.68f, 0.70f, 0.95f), 9.0f, 1.5f, FMargin(14.0f));
        StyleRoundedFrame(Tree, TEXT("GuildCatalogRegisteredFrame"), FLinearColor(0.012f, 0.055f, 0.075f, 0.96f), FLinearColor(0.62f, 0.45f, 0.18f, 0.96f), 9.0f, 1.5f, FMargin(14.0f));
        StyleRoundedFrame(Tree, TEXT("ReferenceGuildInfoFrame"), FLinearColor(0.055f, 0.04f, 0.015f, 0.94f), FLinearColor(0.62f, 0.45f, 0.18f, 0.96f), 9.0f, 1.5f, FMargin(16.0f));
        StyleRoundedFrame(Tree, TEXT("ReferenceGuildActiveTitleFrame"), FLinearColor(0.70f, 0.52f, 0.29f, 0.98f), FLinearColor(0.91f, 0.74f, 0.42f, 1.0f), 5.0f, 1.5f, FMargin(12.0f, 8.0f));
        StyleRoundedFrame(Tree, TEXT("ReferenceGuildRegisteredTitleFrame"), FLinearColor(0.70f, 0.52f, 0.29f, 0.98f), FLinearColor(0.91f, 0.74f, 0.42f, 1.0f), 5.0f, 1.5f, FMargin(12.0f, 8.0f));
        GuildActiveHeading->SetColorAndOpacity(FSlateColor(FLinearColor(0.11f, 0.075f, 0.025f, 1.0f)));
        GuildRegisteredHeading->SetColorAndOpacity(FSlateColor(FLinearColor(0.11f, 0.075f, 0.025f, 1.0f)));

        for (const FName ShadowText : {
            FName(TEXT("DiplomacyHeadingText")),
            FName(TEXT("DiplomacySubtitleText")),
            FName(TEXT("RelationTitleText")),
            FName(TEXT("RelationStateText")),
            FName(TEXT("AllianceHeadingText")),
            FName(TEXT("AllianceSubtitleText")),
            FName(TEXT("ReferenceAllianceSummaryTitleText")),
            FName(TEXT("ReferenceAllianceMembersTitleText")),
            FName(TEXT("ChatHeadingText")),
            FName(TEXT("GuildSubtitleText")),
            FName(TEXT("ReferenceGuildInfoTitleText"))
        })
        {
            StyleTextShadow(Tree, ShadowText);
        }

        FBlueprintEditorUtils::MarkBlueprintAsStructurallyModified(Panel);
        FKismetEditorUtilities::CompileBlueprint(Panel);
        if (!SaveAsset(Panel))
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI secondary reference update failed while saving panel."));
            return false;
        }
        UE_LOG(LogTemp, Display, TEXT("PALTR_UI_SECONDARY_REFERENCE_OK | diplomacy=2col | alliance=3col | guilds=3col"));
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

    bool UpdatePixelMatchVisual()
    {
        const FString ArtDirectory = FPaths::ConvertRelativePathToFull(
            FPaths::ProjectPluginsDir() / TEXT("PalTRUIAssetBuilder/Resources")
        );
        UTexture2D* ParchmentTexture = ImportUITexture(
            TEXT("/Game/Mods/PalTRUI/Art/T_PalTRParchmentHeader"),
            TEXT("T_PalTRParchmentHeader"),
            ArtDirectory / TEXT("paltr_parchment_header.png")
        );
        UTexture2D* DashboardChromeTexture = ImportUITexture(
            TEXT("/Game/Mods/PalTRUI/Art/T_PalTRDashboardChrome"),
            TEXT("T_PalTRDashboardChrome"),
            ArtDirectory / TEXT("paltr_dashboard_chrome.png")
        );
        UTexture2D* ClanIcon = LoadObject<UTexture2D>(
            nullptr,
            TEXT("/Game/Mods/PalTRUI/Art/T_PalTRClanIcon.T_PalTRClanIcon")
        );
        UTexture2D* DiplomacyIcon = LoadObject<UTexture2D>(
            nullptr,
            TEXT("/Game/Mods/PalTRUI/Art/T_PalTRDiplomacyIcon.T_PalTRDiplomacyIcon")
        );
        UTexture2D* ProtectionIcon = LoadObject<UTexture2D>(
            nullptr,
            TEXT("/Game/Mods/PalTRUI/Art/T_PalTRProtectionIcon.T_PalTRProtectionIcon")
        );
        UTexture2D* BuildingsIcon = LoadObject<UTexture2D>(
            nullptr,
            TEXT("/Game/Mods/PalTRUI/Art/T_PalTRBuildingsIcon.T_PalTRBuildingsIcon")
        );
        if (!ParchmentTexture || !DashboardChromeTexture || !ClanIcon || !DiplomacyIcon
            || !ProtectionIcon || !BuildingsIcon)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI pixel match update failed: art textures incomplete."));
            return false;
        }

        UWidgetBlueprint* Panel = LoadObject<UWidgetBlueprint>(
            nullptr,
            TEXT("/Game/Mods/PalTRUI/WBP_PalTRPanel.WBP_PalTRPanel")
        );
        if (!Panel || !Panel->WidgetTree)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI pixel match update failed: panel asset missing."));
            return false;
        }

        UWidgetTree* Tree = Panel->WidgetTree;
        UButton* InputShield = Cast<UButton>(Tree->FindWidget(TEXT("PanelInputShield")));
        UBorder* Background = Cast<UBorder>(Tree->FindWidget(TEXT("PanelBackground")));
        UBorder* ArtContentPadding = Cast<UBorder>(Tree->FindWidget(TEXT("PanelArtContentPadding")));
        UBorder* HeaderFrame = Cast<UBorder>(Tree->FindWidget(TEXT("HeaderFrame")));
        UBorder* ContentFrame = Cast<UBorder>(Tree->FindWidget(TEXT("ContentFrame")));
        UBorder* FooterFrame = Cast<UBorder>(Tree->FindWidget(TEXT("FooterFrame")));
        UTextBlock* FooterHint = Cast<UTextBlock>(Tree->FindWidget(TEXT("FooterHintText")));
        UHorizontalBox* FooterHintRow = Cast<UHorizontalBox>(Tree->FindWidget(TEXT("FooterHintRow")));
        UBorder* FooterF6KeyFrame = Cast<UBorder>(Tree->FindWidget(TEXT("FooterF6KeyFrame")));
        UBorder* FooterEscKeyFrame = Cast<UBorder>(Tree->FindWidget(TEXT("FooterEscKeyFrame")));
        UHorizontalBox* BodyRow = Cast<UHorizontalBox>(Tree->FindWidget(TEXT("PanelBodyRow")));
        USizeBox* NavigationSize = Cast<USizeBox>(Tree->FindWidget(TEXT("LeftNavigationSize")));
        UBorder* NavigationFrame = Cast<UBorder>(Tree->FindWidget(TEXT("LeftNavigationFrame")));
        USizeBox* HeaderCrestSize = Cast<USizeBox>(Tree->FindWidget(TEXT("HeaderCrestImageSize")));
        UHorizontalBox* StatusCards = Cast<UHorizontalBox>(Tree->FindWidget(TEXT("DashboardStatusCardsFrame")));
        UHorizontalBox* DashboardColumns = Cast<UHorizontalBox>(Tree->FindWidget(TEXT("DashboardColumns")));
        UVerticalBox* MainColumn = Cast<UVerticalBox>(Tree->FindWidget(TEXT("DashboardMainColumn")));
        UVerticalBox* SidebarColumn = Cast<UVerticalBox>(Tree->FindWidget(TEXT("DashboardSidebarColumn")));
        UHorizontalBox* LowerRow = Cast<UHorizontalBox>(Tree->FindWidget(TEXT("DashboardLowerRow")));
        UBorder* RecentFrame = Cast<UBorder>(Tree->FindWidget(TEXT("DashboardRecentEventsFrame")));
        UBorder* QuickFrame = Cast<UBorder>(Tree->FindWidget(TEXT("DashboardQuickActionsFrame")));
        USizeBox* DashboardSize = Cast<USizeBox>(Tree->FindWidget(TEXT("DashboardColumnsSize")));
        UVerticalBox* ClanPage = Cast<UVerticalBox>(Tree->FindWidget(TEXT("ClanPage")));
        UTextBlock* ClanHeading = Cast<UTextBlock>(Tree->FindWidget(TEXT("ClanHeadingText")));
        UTextBlock* ClanSubtitle = Cast<UTextBlock>(Tree->FindWidget(TEXT("ClanSubtitleText")));
        if (!Background || !ArtContentPadding || !HeaderFrame || !ContentFrame || !FooterFrame
            || !BodyRow || !NavigationSize || !NavigationFrame || !HeaderCrestSize
            || !StatusCards || !DashboardColumns || !MainColumn || !SidebarColumn
            || !LowerRow || !RecentFrame || !QuickFrame || !DashboardSize
            || !ClanPage || !ClanHeading || !ClanSubtitle)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI pixel match update failed: presentation hierarchy incomplete."));
            return false;
        }

        Panel->Modify();
        Tree->Modify();

        ArtContentPadding->Modify();
        ArtContentPadding->SetBrushFromTexture(DashboardChromeTexture);
        ArtContentPadding->SetBrushColor(FLinearColor::White);
        ArtContentPadding->SetPadding(FMargin(16.0f, 12.0f));
        Background->SetBrush(FSlateRoundedBoxBrush(
            PixelTheme::Background,
            3.0f,
            PixelTheme::GoldMuted,
            1.0f
        ));
        Background->SetBrushColor(FLinearColor::White);

        auto MovePageTextIntoMain = [MainColumn](UTextBlock* Text, const int32 Index, const FMargin Padding) -> bool
        {
            if (!Text)
            {
                return false;
            }
            if (Text->GetParent() != MainColumn)
            {
                UPanelWidget* Parent = Text->GetParent();
                if (!Parent || !Parent->RemoveChild(Text))
                {
                    return false;
                }
                UVerticalBoxSlot* Slot = Cast<UVerticalBoxSlot>(MainColumn->InsertChildAt(Index, Text));
                if (!Slot)
                {
                    return false;
                }
                Slot->SetHorizontalAlignment(HAlign_Fill);
                Slot->SetPadding(Padding);
            }
            else if (UVerticalBoxSlot* Slot = Cast<UVerticalBoxSlot>(Text->Slot))
            {
                Slot->SetPadding(Padding);
            }
            return true;
        };
        if (!MovePageTextIntoMain(ClanHeading, 0, FMargin(8, 4, 0, 4))
            || !MovePageTextIntoMain(ClanSubtitle, 1, FMargin(8, 0, 0, 14)))
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI pixel match update failed: dashboard heading relocation."));
            return false;
        }

        const FAnchors PixelAnchors(0.055f, 0.040f, 0.945f, 0.955f);
        if (InputShield)
        {
            if (UCanvasPanelSlot* Slot = Cast<UCanvasPanelSlot>(InputShield->Slot))
            {
                Slot->Modify();
                Slot->SetAnchors(PixelAnchors);
                Slot->SetAlignment(FVector2D::ZeroVector);
                Slot->SetOffsets(FMargin(0.0f));
            }
        }
        else if (UCanvasPanelSlot* Slot = Cast<UCanvasPanelSlot>(Background->Slot))
        {
            Slot->Modify();
            Slot->SetAnchors(PixelAnchors);
            Slot->SetAlignment(FVector2D::ZeroVector);
            Slot->SetOffsets(FMargin(0.0f));
        }

        // Literal 1672x941 reference geometry. The visible panel runs from
        // x=62..1573 and its body is split into 304 / 821 / 391 pixel regions.
        HeaderCrestSize->SetWidthOverride(92.0f);
        HeaderCrestSize->SetHeightOverride(77.0f);
        NavigationSize->SetWidthOverride(304.0f);
        DashboardSize->SetHeightOverride(725.0f);

        StyleTransparentFrame(Tree, TEXT("HeaderFrame"), FMargin(12.0f, 0.0f));
        StyleTransparentFrame(Tree, TEXT("ContentFrame"), FMargin(0.0f));
        StyleTransparentFrame(Tree, TEXT("FooterFrame"), FMargin(10.0f, 14.0f));
        StyleTransparentFrame(Tree, TEXT("LeftNavigationFrame"), FMargin(16.0f, 18.0f));

        StyleRoundedFrame(Tree, TEXT("HeaderServerFrame"), PixelTheme::FromSRGB(9, 31, 39, 0.98f),
            PixelTheme::GoldMuted, 5.0f, 1.0f, FMargin(11.0f, 7.0f));
        StyleRoundedFrame(Tree, TEXT("HeaderGuildFrame"), PixelTheme::FromSRGB(20, 86, 91, 0.98f),
            PixelTheme::CyanDark, 4.0f, 1.0f, FMargin(10.0f, 7.0f));
        StyleRoundedFrame(Tree, TEXT("HeaderRoleFrame"), PixelTheme::FromSRGB(91, 69, 26, 0.98f),
            PixelTheme::GoldMuted, 4.0f, 1.0f, FMargin(10.0f, 7.0f));
        StyleRoundedFrame(Tree, TEXT("HeaderNotificationFrame"), PixelTheme::FromSRGB(111, 43, 33, 0.98f),
            PixelTheme::FromSRGB(155, 71, 52, 1.0f), 4.0f, 1.0f, FMargin(10.0f, 7.0f));

        if (UVerticalBoxSlot* HeaderSlot = Cast<UVerticalBoxSlot>(HeaderFrame->Slot))
        {
            HeaderSlot->SetPadding(FMargin(0.0f));
        }
        if (UVerticalBoxSlot* FooterSlot = Cast<UVerticalBoxSlot>(FooterFrame->Slot))
        {
            FooterSlot->SetPadding(FMargin(0.0f));
        }
        if (UHorizontalBoxSlot* NavigationSlot = Cast<UHorizontalBoxSlot>(NavigationSize->Slot))
        {
            NavigationSlot->SetPadding(FMargin(0.0f));
            NavigationSlot->SetVerticalAlignment(VAlign_Fill);
        }
        if (!FooterHintRow && !FooterF6KeyFrame && !FooterEscKeyFrame)
        {
            if (!FooterHint || FooterHint->GetParent() != FooterFrame || !FooterFrame->RemoveChild(FooterHint))
            {
                UE_LOG(LogTemp, Error, TEXT("PalTRUI pixel match update failed: footer source hierarchy."));
                return false;
            }
            FooterHint->SetVisibility(ESlateVisibility::Collapsed);
            FooterHintRow = Tree->ConstructWidget<UHorizontalBox>(UHorizontalBox::StaticClass(), TEXT("FooterHintRow"));
            FooterF6KeyFrame = Tree->ConstructWidget<UBorder>(UBorder::StaticClass(), TEXT("FooterF6KeyFrame"));
            FooterF6KeyFrame->SetContent(MakeText(Tree, TEXT("FooterF6KeyText"), TEXT("F6"), 15));
            AddHorizontal(FooterHintRow, FooterF6KeyFrame, FMargin(0, 0, 10, 0));
            AddHorizontal(FooterHintRow, MakeText(Tree, TEXT("FooterPanelLabelText"), TEXT("Panel"), 15), FMargin(0, 0, 18, 0));
            AddHorizontal(FooterHintRow, MakeText(Tree, TEXT("FooterSeparatorText"), TEXT("|"), 15), FMargin(0, 0, 18, 0));
            FooterEscKeyFrame = Tree->ConstructWidget<UBorder>(UBorder::StaticClass(), TEXT("FooterEscKeyFrame"));
            FooterEscKeyFrame->SetContent(MakeText(Tree, TEXT("FooterEscKeyText"), TEXT("Esc"), 15));
            AddHorizontal(FooterHintRow, FooterEscKeyFrame, FMargin(0, 0, 10, 0));
            AddHorizontal(FooterHintRow, MakeText(Tree, TEXT("FooterCloseLabelText"), TEXT("Kapat"), 15));
            AddHorizontal(FooterHintRow, FooterHint);
            FooterFrame->SetContent(FooterHintRow);
        }
        else if (!FooterHintRow || !FooterF6KeyFrame || !FooterEscKeyFrame
            || FooterHintRow->GetParent() != FooterFrame)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI pixel match update refused: partial footer keycap hierarchy."));
            return false;
        }
        if (!FooterHint)
        {
            FooterHint = MakeText(Tree, TEXT("FooterHintText"), TEXT("F6  Panel     |     Esc  Kapat"), 16);
            FooterHint->SetVisibility(ESlateVisibility::Collapsed);
            AddHorizontal(FooterHintRow, FooterHint);
        }
        FooterHint->SetText(FText::FromString(TEXT("F6  Panel     |     Esc  Kapat")));
        FooterHint->SetJustification(ETextJustify::Center);
        FooterHint->SetColorAndOpacity(FSlateColor(PixelTheme::TextPrimary));
        FooterHint->SetVisibility(ESlateVisibility::Collapsed);
        SetTextFontSize(Tree, TEXT("FooterHintText"), 16);
        if (UBorderSlot* FooterContentSlot = Cast<UBorderSlot>(FooterHintRow->Slot))
        {
            FooterContentSlot->SetHorizontalAlignment(HAlign_Center);
            FooterContentSlot->SetVerticalAlignment(VAlign_Center);
        }
        StyleRoundedFrame(Tree, TEXT("FooterF6KeyFrame"), PixelTheme::FromSRGB(12, 22, 29, 0.98f),
            PixelTheme::FromSRGB(107, 105, 94, 0.96f), 3.0f, 1.0f, FMargin(7.0f, 3.0f));
        StyleRoundedFrame(Tree, TEXT("FooterEscKeyFrame"), PixelTheme::FromSRGB(12, 22, 29, 0.98f),
            PixelTheme::FromSRGB(107, 105, 94, 0.96f), 3.0f, 1.0f, FMargin(7.0f, 3.0f));

        if (UHorizontalBoxSlot* MainSlot = Cast<UHorizontalBoxSlot>(MainColumn->Slot))
        {
            FSlateChildSize Size(ESlateSizeRule::Fill);
            Size.Value = 821.0f;
            MainSlot->SetSize(Size);
            MainSlot->SetPadding(FMargin(18.0f, 0.0f, 8.0f, 0.0f));
            MainSlot->SetVerticalAlignment(VAlign_Fill);
        }
        if (UHorizontalBoxSlot* SidebarSlot = Cast<UHorizontalBoxSlot>(SidebarColumn->Slot))
        {
            FSlateChildSize Size(ESlateSizeRule::Fill);
            Size.Value = 391.0f;
            SidebarSlot->SetSize(Size);
            SidebarSlot->SetPadding(FMargin(8.0f, 0.0f, 16.0f, 0.0f));
            SidebarSlot->SetVerticalAlignment(VAlign_Fill);
        }
        if (UHorizontalBoxSlot* RecentSlot = Cast<UHorizontalBoxSlot>(RecentFrame->Slot))
        {
            FSlateChildSize Size(ESlateSizeRule::Fill);
            Size.Value = 1.18f;
            RecentSlot->SetSize(Size);
            RecentSlot->SetPadding(FMargin(0, 0, 8, 0));
            RecentSlot->SetVerticalAlignment(VAlign_Fill);
        }
        if (UHorizontalBoxSlot* QuickSlot = Cast<UHorizontalBoxSlot>(QuickFrame->Slot))
        {
            FSlateChildSize Size(ESlateSizeRule::Fill);
            Size.Value = 1.0f;
            QuickSlot->SetSize(Size);
            QuickSlot->SetPadding(FMargin(8, 0, 0, 0));
            QuickSlot->SetVerticalAlignment(VAlign_Fill);
        }

        const FName CardFrames[] = {
            TEXT("DashboardClanCardFrame"),
            TEXT("DashboardDiplomacyCardFrame"),
            TEXT("DashboardProtectionCardFrame"),
            TEXT("DashboardBuildingsCardFrame")
        };
        for (int32 Index = 0; Index < UE_ARRAY_COUNT(CardFrames); ++Index)
        {
            if (UBorder* Card = Cast<UBorder>(Tree->FindWidget(CardFrames[Index])))
            {
                if (UHorizontalBoxSlot* Slot = Cast<UHorizontalBoxSlot>(Card->Slot))
                {
                    Slot->SetSize(FSlateChildSize(ESlateSizeRule::Fill));
                    Slot->SetPadding(FMargin(Index == 0 ? 0.0f : 8.0f, 0,
                        Index + 1 == UE_ARRAY_COUNT(CardFrames) ? 0.0f : 8.0f, 0));
                    Slot->SetVerticalAlignment(VAlign_Fill);
                }
            }
        }

        const FLinearColor NoOutline = FLinearColor::Transparent;
        StyleRoundedFrame(Tree, TEXT("DashboardClanCardFrame"), PixelTheme::FromSRGB(8, 82, 77, 0.72f),
            NoOutline, 3.0f, 0.0f, FMargin(12.0f));
        StyleRoundedFrame(Tree, TEXT("DashboardDiplomacyCardFrame"), PixelTheme::FromSRGB(18, 67, 101, 0.72f),
            NoOutline, 3.0f, 0.0f, FMargin(12.0f));
        StyleRoundedFrame(Tree, TEXT("DashboardProtectionCardFrame"), PixelTheme::FromSRGB(115, 81, 25, 0.68f),
            NoOutline, 3.0f, 0.0f, FMargin(12.0f));
        StyleRoundedFrame(Tree, TEXT("DashboardBuildingsCardFrame"), PixelTheme::FromSRGB(92, 48, 21, 0.68f),
            NoOutline, 3.0f, 0.0f, FMargin(12.0f));
        StyleTransparentFrame(Tree, TEXT("DashboardRecentEventsFrame"), FMargin(16.0f));
        StyleTransparentFrame(Tree, TEXT("DashboardQuickActionsFrame"), FMargin(14.0f));
        StyleTransparentFrame(Tree, TEXT("DashboardRelationsFrame"), FMargin(14.0f));
        StyleTransparentFrame(Tree, TEXT("PendingOffersFrame"), FMargin(14.0f));

        const FName DashboardChromeTitleFrames[] = {
            TEXT("DashboardSidebarTitleFrame"),
            TEXT("PendingOffersTitleFrame")
        };
        for (const FName FrameName : DashboardChromeTitleFrames)
        {
            StyleTransparentFrame(Tree, FrameName, FMargin(16.0f, 9.0f));
        }
        const FName SecondaryParchmentFrames[] = {
            TEXT("ReferenceDiplomacyListTitleFrame"),
            TEXT("ReferenceDiplomacyDetailTitleFrame"),
            TEXT("ReferenceGuildActiveTitleFrame"),
            TEXT("ReferenceGuildRegisteredTitleFrame")
        };
        for (const FName FrameName : SecondaryParchmentFrames)
        {
            StyleTextureFrame(Tree, FrameName, ParchmentTexture,
                FMargin(0.025f, 0.075f), FMargin(16.0f, 9.0f));
        }
        for (const FName ParchmentText : {
            FName(TEXT("DashboardSidebarTitleText")),
            FName(TEXT("PendingOffersHeadingText")),
            FName(TEXT("ReferenceDiplomacyListTitleText")),
            FName(TEXT("ReferenceDiplomacyDetailTitleText")),
            FName(TEXT("GuildCatalogActiveHeadingText")),
            FName(TEXT("GuildCatalogRegisteredHeadingText"))
        })
        {
            if (UTextBlock* Text = Cast<UTextBlock>(Tree->FindWidget(ParchmentText)))
            {
                Text->SetColorAndOpacity(FSlateColor(PixelTheme::FromSRGB(66, 48, 24, 1.0f)));
                StyleTextShadow(Tree, ParchmentText, FVector2D(0, 1), PixelTheme::FromSRGB(255, 244, 210, 0.34f));
            }
        }
        if (UTextBlock* RelationsHeading = Cast<UTextBlock>(Tree->FindWidget(TEXT("DashboardSidebarTitleText"))))
        {
            RelationsHeading->SetRenderTranslation(FVector2D(0.0f, 10.0f));
        }
        if (UTextBlock* PendingHeading = Cast<UTextBlock>(Tree->FindWidget(TEXT("PendingOffersHeadingText"))))
        {
            PendingHeading->SetRenderTranslation(FVector2D(0.0f, 10.0f));
        }

        struct FNavigationVisual
        {
            const TCHAR* Button;
            const TCHAR* Label;
            const TCHAR* Content;
            const TCHAR* IconSize;
            const TCHAR* Icon;
            const TCHAR* Arrow;
            UTexture2D* Texture;
            bool bLive;
        };
        const FNavigationVisual NavigationVisuals[] = {
            { TEXT("ClanTabButton"), TEXT("ClanTabText"), TEXT("ClanNavContent"), TEXT("ClanNavIconSize"), TEXT("ClanNavIcon"), TEXT("ClanNavArrowText"), ClanIcon, true },
            { TEXT("DiplomacyTabButton"), TEXT("DiplomacyTabText"), TEXT("DiplomacyNavContent"), TEXT("DiplomacyNavIconSize"), TEXT("DiplomacyNavIcon"), TEXT("DiplomacyNavArrowText"), DiplomacyIcon, true },
            { TEXT("AllianceTabButton"), TEXT("AllianceTabText"), TEXT("AllianceNavContent"), TEXT("AllianceNavIconSize"), TEXT("AllianceNavIcon"), TEXT("AllianceNavArrowText"), DiplomacyIcon, true },
            { TEXT("ChatTabButton"), TEXT("ChatTabText"), TEXT("GuildsNavContent"), TEXT("GuildsNavIconSize"), TEXT("GuildsNavIcon"), TEXT("GuildsNavArrowText"), ClanIcon, true },
            { TEXT("FutureProtectionButton"), TEXT("FutureProtectionButtonText"), TEXT("ProtectionNavContent"), TEXT("ProtectionNavIconSize"), TEXT("ProtectionNavIcon"), TEXT("ProtectionNavArrowText"), ProtectionIcon, false },
            { TEXT("FutureStructuresButton"), TEXT("FutureStructuresButtonText"), TEXT("StructuresNavContent"), TEXT("StructuresNavIconSize"), TEXT("StructuresNavIcon"), TEXT("StructuresNavArrowText"), BuildingsIcon, false }
        };
        for (const FNavigationVisual& Spec : NavigationVisuals)
        {
            UButton* Button = Cast<UButton>(Tree->FindWidget(FName(Spec.Button)));
            UTextBlock* Label = Cast<UTextBlock>(Tree->FindWidget(FName(Spec.Label)));
            UHorizontalBox* Content = Cast<UHorizontalBox>(Tree->FindWidget(FName(Spec.Content)));
            USizeBox* IconSize = Cast<USizeBox>(Tree->FindWidget(FName(Spec.IconSize)));
            UImage* Icon = Cast<UImage>(Tree->FindWidget(FName(Spec.Icon)));
            UTextBlock* Arrow = Cast<UTextBlock>(Tree->FindWidget(FName(Spec.Arrow)));
            if (!Content && !IconSize && !Icon && !Arrow)
            {
                if (!Button || !Label || Button->GetContent() != Label)
                {
                    UE_LOG(LogTemp, Error, TEXT("PalTRUI pixel match update failed: navigation source: %s"), Spec.Button);
                    return false;
                }
                Button->RemoveChild(Label);
                Content = Tree->ConstructWidget<UHorizontalBox>(UHorizontalBox::StaticClass(), FName(Spec.Content));
                IconSize = Tree->ConstructWidget<USizeBox>(USizeBox::StaticClass(), FName(Spec.IconSize));
                IconSize->SetWidthOverride(36.0f);
                IconSize->SetHeightOverride(36.0f);
                Icon = Tree->ConstructWidget<UImage>(UImage::StaticClass(), FName(Spec.Icon));
                IconSize->SetContent(Icon);
                AddHorizontal(Content, IconSize, FMargin(0, 0, 14, 0));
                UHorizontalBoxSlot* LabelSlot = AddHorizontal(Content, Label);
                LabelSlot->SetSize(FSlateChildSize(ESlateSizeRule::Fill));
                LabelSlot->SetVerticalAlignment(VAlign_Center);
                Label->SetJustification(ETextJustify::Left);
                Arrow = MakeText(Tree, FName(Spec.Arrow), Spec.bLive ? TEXT(">") : TEXT(""), 18);
                Arrow->SetColorAndOpacity(FSlateColor(PixelTheme::Cyan));
                AddHorizontal(Content, Arrow, FMargin(10, 0, 0, 0));
                Button->SetContent(Content);
            }
            else if (!Button || !Label || !Content || !IconSize || !Icon || !Arrow
                || Button->GetContent() != Content || IconSize->GetContent() != Icon)
            {
                UE_LOG(LogTemp, Error, TEXT("PalTRUI pixel match update refused: partial navigation visual: %s"), Spec.Button);
                return false;
            }
            Icon->SetBrushFromTexture(Spec.Texture, true);
            IconSize->SetWidthOverride(Spec.bLive ? 46.0f : 40.0f);
            IconSize->SetHeightOverride(Spec.bLive ? 46.0f : 40.0f);
            FButtonStyle Style = Button->WidgetStyle;
            const bool bHomeEntry = FName(Spec.Button) == FName(TEXT("ClanTabButton"));
            Style.SetNormal(bHomeEntry
                ? FSlateRoundedBoxBrush(PixelTheme::FromSRGB(7, 87, 108, 0.96f), 4.0f, PixelTheme::Cyan, 1.5f)
                : FSlateRoundedBoxBrush(PixelTheme::FromSRGB(3, 18, 29, 0.06f), 0.0f));
            Style.SetHovered(FSlateRoundedBoxBrush(PixelTheme::FromSRGB(7, 72, 91, 0.94f), 4.0f, PixelTheme::Cyan, 1.5f));
            Style.SetPressed(FSlateRoundedBoxBrush(PixelTheme::FromSRGB(10, 102, 116, 0.99f), 4.0f, PixelTheme::Cyan, 2.0f));
            Style.SetDisabled(FSlateRoundedBoxBrush(PixelTheme::FromSRGB(31, 38, 41, 0.92f), 3.0f, PixelTheme::FromSRGB(62, 68, 68, 0.90f), 1.0f));
            Style.SetNormalPadding(FMargin(12.0f, 7.0f));
            Style.SetPressedPadding(FMargin(12.0f, 8.0f, 12.0f, 6.0f));
            Button->SetStyle(Style);
            SetTextFontSize(Tree, FName(Spec.Label), Spec.bLive ? 17 : 12);
        }

        UTexture2D* EventTextures[] = {
            DiplomacyIcon, DiplomacyIcon, ProtectionIcon, ClanIcon, BuildingsIcon
        };
        for (int32 Index = 1; Index <= 5; ++Index)
        {
            const FName RowName(*FString::Printf(TEXT("DashboardRecentEvent%dRow"), Index));
            const FName SizeName(*FString::Printf(TEXT("DashboardRecentEvent%dIconSize"), Index));
            const FName IconName(*FString::Printf(TEXT("DashboardRecentEvent%dIcon"), Index));
            UHorizontalBox* Row = Cast<UHorizontalBox>(Tree->FindWidget(RowName));
            USizeBox* IconSize = Cast<USizeBox>(Tree->FindWidget(SizeName));
            UImage* Icon = Cast<UImage>(Tree->FindWidget(IconName));
            if (!IconSize && !Icon)
            {
                if (!Row)
                {
                    UE_LOG(LogTemp, Error, TEXT("PalTRUI pixel match update failed: event row missing: %d"), Index);
                    return false;
                }
                IconSize = Tree->ConstructWidget<USizeBox>(USizeBox::StaticClass(), SizeName);
                IconSize->SetWidthOverride(28.0f);
                IconSize->SetHeightOverride(28.0f);
                Icon = Tree->ConstructWidget<UImage>(UImage::StaticClass(), IconName);
                IconSize->SetContent(Icon);
                UHorizontalBoxSlot* Slot = Cast<UHorizontalBoxSlot>(Row->InsertChildAt(0, IconSize));
                if (!Slot)
                {
                    return false;
                }
                Slot->SetPadding(FMargin(0, 0, 10, 0));
                Slot->SetVerticalAlignment(VAlign_Center);
            }
            else if (!IconSize || !Icon || IconSize->GetContent() != Icon || IconSize->GetParent() != Row)
            {
                UE_LOG(LogTemp, Error, TEXT("PalTRUI pixel match update refused: partial event icon: %d"), Index);
                return false;
            }
            Icon->SetBrushFromTexture(EventTextures[Index - 1], true);
            IconSize->SetWidthOverride(38.0f);
            IconSize->SetHeightOverride(38.0f);
            StyleTransparentFrame(Tree,
                FName(*FString::Printf(TEXT("DashboardRecentEvent%dFrame"), Index)),
                FMargin(4.0f, 4.0f));
        }

        for (const FName CardIconSizeName : {
            FName(TEXT("DashboardClanIconSize")),
            FName(TEXT("DashboardDiplomacyIconSize")),
            FName(TEXT("DashboardProtectionIconSize")),
            FName(TEXT("DashboardBuildingsIconSize"))
        })
        {
            if (USizeBox* IconSize = Cast<USizeBox>(Tree->FindWidget(CardIconSizeName)))
            {
                IconSize->SetWidthOverride(88.0f);
                IconSize->SetHeightOverride(88.0f);
            }
        }
        for (int32 Index = 1; Index <= 3; ++Index)
        {
            if (USizeBox* IconSize = Cast<USizeBox>(Tree->FindWidget(
                FName(*FString::Printf(TEXT("DashboardRelation%dIconSize"), Index)))))
            {
                IconSize->SetWidthOverride(64.0f);
                IconSize->SetHeightOverride(72.0f);
                IconSize->SetWidthOverride(72.0f);
            }
            StyleTransparentFrame(Tree,
                FName(*FString::Printf(TEXT("DashboardRelationRow%dFrame"), Index)),
                FMargin(4.0f, 6.0f));
            SetTextFontSize(Tree,
                FName(*FString::Printf(TEXT("DashboardRelationRow%dNameText"), Index)), 16);
            SetTextFontSize(Tree,
                FName(*FString::Printf(TEXT("DashboardRelationRow%dStateText"), Index)), 12);
        }
        if (USizeBox* PendingIconSize = Cast<USizeBox>(Tree->FindWidget(TEXT("DashboardPendingIconSize"))))
        {
            PendingIconSize->SetWidthOverride(74.0f);
            PendingIconSize->SetHeightOverride(74.0f);
        }
        StyleTransparentFrame(Tree, TEXT("DashboardPendingCardFrame"), FMargin(12.0f, 10.0f));
        SetTextFontSize(Tree, TEXT("PendingOffersHeadingText"), 18);
        SetTextFontSize(Tree, TEXT("DashboardPendingGuildText"), 17);
        SetTextFontSize(Tree, TEXT("DashboardPendingStateText"), 14);
        for (const FName QuickIconSizeName : {
            FName(TEXT("DashboardDiplomacyButtonIconSize")),
            FName(TEXT("DashboardOffersButtonIconSize")),
            FName(TEXT("DashboardGuildsButtonIconSize")),
            FName(TEXT("DashboardProtectionButtonIconSize"))
        })
        {
            if (USizeBox* IconSize = Cast<USizeBox>(Tree->FindWidget(QuickIconSizeName)))
            {
                IconSize->SetWidthOverride(34.0f);
                IconSize->SetHeightOverride(34.0f);
            }
        }

        StyleButton(Tree, TEXT("DashboardDiplomacyButton"), PixelTheme::FromSRGB(16, 103, 116, 0.99f));
        StyleButton(Tree, TEXT("DashboardOffersButton"), PixelTheme::FromSRGB(13, 62, 73, 0.98f));
        StyleButton(Tree, TEXT("DashboardGuildsButton"), PixelTheme::FromSRGB(13, 75, 84, 0.98f));
        StyleButton(Tree, TEXT("DashboardProtectionButton"), PixelTheme::FromSRGB(34, 43, 45, 0.92f));
        StyleButton(Tree, TEXT("CloseButton"), PixelTheme::FromSRGB(111, 43, 33, 0.99f));

        SetTextFontSize(Tree, TEXT("DashboardClanCardTitleText"), 18);
        SetTextFontSize(Tree, TEXT("DashboardClanCardValueText"), 24);
        SetTextFontSize(Tree, TEXT("DashboardClanCardDetailText"), 13);
        SetTextFontSize(Tree, TEXT("DashboardDiplomacyCardTitleText"), 18);
        SetTextFontSize(Tree, TEXT("DashboardDiplomacyCardValueText"), 15);
        SetTextFontSize(Tree, TEXT("DashboardDiplomacyCardDetailText"), 13);
        SetTextFontSize(Tree, TEXT("DashboardProtectionCardTitleText"), 18);
        SetTextFontSize(Tree, TEXT("DashboardProtectionCardValueText"), 18);
        SetTextFontSize(Tree, TEXT("DashboardProtectionCardDetailText"), 12);
        SetTextFontSize(Tree, TEXT("DashboardBuildingsCardTitleText"), 18);
        SetTextFontSize(Tree, TEXT("DashboardBuildingsCardValueText"), 18);
        SetTextFontSize(Tree, TEXT("DashboardBuildingsCardDetailText"), 12);
        SetTextFontSize(Tree, TEXT("DashboardRecentEventsHeadingText"), 20);
        SetTextFontSize(Tree, TEXT("DashboardQuickActionsHeadingText"), 20);

        for (const FName HeadingName : {
            FName(TEXT("ClanHeadingText")),
            FName(TEXT("DiplomacyHeadingText")),
            FName(TEXT("AllianceHeadingText")),
            FName(TEXT("ChatHeadingText"))
        })
        {
            SetTextFontSize(Tree, HeadingName, 28);
            SetTextColor(Tree, HeadingName, PixelTheme::TextPrimary);
            StyleTextShadow(Tree, HeadingName, FVector2D(1, 2), FLinearColor(0, 0, 0, 0.92f));
        }
        SetTextFontSize(Tree, TEXT("TitleText"), 36);
        SetTextColor(Tree, TEXT("TitleText"), PixelTheme::TextPrimary);
        for (const FName SubtitleName : {
            FName(TEXT("ClanSubtitleText")),
            FName(TEXT("DiplomacySubtitleText")),
            FName(TEXT("AllianceSubtitleText")),
            FName(TEXT("GuildSubtitleText"))
        })
        {
            SetTextFontSize(Tree, SubtitleName, 14);
            SetTextColor(Tree, SubtitleName, PixelTheme::TextSecondary);
        }

        FBlueprintEditorUtils::MarkBlueprintAsStructurallyModified(Panel);
        FKismetEditorUtilities::CompileBlueprint(Panel);
        if (!SaveAsset(Panel))
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI pixel match update failed while saving panel."));
            return false;
        }
        UE_LOG(LogTemp, Display, TEXT("PALTR_UI_PIXEL_MATCH_OK | layout=1920x1080 | parchment=texture | navigation=icons | events=icons"));
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
            TEXT("/Game/Mods/PalTRUI/Art/T_PalTRBuildingsIcon.T_PalTRBuildingsIcon"),
            TEXT("/Game/Mods/PalTRUI/Art/T_PalTRParchmentHeader.T_PalTRParchmentHeader"),
            TEXT("/Game/Mods/PalTRUI/Art/T_PalTRDashboardChrome.T_PalTRDashboardChrome")
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
            TEXT("DashboardColumnsSize"),
            TEXT("DashboardMainColumn"),
            TEXT("DashboardSidebarColumn"),
            TEXT("HeaderFrame"),
            TEXT("HeaderServerFrame"),
            TEXT("HeaderServerContent"),
            TEXT("HeaderServerDotText"),
            TEXT("ClanSubtitleText"),
            TEXT("DiplomacySubtitleText"),
            TEXT("AllianceSubtitleText"),
            TEXT("GuildSubtitleText"),
            TEXT("DashboardSidebarTitleFrame"),
            TEXT("DashboardSidebarTitleText"),
            TEXT("DiplomacyListFrame"),
            TEXT("DiplomacyDetailFrame"),
            TEXT("ReferenceDiplomacyListContent"),
            TEXT("ReferenceDiplomacyListTitleFrame"),
            TEXT("ReferenceDiplomacyListTitleText"),
            TEXT("ReferenceDiplomacyDetailContent"),
            TEXT("ReferenceDiplomacyDetailTitleFrame"),
            TEXT("ReferenceDiplomacyDetailTitleText"),
            TEXT("PanelArtOverlay"),
            TEXT("PanelArtImage"),
            TEXT("PanelArtContentPadding"),
            TEXT("PanelBodyRow"),
            TEXT("LeftNavigationSize"),
            TEXT("LeftNavigationFrame"),
            TEXT("LeftNavigation"),
            TEXT("LeftNavigationHeadingText"),
            TEXT("FutureProtectionButton"),
            TEXT("FutureProtectionButtonText"),
            TEXT("FutureStructuresButton"),
            TEXT("FutureStructuresButtonText"),
            TEXT("FutureRegionsButton"),
            TEXT("FutureRegionsButtonText"),
            TEXT("FuturePlayersButton"),
            TEXT("FuturePlayersButtonText"),
            TEXT("FutureNotificationsButton"),
            TEXT("FutureNotificationsButtonText"),
            TEXT("FutureSettingsButton"),
            TEXT("FutureSettingsButtonText"),
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
            TEXT("DashboardRecentEvent1Frame"),
            TEXT("DashboardRecentEvent1Row"),
            TEXT("DashboardRecentEvent1MessageText"),
            TEXT("DashboardRecentEvent1TimeText"),
            TEXT("DashboardRecentEvent2Frame"),
            TEXT("DashboardRecentEvent2Row"),
            TEXT("DashboardRecentEvent2MessageText"),
            TEXT("DashboardRecentEvent2TimeText"),
            TEXT("DashboardRecentEvent3Frame"),
            TEXT("DashboardRecentEvent3Row"),
            TEXT("DashboardRecentEvent3MessageText"),
            TEXT("DashboardRecentEvent3TimeText"),
            TEXT("DashboardRecentEvent4Frame"),
            TEXT("DashboardRecentEvent4Row"),
            TEXT("DashboardRecentEvent4MessageText"),
            TEXT("DashboardRecentEvent4TimeText"),
            TEXT("DashboardRecentEvent5Frame"),
            TEXT("DashboardRecentEvent5Row"),
            TEXT("DashboardRecentEvent5MessageText"),
            TEXT("DashboardRecentEvent5TimeText"),
            TEXT("DashboardRecentEvent1Icon"),
            TEXT("DashboardRecentEvent2Icon"),
            TEXT("DashboardRecentEvent3Icon"),
            TEXT("DashboardRecentEvent4Icon"),
            TEXT("DashboardRecentEvent5Icon"),
            TEXT("ClanNavContent"),
            TEXT("ClanNavIcon"),
            TEXT("DiplomacyNavContent"),
            TEXT("DiplomacyNavIcon"),
            TEXT("AllianceNavContent"),
            TEXT("AllianceNavIcon"),
            TEXT("GuildsNavContent"),
            TEXT("GuildsNavIcon"),
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
            TEXT("DashboardProtectionButton"),
            TEXT("DashboardProtectionButtonText"),
            TEXT("DashboardDiplomacyButtonContent"),
            TEXT("DashboardDiplomacyButtonIconSize"),
            TEXT("DashboardDiplomacyButtonIcon"),
            TEXT("DashboardDiplomacyButtonArrowText"),
            TEXT("DashboardOffersButtonContent"),
            TEXT("DashboardOffersButtonIconSize"),
            TEXT("DashboardOffersButtonIcon"),
            TEXT("DashboardOffersButtonArrowText"),
            TEXT("DashboardGuildsButtonContent"),
            TEXT("DashboardGuildsButtonIconSize"),
            TEXT("DashboardGuildsButtonIcon"),
            TEXT("DashboardGuildsButtonArrowText"),
            TEXT("DashboardProtectionButtonContent"),
            TEXT("DashboardProtectionButtonIconSize"),
            TEXT("DashboardProtectionButtonIcon"),
            TEXT("DashboardProtectionButtonArrowText"),
            TEXT("PendingOffersTitleFrame"),
            TEXT("DashboardPendingCardFrame"),
            TEXT("DashboardPendingCardContent"),
            TEXT("DashboardPendingIdentity"),
            TEXT("DashboardPendingIconSize"),
            TEXT("DashboardPendingIcon"),
            TEXT("DashboardPendingCopy"),
            TEXT("DashboardPendingGuildText"),
            TEXT("DashboardPendingStateText"),
            TEXT("DashboardPendingActions"),
            TEXT("DashboardPendingAcceptButton"),
            TEXT("DashboardPendingAcceptButtonText"),
            TEXT("DashboardPendingRejectButton"),
            TEXT("DashboardPendingRejectButtonText"),
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
            TEXT("DashboardRelationRow1Frame"),
            TEXT("DashboardRelationRow1Content"),
            TEXT("DashboardRelationRow1IconSize"),
            TEXT("DashboardRelationRow1Icon"),
            TEXT("DashboardRelationRow1NameText"),
            TEXT("DashboardRelationRow1BadgeFrame"),
            TEXT("DashboardRelationRow1StateText"),
            TEXT("DashboardRelationRow2Frame"),
            TEXT("DashboardRelationRow2Content"),
            TEXT("DashboardRelationRow2IconSize"),
            TEXT("DashboardRelationRow2Icon"),
            TEXT("DashboardRelationRow2NameText"),
            TEXT("DashboardRelationRow2BadgeFrame"),
            TEXT("DashboardRelationRow2StateText"),
            TEXT("DashboardRelationRow3Frame"),
            TEXT("DashboardRelationRow3Content"),
            TEXT("DashboardRelationRow3IconSize"),
            TEXT("DashboardRelationRow3Icon"),
            TEXT("DashboardRelationRow3NameText"),
            TEXT("DashboardRelationRow3BadgeFrame"),
            TEXT("DashboardRelationRow3StateText"),
            TEXT("AllianceDetailFrame"),
            TEXT("AllianceDetailContent"),
            TEXT("ReferenceAllianceColumnsSize"),
            TEXT("ReferenceAllianceColumns"),
            TEXT("ReferenceAllianceSummaryFrame"),
            TEXT("ReferenceAllianceSummaryContent"),
            TEXT("ReferenceAllianceSummaryTitleText"),
            TEXT("ReferenceAllianceMembersFrame"),
            TEXT("ReferenceAllianceMembersContent"),
            TEXT("ReferenceAllianceMembersTitleText"),
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
            TEXT("ReferenceGuildActiveTitleFrame"),
            TEXT("ReferenceGuildRegisteredTitleFrame"),
            TEXT("ReferenceGuildInfoFrame"),
            TEXT("ReferenceGuildInfoContent"),
            TEXT("ReferenceGuildInfoTitleText"),
            TEXT("ReferenceGuildInfoText"),
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
        const FAnchors ExpectedPanelAnchors(0.055f, 0.040f, 0.945f, 0.955f);
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

        USizeBox* DashboardColumnsSize = Cast<USizeBox>(Panel->WidgetTree->FindWidget(TEXT("DashboardColumnsSize")));
        UHorizontalBox* DashboardColumns = Cast<UHorizontalBox>(Panel->WidgetTree->FindWidget(TEXT("DashboardColumns")));
        UHorizontalBox* DashboardLowerRow = Cast<UHorizontalBox>(Panel->WidgetTree->FindWidget(TEXT("DashboardLowerRow")));
        UBorder* DashboardRelations = Cast<UBorder>(Panel->WidgetTree->FindWidget(TEXT("DashboardRelationsFrame")));
        UBorder* DashboardOffers = Cast<UBorder>(Panel->WidgetTree->FindWidget(TEXT("PendingOffersFrame")));
        UVerticalBoxSlot* DashboardLowerSlot = DashboardLowerRow
            ? Cast<UVerticalBoxSlot>(DashboardLowerRow->Slot)
            : nullptr;
        UVerticalBoxSlot* DashboardRelationsSlot = DashboardRelations
            ? Cast<UVerticalBoxSlot>(DashboardRelations->Slot)
            : nullptr;
        UVerticalBoxSlot* DashboardOffersSlot = DashboardOffers
            ? Cast<UVerticalBoxSlot>(DashboardOffers->Slot)
            : nullptr;
        if (!DashboardColumnsSize
            || DashboardColumnsSize->GetContent() != DashboardColumns
            || !FMath::IsNearlyEqual(DashboardColumnsSize->GetHeightOverride(), 725.0f)
            || !DashboardLowerSlot
            || DashboardLowerSlot->GetSize().SizeRule != ESlateSizeRule::Fill
            || !DashboardRelationsSlot
            || DashboardRelationsSlot->GetSize().SizeRule != ESlateSizeRule::Fill
            || !DashboardOffersSlot
            || DashboardOffersSlot->GetSize().SizeRule != ESlateSizeRule::Fill)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI asset verification failed: reference dashboard proportions are incomplete."));
            return false;
        }
        for (const FName FutureButtonName : {
            FName(TEXT("FutureProtectionButton")),
            FName(TEXT("FutureStructuresButton")),
            FName(TEXT("FutureRegionsButton")),
            FName(TEXT("FuturePlayersButton")),
            FName(TEXT("FutureNotificationsButton")),
            FName(TEXT("FutureSettingsButton"))
        })
        {
            UButton* FutureButton = Cast<UButton>(Panel->WidgetTree->FindWidget(FutureButtonName));
            if (!FutureButton || FutureButton->GetIsEnabled())
            {
                UE_LOG(LogTemp, Error, TEXT("PalTRUI asset verification failed: future navigation must remain disabled: %s."), *FutureButtonName.ToString());
                return false;
            }
        }
        UButton* ProtectionQuickAction = Cast<UButton>(Panel->WidgetTree->FindWidget(TEXT("DashboardProtectionButton")));
        UTextBlock* LegacyRecentEvents = Cast<UTextBlock>(Panel->WidgetTree->FindWidget(TEXT("DashboardRecentEventsText")));
        UTextBlock* RelationsHeading = Cast<UTextBlock>(Panel->WidgetTree->FindWidget(TEXT("DashboardRelationsHeadingText")));
        if (!ProtectionQuickAction
            || ProtectionQuickAction->GetIsEnabled()
            || !LegacyRecentEvents
            || LegacyRecentEvents->GetVisibility() != ESlateVisibility::Collapsed
            || !RelationsHeading
            || RelationsHeading->GetVisibility() != ESlateVisibility::Collapsed)
        {
            UE_LOG(LogTemp, Error, TEXT("PalTRUI asset verification failed: reference dashboard content state is incomplete."));
            return false;
        }

        UE_LOG(
            LogTemp,
            Display,
            TEXT("PALTR_UI_ASSET_VERIFY_OK | mod_actor=%s | panel=%s | widgets=%d | textures=%d | viewport=92x90pct | events=5 | fill_chain=complete | dashboard=reference_proportions"),
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

    if (FParse::Param(*Params, TEXT("UpdateReferenceSecondaryPages")))
    {
        return UpdateReferenceSecondaryPages() ? 0 : 25;
    }

    if (FParse::Param(*Params, TEXT("UpdatePixelMatchVisual")))
    {
        return UpdatePixelMatchVisual() ? 0 : 26;
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
