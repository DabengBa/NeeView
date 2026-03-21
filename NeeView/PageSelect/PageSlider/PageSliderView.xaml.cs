using System;
using System.ComponentModel;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;

namespace NeeView
{
    /// <summary>
    /// PageSliderView.xaml の相互作用ロジック
    /// </summary>
    public partial class PageSliderView : UserControl
    {
        private PageSliderViewModel? _vm;
        private bool _isPageMarkersQueued;
        private bool _isPageMarkersInitialized;


        public PageSlider Source
        {
            get { return (PageSlider)GetValue(SourceProperty); }
            set { SetValue(SourceProperty, value); }
        }

        public static readonly DependencyProperty SourceProperty =
            DependencyProperty.Register("Source", typeof(PageSlider), typeof(PageSliderView), new PropertyMetadata(null, Source_Changed));

        private static void Source_Changed(DependencyObject d, DependencyPropertyChangedEventArgs e)
        {
            if (d is PageSliderView control)
            {
                control.Initialize();
            }
        }


        public bool IsBackgroundOpacityEnabled
        {
            get { return (bool)GetValue(IsBackgroundOpacityEnabledProperty); }
            set { SetValue(IsBackgroundOpacityEnabledProperty, value); }
        }

        public static readonly DependencyProperty IsBackgroundOpacityEnabledProperty =
            DependencyProperty.Register("IsBackgroundOpacityEnabled", typeof(bool), typeof(PageSliderView), new PropertyMetadata(false));


        public bool IsBorderVisible
        {
            get { return (bool)GetValue(IsBorderVisibleProperty); }
            set { SetValue(IsBorderVisibleProperty, value); }
        }

        public static readonly DependencyProperty IsBorderVisibleProperty =
            DependencyProperty.Register("IsBorderVisible", typeof(bool), typeof(PageSliderView), new PropertyMetadata(false));


        public PageSliderView()
        {
            using var startupScope = App.TryTraceStartupScope("MainWindow.InitializeComponent.PageSliderView");
            InitializeComponent();

            this.Loaded += PageSliderView_Loaded;
            Config.Current.Slider.AddPropertyChanged(nameof(SliderConfig.IsVisiblePlaylistMark), SliderConfig_IsVisiblePlaylistMarkChanged);
        }


        public void Initialize()
        {
            using var startupScope = App.TryTraceStartupScope("MainWindow.Initialize.ViewSources.PageSliderView.Initialize");
            if (this.Source == null) return;

            using (App.TryTraceStartupScope("MainWindow.Initialize.ViewSources.PageSliderView.Initialize.ViewModel.New"))
            {
                _vm = new PageSliderViewModel(this.Source);
            }

            using (App.TryTraceStartupScope("MainWindow.Initialize.ViewSources.PageSliderView.Initialize.ViewModel.AssignDataContext"))
            {
                this.Root.DataContext = _vm;
            }

            using (App.TryTraceStartupScope("MainWindow.Initialize.ViewSources.PageSliderView.Initialize.PageMarkers.Queue"))
            {
                QueuePageMarkersInitialization();
            }
        }


        private void PageSliderView_Loaded(object sender, RoutedEventArgs e)
        {
            QueuePageMarkersInitialization();
        }

        private void SliderConfig_IsVisiblePlaylistMarkChanged(object? sender, PropertyChangedEventArgs e)
        {
            QueuePageMarkersInitialization();
        }

        private void QueuePageMarkersInitialization()
        {
            if (_isPageMarkersInitialized || _isPageMarkersQueued || this.Source is null || !this.IsLoaded || !Config.Current.Slider.IsVisiblePlaylistMark)
            {
                return;
            }

            _isPageMarkersQueued = true;
            this.Dispatcher.BeginInvoke(() =>
            {
                _isPageMarkersQueued = false;

                if (_isPageMarkersInitialized || this.Source is null || !Config.Current.Slider.IsVisiblePlaylistMark)
                {
                    return;
                }

                using var startupScope = App.TryTraceStartupScope("MainWindow.DeferredWarmup.PageSliderView.PageMarkers.Source");
                this.PageMarkersView.Source = this.Source.PageMarkers;
                _isPageMarkersInitialized = true;
            }, System.Windows.Threading.DispatcherPriority.Background);
        }


        /// <summary>
        /// スライダーエリアでのマウスホイール操作
        /// </summary>
        /// <param name="sender"></param>
        /// <param name="e"></param>
        private void SliderArea_MouseWheel(object? sender, MouseWheelEventArgs e)
        {
            if (_vm is null) return;

            _vm.MouseWheel(sender, e);
        }

        private void PageSlider_PreviewMouseLeftButtonDown(object? sender, MouseButtonEventArgs e)
        {
            // 操作するときはメインビューにフォーカスを移動する
            MainWindowModel.Current.FocusMainView();
        }

        private void PageSlider_PreviewMouseLeftButtonUp(object? sender, MouseButtonEventArgs e)
        {
            if (_vm is null) return;

            _vm.Jump(false);
        }

        private void PageSliderTextBox_ValueChanged(object? sender, EventArgs e)
        {
            if (_vm is null) return;

            _vm.Jump(true);
        }

        // テキストボックス入力時に単キーのショートカットを無効にする
        private void PageSliderTextBox_KeyDown(object? sender, KeyEventArgs e)
        {
            // 単キーのショートカット無効
            KeyExGesture.AddFilter(KeyExGestureFilter.All);
            //e.Handled = true;
        }

    }
}

