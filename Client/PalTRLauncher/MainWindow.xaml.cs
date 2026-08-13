using System.Windows;
using System.Windows.Input;
using System.Windows.Media;
using PalTRLauncher.Services;
using PalTRLauncher.ViewModels;

namespace PalTRLauncher;

public partial class MainWindow : Window
{
    private readonly LauncherViewModel viewModel;

    public MainWindow()
    {
        InitializeComponent();
        viewModel = new LauncherViewModel(
            new DemoLauncherService(),
            new SystemExternalLinkService());
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
}
