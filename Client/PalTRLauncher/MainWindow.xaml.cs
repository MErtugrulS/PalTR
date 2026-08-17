using System.Windows;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Controls;
using PalTRLauncher.Services;
using PalTRLauncher.ViewModels;

namespace PalTRLauncher;

public partial class MainWindow : Window
{
    private readonly LauncherViewModel viewModel;

    public MainWindow()
    {
        InitializeComponent();
        PalworldInstallLocator installLocator = new();
        LocalPalTRInstallationService embeddedInstaller = new(installLocator);
        viewModel = new LauncherViewModel(
            new DemoLauncherService(),
            new DemoAccountService(new HttpAccountService()),
            new SystemExternalLinkService(),
            new LocalRememberedSessionStore(),
            new UnavailableSteamAccountLinkService(),
            new GitHubPalTRInstallationService(installLocator, embeddedInstaller));
        DataContext = viewModel;
        Loaded += async (_, _) => await viewModel.InitializeAsync();
    }

    private void TitleBar_OnMouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (e.ButtonState == MouseButtonState.Pressed)
        {
            DragMove();
        }
    }

    private void Minimize_OnClick(object sender, RoutedEventArgs e)
        => WindowState = WindowState.Minimized;

    private void Close_OnClick(object sender, RoutedEventArgs e)
        => Close();

    private void Slider_OnMouseLeftButtonUp(object sender, MouseButtonEventArgs e)
    {
        DependencyObject? source = e.OriginalSource as DependencyObject;
        while (source is not null)
        {
            if (source is System.Windows.Controls.Button)
            {
                return;
            }
            source = VisualTreeHelper.GetParent(source);
        }

        if (viewModel.OpenSlideLinkCommand.CanExecute(null))
        {
            viewModel.OpenSlideLinkCommand.Execute(null);
        }
    }

    private void LoginPassword_OnPasswordChanged(object sender, RoutedEventArgs e)
        => viewModel.LoginPassword = ((PasswordBox)sender).Password;

    private void RegisterPassword_OnPasswordChanged(object sender, RoutedEventArgs e)
        => viewModel.RegisterPassword = ((PasswordBox)sender).Password;

    private void RegisterPasswordConfirmation_OnPasswordChanged(object sender, RoutedEventArgs e)
        => viewModel.RegisterPasswordConfirmation = ((PasswordBox)sender).Password;

    private async void Login_OnClick(object sender, RoutedEventArgs e)
    {
        await viewModel.LoginAsync();
        ClearAuthenticationPasswordsWhenComplete();
    }

    private async void Register_OnClick(object sender, RoutedEventArgs e)
    {
        await viewModel.RegisterAsync();
        ClearAuthenticationPasswordsWhenComplete();
    }

    private void ClearAuthenticationPasswordsWhenComplete()
    {
        LoginPasswordBox.Clear();
        RegisterPasswordBox.Clear();
        RegisterPasswordConfirmationBox.Clear();
    }
}
