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
    }

    public LauncherSnapshot Snapshot { get; private set; } = new();
    public ObservableCollection<LauncherNews> News { get; } = new();
    public ObservableCollection<LauncherNotification> Notifications { get; } = new();
    public ObservableCollection<LauncherTicket> Tickets { get; } = new();

    public LauncherSlide? CurrentSlide
        => Snapshot.Slides.Count == 0 ? null : Snapshot.Slides[currentSlideIndex];

    public int CurrentSlideNumber => Snapshot.Slides.Count == 0 ? 0 : currentSlideIndex + 1;
    public int SlideCount => Snapshot.Slides.Count;

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
                RaisePropertyChanged(nameof(IsAccountPage));
            }
        }
    }

    public bool IsHomePage => SelectedPage == "Ana Sayfa";
    public bool IsNewsPage => SelectedPage == "Haberler";
    public bool IsNotificationsPage => SelectedPage == "Bildirimler";
    public bool IsSupportPage => SelectedPage == "Destek";
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

    public async Task InitializeAsync() => await RefreshAsync();

    private async Task RefreshAsync()
    {
        Snapshot = await service.GetSnapshotAsync();
        News.ReplaceWith(Snapshot.News);
        Notifications.ReplaceWith(Snapshot.Notifications);
        Tickets.ReplaceWith(Snapshot.Tickets);
        RaisePropertyChanged(nameof(Snapshot));
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

        if (string.IsNullOrWhiteSpace(slide.TargetUrl))
        {
            if (slide.Category == "PALTR ANA SUNUCU")
            {
                JoinServerCommand.Execute(null);
                return;
            }

            if (slide.Category == "GÜNCELLEME NOTLARI")
            {
                SelectedPage = "Haberler";
                SetStatus(true, "Launcher haberleri açıldı.");
                return;
            }
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
