using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using NeeLaboratory;
using System.Collections.ObjectModel;
using System.Linq;
using System.Windows;

namespace NeeView
{
    public partial class DestinationFolderDialogViewModel : ObservableObject
    {
        public ObservableCollection<DestinationFolder> _items;
        private int _selectedIndex = -1;


        public DestinationFolderDialogViewModel()
        {
            _items = new ObservableCollection<DestinationFolder>(Config.Current.System.DestinationFolderCollection);
        }


        public Window? Owner { get; set; }


        public ObservableCollection<DestinationFolder> Items
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
            CallEditDialog(-1, new DestinationFolder());
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
            var item = (DestinationFolder)Items[_selectedIndex].Clone();

            CallEditDialog(index, item);
        }

        private void CallEditDialog(int index, DestinationFolder item)
        {
            var dialog = new DestinationFolderEditDialog(item);
            dialog.Owner = Owner;
            dialog.WindowStartupLocation = WindowStartupLocation.CenterOwner;
            var result = dialog.ShowDialog();

            if (result == true && item.IsValid())
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
            Items.Add(new DestinationFolder("", path));
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
            Config.Current.System.DestinationFolderCollection = new DestinationFolderCollection(_items);
        }
    }
}
