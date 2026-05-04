using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using System.Windows;
using System.Windows.Input;

namespace NeeView.Setting
{
    /// <summary>
    /// CommandResetWindow.xaml の相互作用ロジック
    /// </summary>
    public partial class CommandResetWindow : Window
    {
        private readonly CommandResetWindowViewModel _vm;


        public CommandResetWindow()
        {
            InitializeComponent();

            _vm = new CommandResetWindowViewModel();
            this.DataContext = _vm;

            this.Loaded += CommandResetWindow_Loaded;
            this.KeyDown += CommandResetWindow_KeyDown;
        }


        public InputScheme InputScheme => _vm.InputScheme;


        private void CommandResetWindow_KeyDown(object sender, KeyEventArgs e)
        {
            if (e.Key == Key.Escape && Keyboard.Modifiers == ModifierKeys.None)
            {
                this.Close();
                e.Handled = true;
            }
        }

        private void CommandResetWindow_Loaded(object sender, RoutedEventArgs e)
        {
            this.OkButton.Focus();
        }
    }


    public partial class CommandResetWindowViewModel : ObservableObject
    {
        private InputScheme _inputScheme;

        public InputScheme InputScheme
        {
            get { return _inputScheme; }
            set { SetProperty(ref _inputScheme, value); }
        }


        [RelayCommand]
        private void Ok(Window? window)
        {
            if (window is null) return;

            window.DialogResult = true;
            window.Close();
        }

        [RelayCommand]
        private void Cancel(Window? window)
        {
            if (window is null) return;

            window.DialogResult = false;
            window.Close();
        }
    }
}
