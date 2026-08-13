using System.Collections.ObjectModel;
using System.Windows.Input;
using PalTRLauncher.Models;
using PalTRLauncher.Services;

namespace PalTRLauncher.ViewModels;

public sealed class LauncherViewModel : ObservableObject
{
    public const string DemoUsername = "Herakles";
    public const string DemoPassword = "PalTRDemo2026!";

    private readonly ILauncherService service;
    private readonly IExternalLinkService externalLinkService;
    private readonly IRememberedSessionStore rememberedSessionStore;
    private readonly ISteamAccountLinkService steamAccountLinkService;
    private readonly IInstallationService installationService;
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
    private string registerUsername = string.Empty;
    private string registerEmail = string.Empty;
    private string registerPassword = string.Empty;
    private string registerPasswordConfirmation = string.Empty;
    private bool hasAcceptedTerms;
    private bool rememberMe = true;
    private string authenticationMessage = "PalTR hesabınla devam et.";
    private bool isAuthenticationMessageError;
    private string signedInAccountName = string.Empty;
    private SteamAccountLinkSnapshot steamAccountLink = SteamAccountLinkSnapshot.BackendUnavailable;
    private InstallationSnapshot installation = InstallationSnapshot.Checking;

    public LauncherViewModel(
        ILauncherService service,
        IExternalLinkService externalLinkService,
        IRememberedSessionStore rememberedSessionStore,
        ISteamAccountLinkService steamAccountLinkService,
        IInstallationService installationService)
    {
        this.service = service;
        this.externalLinkService = externalLinkService;
        this.rememberedSessionStore = rememberedSessionStore;
        this.steamAccountLinkService = steamAccountLinkService;
        this.installationService = installationService;
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
        RefreshSteamLinkCommand = new AsyncRelayCommand(RefreshSteamLinkAsync);
        BeginSteamLinkCommand = new AsyncRelayCommand(BeginSteamLinkAsync);
        UnlinkSteamCommand = new AsyncRelayCommand(UnlinkSteamAsync);
        InstallOrRepairCommand = new AsyncRelayCommand(InstallOrRepairAsync);
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

    public SteamAccountLinkSnapshot SteamAccountLink
    {
        get => steamAccountLink;
        private set
        {
            if (SetProperty(ref steamAccountLink, value))
            {
                RaisePropertyChanged(nameof(IsSteamLinked));
                RaisePropertyChanged(nameof(IsSteamUnlinked));
                RaisePropertyChanged(nameof(HasSteamIdentity));
            }
        }
    }

    public bool IsSteamLinked => SteamAccountLink.State == SteamAccountLinkState.Linked;
    public bool IsSteamUnlinked => !IsSteamLinked;
    public bool HasSteamIdentity => !string.IsNullOrWhiteSpace(SteamAccountLink.SteamId64);

    public InstallationSnapshot Installation
    {
        get => installation;
        private set
        {
            if (SetProperty(ref installation, value))
            {
                RaisePropertyChanged(nameof(IsLauncherVisible));
                RaisePropertyChanged(nameof(IsAuthenticationVisible));
                RaisePropertyChanged(nameof(CanInstallOrRepair));
                RaisePropertyChanged(nameof(InstallationActionText));
            }
        }
    }

    public bool CanInstallOrRepair => Installation.CanInstall || Installation.CanRetry;

    public string InstallationActionText => Installation.State switch
    {
        InstallationState.Ready => "GÜNCEL",
        InstallationState.Checking => "KONTROL EDİLİYOR",
        _ => "GÜNCELLE"
    };

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

    public string RegisterUsername
    {
        get => registerUsername;
        set => SetProperty(ref registerUsername, value);
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

    public bool RememberMe
    {
        get => rememberMe;
        set => SetProperty(ref rememberMe, value);
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
    public ICommand RefreshSteamLinkCommand { get; }
    public ICommand BeginSteamLinkCommand { get; }
    public ICommand UnlinkSteamCommand { get; }
    public ICommand InstallOrRepairCommand { get; }

    public async Task InitializeAsync()
    {
        Installation = await installationService.InspectAsync();
        await RefreshAsync();
        string? rememberedAccountName = rememberedSessionStore.LoadAccountName();
        if (rememberedAccountName is null)
        {
            return;
        }

        signedInAccountName = rememberedAccountName;
        isAuthenticated = true;
        RaisePropertyChanged(nameof(IsLauncherVisible));
        RaisePropertyChanged(nameof(IsAuthenticationVisible));
        RaisePropertyChanged(nameof(AccountDisplayName));
        SetStatus(true, "Hatırlanan PalTR oturumu açıldı.");
        await RefreshSteamLinkAsync();
    }

    private async Task InstallOrRepairAsync()
    {
        Installation = InstallationSnapshot.Checking;
        InstallationActionResult result = await installationService.InstallOrRepairAsync();
        Installation = result.Snapshot;
        if (!result.Success)
        {
            return;
        }

        await RefreshAsync();
        string? rememberedAccountName = rememberedSessionStore.LoadAccountName();
        if (rememberedAccountName is null)
        {
            return;
        }

        signedInAccountName = rememberedAccountName;
        isAuthenticated = true;
        RaisePropertyChanged(nameof(IsLauncherVisible));
        RaisePropertyChanged(nameof(IsAuthenticationVisible));
        RaisePropertyChanged(nameof(AccountDisplayName));
        await RefreshSteamLinkAsync();
    }

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
        Installation = await installationService.InspectAsync();
        if (!Installation.IsReady)
        {
            SetStatus(false, $"Sunucuya katılmadan önce PalTR kurulumu gerekli: {Installation.Detail}");
            return;
        }

        LauncherActionResult result = await service.PrepareDirectJoinAsync();
        SetStatus(result.Success, result.Message);
    }

    private async Task CheckUpdatesAsync()
    {
        Installation = await installationService.InspectAsync();
        SetStatus(Installation.IsReady, $"{Installation.Title}: {Installation.Detail}");
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

    private async Task RefreshSteamLinkAsync()
    {
        try
        {
            SteamAccountLink = await steamAccountLinkService.GetStatusAsync();
        }
        catch (Exception exception)
        {
            SetSteamLinkFailure("Steam bağlantı durumu alınamadı.", exception);
        }
    }

    private async Task BeginSteamLinkAsync()
    {
        SteamAccountLinkActionResult result;
        try
        {
            result = await steamAccountLinkService.BeginLinkAsync();
            SteamAccountLink = result.Snapshot;
            SetStatus(result.Success, result.Message);
        }
        catch (Exception exception)
        {
            SetSteamLinkFailure("Steam bağlantısı başlatılamadı.", exception);
            return;
        }

        if (!result.Success || string.IsNullOrWhiteSpace(result.AuthorizationUrl))
        {
            return;
        }

        LauncherActionResult openResult = externalLinkService.Open(result.AuthorizationUrl);
        SetStatus(openResult.Success, openResult.Success
            ? "Steam doğrulama sayfası açıldı. İşlemi tamamladıktan sonra durumu yenile."
            : openResult.Message);
    }

    private async Task UnlinkSteamAsync()
    {
        try
        {
            SteamAccountLinkActionResult result = await steamAccountLinkService.UnlinkAsync();
            SteamAccountLink = result.Snapshot;
            SetStatus(result.Success, result.Message);
        }
        catch (Exception exception)
        {
            SetSteamLinkFailure("Steam bağlantısı kaldırılamadı.", exception);
        }
    }

    private void SetSteamLinkFailure(string message, Exception exception)
    {
        SteamAccountLink = new SteamAccountLinkSnapshot(
            SteamAccountLinkState.Failed,
            "Bağlantı hatası",
            message);
        SetStatus(false, $"{message} {exception.Message}");
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
            SetAuthenticationMessage(true, "Kullanıcı adı alanını doldur.");
            return;
        }

        if (!string.Equals(identifier, DemoUsername, StringComparison.OrdinalIgnoreCase) ||
            LoginPassword != DemoPassword)
        {
            SetAuthenticationMessage(true, "Kullanıcı adı veya parola hatalı. Demo hesap bilgilerini kullan.");
            return;
        }

        signedInAccountName = DemoUsername;
        CompleteAuthentication(
            "Demo oturumu açıldı. Gerçek hesap servisi henüz bağlı değil.",
            RememberMe);
    }

    private void Register()
    {
        string username = RegisterUsername.Trim();
        string email = RegisterEmail.Trim();
        if (username.Length < 3)
        {
            SetAuthenticationMessage(true, "Kullanıcı adı en az 3 karakter olmalı.");
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

        signedInAccountName = username;
        CompleteAuthentication("Demo hesabı hazırlandı. Bilgiler sunucuya kaydedilmedi.", true);
    }

    private void CompleteAuthentication(string message, bool persistSession)
    {
        isAuthenticated = true;
        if (persistSession)
        {
            rememberedSessionStore.SaveAccountName(signedInAccountName);
        }
        else
        {
            rememberedSessionStore.Clear();
        }
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
        rememberedSessionStore.Clear();
        isAuthenticated = false;
        signedInAccountName = string.Empty;
        SteamAccountLink = SteamAccountLinkSnapshot.BackendUnavailable;
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
