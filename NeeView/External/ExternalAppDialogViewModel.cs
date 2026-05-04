using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using NeeLaboratory;
using System.Collections.ObjectModel;
using System.Linq;
using System.Windows;

namespace NeeView
{
    public partial class ExternalAppDialogViewModel : ObservableObject
    {
        public ObservableCollection<ExternalApp> _items;
        private int _selectedIndex = -1;


        public ExternalAppDialogViewModel()
        {
            _items = new ObservableCollection<ExternalApp>(Config.Current.System.ExternalAppCollection);
        }


        public Window? Owner { get; set; }


        public ObservableCollection<ExternalApp> Items
        {
            get { return _items; }
            set { SetProperty(ref _items, value); }
        }

        public int SelectedIndex
        {
            get { return _selectedIndex; }
            set
            {
                if (SetProperty(ref _selectedIndex, value))
                {
                    EditCommand.NotifyCanExecuteChanged();
                    DeleteCommand.NotifyCanExecuteChanged();
                    MoveUpCommand.NotifyCanExecuteChanged();
                    MoveDownCommand.NotifyCanExecuteChanged();
                }
            }
        }


        [RelayCommand]
        private void Add()
        {
            CallEditDialog(-1, new ExternalApp());
        }

        private bool CanEdit()
        {
            return Items.Any() && _selectedIndex >= 0;
        }

        [RelayCommand(CanExecute = nameof(CanEdit))]
        private void Edit()
        {
            if (_selectedIndex < 0) return;

            var index = _selectedIndex;
            var item = Items[_selectedIndex];

            CallEditDialog(index, item);
        }

        private void CallEditDialog(int index, ExternalApp source)
        {
            var item = (ExternalApp)source.Clone();

            var dialog = new ExternalAppEditDialog(item);
            dialog.Owner = Owner;
            dialog.WindowStartupLocation = WindowStartupLocation.CenterOwner;
            var result = dialog.ShowDialog();

            if (result == true)
            {
                if (index >= 0)
                {
                    Items[index] = item;
                }
                else
                {
                    Items.Add(item);
                }
            }
        }

        public void Add(string path)
        {
            Items.Add(new ExternalApp() { Command = path });
        }

        [RelayCommand(CanExecute = nameof(CanEdit))]
        private void Delete()
        {
            if (_selectedIndex < 0) return;

            var index = _selectedIndex;
            Items.RemoveAt(_selectedIndex);
            SelectedIndex = MathUtility.Clamp(index, -1, Items.Count - 1);
        }

        private bool CanMoveUp()
        {
            return _selectedIndex > 0;
        }

        [RelayCommand(CanExecute = nameof(CanMoveUp))]
        private void MoveUp()
        {
            if (!CanMoveUp()) return;

            Items.Move(_selectedIndex, _selectedIndex - 1);
        }

        private bool CanMoveDown()
        {
            return _selectedIndex >= 0 && _selectedIndex < Items.Count - 1;
        }

        [RelayCommand(CanExecute = nameof(CanMoveDown))]
        private void MoveDown()
        {
            if (!CanMoveDown()) return;

            Items.Move(_selectedIndex, _selectedIndex + 1);
        }


        public void Decide()
        {
            Config.Current.System.ExternalAppCollection = new ExternalAppCollection(_items);
        }
    }
}
