using CommunityToolkit.Mvvm.ComponentModel;
using NeeLaboratory.ComponentModel;
using NeeView.Windows;
using System.Windows.Controls;

namespace NeeView
{
    /// <summary>
    /// MenuBar : Model
    /// </summary>
    public class MenuBar : ObservableObject
    {
        private readonly WindowStateManager _windowStateManager;
        private bool _isMaximizeButtonMouseOver;


        public MenuBar(WindowStateManager windowStateManager)
        {
            _windowStateManager = windowStateManager;

            NeeView.MainMenu.Current.SubscribePropertyChanged(nameof(NeeView.MainMenu.Menu),
                (s, e) => OnPropertyChanged(nameof(MainMenu)));
        }


        public Menu? MainMenu => NeeView.MainMenu.Current.Menu;

        public WindowStateManager WindowStateManager => _windowStateManager;

        public bool IsMaximizeButtonMouseOver => _isMaximizeButtonMouseOver;


        public void SetMaximizeButtonMouseOver(bool isOver)
        {
            _isMaximizeButtonMouseOver = isOver;
        }
    }
}
