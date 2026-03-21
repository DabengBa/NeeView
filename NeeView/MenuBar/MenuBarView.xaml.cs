using NeeView.Windows;
using NeeView.Windows.Controls;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Shell;
using System.Windows.Threading;

namespace NeeView
{
    /// <summary>
    /// MenuBar : View
    /// </summary>
    public partial class MenuBarView : UserControl
    {
        private static readonly Brush AlphaWatermarkBackground = CreateFrozenBrush(Color.FromRgb(0xF3, 0xBC, 0x2D));
        private static readonly Brush AlphaWatermarkForeground = CreateFrozenBrush(Color.FromRgb(0x20, 0x20, 0x20));
        private static readonly Brush BetaWatermarkBackground = CreateFrozenBrush(Color.FromRgb(0x2E, 0x69, 0xD1));

        private MenuBarViewModel? _vm;
        private WindowCaptionButtons? _windowCaptionButtons;
        private bool _isWindowCaptionButtonsInitializationQueued;


        public MenuBarView()
        {
            using var startupScope = App.TryTraceStartupScope("MainWindow.InitializeComponent.MenuBarView");
            InitializeComponent();

            this.Watermark.Visibility = Environment.Watermark ? Visibility.Visible : Visibility.Collapsed;

            if (Environment.IsDevPackage)
            {
                this.Watermark.Background = Brushes.DimGray;
                this.WatermarkText.Foreground = Brushes.White;
                this.WatermarkText.Text = "Dev";
            }
            else if (Environment.IsAlphaRelease)
            {
                this.Watermark.Background = AlphaWatermarkBackground;
                this.WatermarkText.Foreground = AlphaWatermarkForeground;
                this.WatermarkText.Text = Environment.ReleaseType + Environment.ReleaseNumber;
            }
            else if (Environment.IsBetaRelease)
            {
                this.Watermark.Background = BetaWatermarkBackground;
                this.WatermarkText.Foreground = Brushes.White;
                this.WatermarkText.Text = Environment.ReleaseType + Environment.ReleaseNumber;
            }
            else
            {
                this.Watermark.Background = Brushes.DimGray;
                this.WatermarkText.Foreground = Brushes.White;
                this.WatermarkText.Text = Environment.PackageType;
            }

            this.MainMenuJoint.MouseRightButtonUp += (s, e) => e.Handled = true;
            this.MouseRightButtonUp += MenuBarView_MouseRightButtonUp;
            this.Loaded += MenuBarView_Loaded;
        }


        public MenuBar Source
        {
            get { return (MenuBar)GetValue(SourceProperty); }
            set { SetValue(SourceProperty, value); }
        }

        public static readonly DependencyProperty SourceProperty =
            DependencyProperty.Register("Source", typeof(MenuBar), typeof(MenuBarView), new PropertyMetadata(null, SourcePropertyChanged));

        private static void SourcePropertyChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
        {
            (d as MenuBarView)?.Initialize();
        }


        public void Initialize()
        {
            using var startupScope = App.TryTraceStartupScope("MainWindow.Initialize.ViewSources.MenuBarView.Initialize");
            _vm = new MenuBarViewModel(this.Source, this);
            this.Root.DataContext = _vm;
            QueueWindowCaptionButtonsInitialization();
        }

        public void UpdateWindowCaptionButtonsStrokeThickness(DpiScale dpi)
        {
            _windowCaptionButtons?.UpdateStrokeThickness(dpi);
        }

        // 単キーのショートカット無効
        private void Control_KeyDown_IgnoreSingleKeyGesture(object sender, KeyEventArgs e)
        {
            KeyExGesture.AddFilter(KeyExGestureFilter.All);
        }

        // システムメニュー表示
        private void MenuBarView_MouseRightButtonUp(object sender, MouseButtonEventArgs e)
        {
            if (_vm is null) return;

            if (_vm.IsCaptionEnabled)
            {
                WindowTools.ShowSystemMenu(Window.GetWindow(this));
                e.Handled = true;
            }
        }

        private void MenuBarView_Loaded(object sender, RoutedEventArgs e)
        {
            QueueWindowCaptionButtonsInitialization();
        }

        private void QueueWindowCaptionButtonsInitialization()
        {
            if (_windowCaptionButtons != null || _isWindowCaptionButtonsInitializationQueued || _vm is null || !this.IsLoaded)
            {
                return;
            }

            _isWindowCaptionButtonsInitializationQueued = true;
            this.Dispatcher.BeginInvoke(() =>
            {
                _isWindowCaptionButtonsInitializationQueued = false;

                if (_windowCaptionButtons != null || _vm is null || !this.IsLoaded)
                {
                    return;
                }

                using var startupScope = App.TryTraceStartupScope("MainWindow.DeferredWarmup.MenuBarView.WindowCaptionButtons");
                _windowCaptionButtons = CreateWindowCaptionButtons();
                this.WindowCaptionButtonsHost.Content = _windowCaptionButtons;
            }, DispatcherPriority.Background);
        }

        private WindowCaptionButtons CreateWindowCaptionButtons()
        {
            var buttons = new WindowCaptionButtons()
            {
                VerticalAlignment = VerticalAlignment.Top,
                MinHeight = 28,
            };
            WindowChrome.SetIsHitTestVisibleInChrome(buttons, false);
            buttons.MouseRightButtonUp += (s, e) => e.Handled = true;

            BindingOperations.SetBinding(
                buttons,
                WindowCaptionButtons.IsMaximizeButtonMouseOverProperty,
                new Binding(nameof(MenuBarViewModel.IsMaximizeButtonMouseOver))
                {
                    Source = _vm,
                    Mode = BindingMode.OneWayToSource,
                });

            return buttons;
        }

        private static Brush CreateFrozenBrush(Color color)
        {
            var brush = new SolidColorBrush(color);
            brush.Freeze();
            return brush;
        }
    }
}
