using System.Collections.ObjectModel;
using System.Windows.Input;
using PalTRLauncher.Models;
using PalTRLauncher.Services;

namespace PalTRLauncher.ViewModels;

public sealed class LauncherViewModel : ObservableObject
{
    private readonly ILauncherService service;
    private readonly IExternalLinkService externalLinkService;
    private string selectedPage = "Ana Sayfa";
    private string statusMessage = "Launcher hazırlanıyor...";
    private bool isStatusSuccess = true;
    private string supportSubject = string.Empty;
    private string supportMessage = string.Empty;
    private int currentSlideIndex;
    private bool isAuthenticated;
    private bool isRegisterMode;
    private string loginIdentifier = string.Empty;
    private string loginPassword = string.Empty;
    private string registerDisplayName = string.Empty;
    private string registerEmail = string.Empty;
    private string registerPassword = string.Empty;
    private string registerPasswordConfirmation = string.Empty;
    private bool hasAcceptedTerms;
    private string authenticationMessage = "PalTR hesabınla devam et.";
    private bool isAuthenticationMessageError;
    private string signedInAccountName = string.Empty;

    public LauncherViewModel(
        ILauncherService service,
        IExternalLinkService externalLinkService)
    {
        this.service = service;
        this.externalLinkService = externalLinkService;
        RefreshCommand = new AsyncRelayCommand(RefreshAsync);
        JoinServerCommand = new AsyncRelayCommand(JoinServerAsync);
        CheckUpdatesCommand = new AsyncRelayCommand(CheckUpdatesAsync);
        SubmitTicketCommand = new AsyncRelayCommand(SubmitTicketAsync);
        SelectPageCommand = new RelayCommand(parameter => SelectedPage = parameter?.ToString() ?? "Ana Sayfa");
        PreviousSlideCommand = new RelayCommand(_ => MoveSlide(-1));
        NextSlideCommand = new RelayCommand(_ => MoveSlide(1));
        OpenSlideLinkCommand = new RelayCommand(_ => OpenCurrentSlideLink());
        ShowLoginCommand = new RelayCommand(_ => ShowAuthenticationMode(false));
        ShowRegisterCommand = new RelayCommand(_ => ShowAuthenticationMode(true));
        LoginCommand = new RelayCommand(_ => Login());
        RegisterCommand = new RelayCommand(_ => Register());
        LogoutCommand = new RelayCommand(_ => Logout());
    }

    public LauncherSnapshot Snapshot { get; private set; } = new();
    public ObservableCollection<LauncherNews> News { get; } = new();
    public ObservableCollection<LauncherNotification> Notifications { get; } = new();
    public ObservableCollection<LauncherTicket> Tickets { get; } = new();

    public LauncherSlide? CurrentSlide
        => Snapshot.Slides.Count == 0 ? null : Snapshot.Slides[currentSlideIndex];

    public int CurrentSlideNumber => Snapshot.Slides.Count == 0 ? 0 : currentSlideIndex + 1;
    public int SlideCount => Snapshot.Slides.Count;

    public bool IsLauncherVisible => isAuthenticated;
    public bool IsAuthenticationVisible => !isAuthenticated;
    public bool IsLoginMode => !isRegisterMode;
    public bool IsRegisterMode => isRegisterMode;
    public string AccountDisplayName => string.IsNullOrWhiteSpace(signedInAccountName)
        ? Snapshot.AccountName
        : signedInAccountName;

    public string LoginIdentifier
    {
        get => loginIdentifier;
        set => SetProperty(ref loginIdentifier, value);
    }

    public string LoginPassword
    {
        get => loginPassword;
        set => SetProperty(ref loginPassword, value);
    }

    public string RegisterDisplayName
    {
        get => registerDisplayName;
        set => SetProperty(ref registerDisplayName, value);
    }

    public string RegisterEmail
    {
        get => registerEmail;
        set => SetProperty(ref registerEmail, value);
    }

    public string RegisterPassword
    {
        get => registerPassword;
        set => SetProperty(ref registerPassword, value);
    }

    public string RegisterPasswordConfirmation
    {
        get => registerPasswordConfirmation;
        set => SetProperty(ref registerPasswordConfirmation, value);
    }

    public bool HasAcceptedTerms
    {
        get => hasAcceptedTerms;
        set => SetProperty(ref hasAcceptedTerms, value);
    }

    public string AuthenticationMessage
    {
        get => authenticationMessage;
        private set => SetProperty(ref authenticationMessage, value);
    }

    public bool IsAuthenticationMessageError
    {
        get => isAuthenticationMessageError;
        private set => SetProperty(ref isAuthenticationMessageError, value);
    }

    public string SelectedPage
    {
        get => selectedPage;
        set
        {
            if (SetProperty(ref selectedPage, value))
            {
                RaisePropertyChanged(nameof(IsHomePage));
                RaisePropertyChanged(nameof(IsNewsPage));
                RaisePropertyChanged(nameof(IsNotificationsPage));
                RaisePropertyChanged(nameof(IsSupportPage));
                RaisePropertyChanged(nameof(IsStorePage));
                RaisePropertyChanged(nameof(IsAccountPage));
            }
        }
    }

    public bool IsHomePage => SelectedPage == "Ana Sayfa";
    public bool IsNewsPage => SelectedPage == "Haberler";
    public bool IsNotificationsPage => SelectedPage == "Bildirimler";
    public bool IsSupportPage => SelectedPage == "Destek";
    public bool IsStorePage => SelectedPage == "Mağaza";
    public bool IsAccountPage => SelectedPage == "Hesabım";

    public string StatusMessage
    {
        get => statusMessage;
        private set => SetProperty(ref statusMessage, value);
    }

    public bool IsStatusSuccess
    {
        get => isStatusSuccess;
        private set => SetProperty(ref isStatusSuccess, value);
    }

    public string SupportSubject
    {
        get => supportSubject;
        set => SetProperty(ref supportSubject, value);
    }

    public string SupportMessage
    {
        get => supportMessage;
        set => SetProperty(ref supportMessage, value);
    }

    public ICommand RefreshCommand { get; }
    public ICommand JoinServerCommand { get; }
    public ICommand CheckUpdatesCommand { get; }
    public ICommand SubmitTicketCommand { get; }
    public ICommand SelectPageCommand { get; }
    public ICommand PreviousSlideCommand { get; }
    public ICommand NextSlideCommand { get; }
    public ICommand OpenSlideLinkCommand { get; }
    public ICommand ShowLoginCommand { get; }
    public ICommand ShowRegisterCommand { get; }
    public ICommand LoginCommand { get; }
    public ICommand RegisterCommand { get; }
    public ICommand LogoutCommand { get; }

    public async Task InitializeAsync() => await RefreshAsync();

    private async Task RefreshAsync()
    {
        Snapshot = await service.GetSnapshotAsync();
        News.ReplaceWith(Snapshot.News);
        Notifications.ReplaceWith(Snapshot.Notifications);
        Tickets.ReplaceWith(Snapshot.Tickets);
        RaisePropertyChanged(nameof(Snapshot));
        RaisePropertyChanged(nameof(AccountDisplayName));
        currentSlideIndex = 0;
        RaiseSlideProperties();
        SetStatus(true, "Demo launcher verileri hazır. Gerçek API bağlantısı sonraki fazda.");
    }

    private async Task JoinServerAsync()
    {
        LauncherActionResult result = await service.PrepareDirectJoinAsync();
        SetStatus(result.Success, result.Message);
    }

    private async Task CheckUpdatesAsync()
    {
        LauncherActionResult result = await service.CheckForUpdatesAsync();
        SetStatus(result.Success, result.Message);
    }

    private async Task SubmitTicketAsync()
    {
        LauncherActionResult result = await service.CreateSupportTicketAsync(
            SupportSubject,
            SupportMessage);
        SetStatus(result.Success, result.Message);
        if (result.Success)
        {
            SupportSubject = string.Empty;
            SupportMessage = string.Empty;
        }
    }

    private void SetStatus(bool success, string message)
    {
        IsStatusSuccess = success;
        StatusMessage = message;
    }

    private void MoveSlide(int offset)
    {
        if (Snapshot.Slides.Count == 0)
        {
            return;
        }

        currentSlideIndex = (currentSlideIndex + offset + Snapshot.Slides.Count) % Snapshot.Slides.Count;
        RaiseSlideProperties();
    }

    private void OpenCurrentSlideLink()
    {
        LauncherSlide? slide = CurrentSlide;
        if (slide is null)
        {
            SetStatus(false, "Gösterilecek paylaşım bulunamadı.");
            return;
        }

        LauncherActionResult result = externalLinkService.Open(slide.TargetUrl);
        SetStatus(result.Success, result.Message);
    }

    private void RaiseSlideProperties()
    {
        RaisePropertyChanged(nameof(CurrentSlide));
        RaisePropertyChanged(nameof(CurrentSlideNumber));
        RaisePropertyChanged(nameof(SlideCount));
    }

    private void ShowAuthenticationMode(bool registerMode)
    {
        if (isRegisterMode == registerMode)
        {
            return;
        }

        isRegisterMode = registerMode;
        SetAuthenticationMessage(false, registerMode
            ? "Yeni PalTR hesabını oluştur."
            : "PalTR hesabınla devam et.");
        RaisePropertyChanged(nameof(IsLoginMode));
        RaisePropertyChanged(nameof(IsRegisterMode));
    }

    private void Login()
    {
        string identifier = LoginIdentifier.Trim();
        if (identifier.Length < 3)
        {
            SetAuthenticationMessage(true, "Kullanıcı adı veya e-posta alanını doldur.");
            return;
        }

        if (LoginPassword.Length < 6)
        {
            SetAuthenticationMessage(true, "Parola en az 6 karakter olmalı.");
            return;
        }

        signedInAccountName = identifier.Contains('@')
            ? identifier.Split('@', 2)[0]
            : identifier;
        CompleteAuthentication("Demo oturumu açıldı. Gerçek hesap servisi henüz bağlı değil.");
    }

    private void Register()
    {
        string displayName = RegisterDisplayName.Trim();
        string email = RegisterEmail.Trim();
        if (displayName.Length < 3)
        {
            SetAuthenticationMessage(true, "Oyuncu adı en az 3 karakter olmalı.");
            return;
        }

        if (!email.Contains('@') || email.StartsWith('@') || email.EndsWith('@'))
        {
            SetAuthenticationMessage(true, "Geçerli bir e-posta adresi gir.");
            return;
        }

        if (RegisterPassword.Length < 8)
        {
            SetAuthenticationMessage(true, "Yeni parola en az 8 karakter olmalı.");
            return;
        }

        if (RegisterPassword != RegisterPasswordConfirmation)
        {
            SetAuthenticationMessage(true, "Parola alanları birbiriyle eşleşmiyor.");
            return;
        }

        if (!HasAcceptedTerms)
        {
            SetAuthenticationMessage(true, "Devam etmek için kullanım koşullarını kabul et.");
            return;
        }

        signedInAccountName = displayName;
        CompleteAuthentication("Demo hesabı hazırlandı. Bilgiler sunucuya kaydedilmedi.");
    }

    private void CompleteAuthentication(string message)
    {
        isAuthenticated = true;
        LoginPassword = string.Empty;
        RegisterPassword = string.Empty;
        RegisterPasswordConfirmation = string.Empty;
        RaisePropertyChanged(nameof(IsLauncherVisible));
        RaisePropertyChanged(nameof(IsAuthenticationVisible));
        RaisePropertyChanged(nameof(AccountDisplayName));
        SetStatus(true, message);
    }

    private void Logout()
    {
        isAuthenticated = false;
        signedInAccountName = string.Empty;
        SelectedPage = "Ana Sayfa";
        SetAuthenticationMessage(false, "Oturum kapatıldı. Yeniden giriş yapabilirsin.");
        RaisePropertyChanged(nameof(IsLauncherVisible));
        RaisePropertyChanged(nameof(IsAuthenticationVisible));
        RaisePropertyChanged(nameof(AccountDisplayName));
    }

    private void SetAuthenticationMessage(bool isError, string message)
    {
        IsAuthenticationMessageError = isError;
        AuthenticationMessage = message;
    }
}

internal static class CollectionExtensions
{
    public static void ReplaceWith<T>(this ObservableCollection<T> collection, IEnumerable<T> items)
    {
        collection.Clear();
        foreach (T item in items)
        {
            collection.Add(item);
        }
    }
}

public sealed class RelayCommand : ICommand
{
    private readonly Action<object?> execute;

    public RelayCommand(Action<object?> execute) => this.execute = execute;

    public event EventHandler? CanExecuteChanged
    {
        add { }
        remove { }
    }

    public bool CanExecute(object? parameter) => true;
    public void Execute(object? parameter) => execute(parameter);
}
