using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using NeeLaboratory.ComponentModel;
using NeeView.Windows;
using System;
using System.Collections.Generic;
using System.Linq;

namespace NeeView.Setting
{
    public partial class SettingItemFileAssociationGroupViewModel : ObservableObject
    {
        private FileAssociationCategory _category;
        private List<FileAssociationAccessor> _items;
        private bool? _isChecked;
        private DisposableCollection _disposables = new();
        private bool _lockCheckFlag;
        private IHasWindowHandle _window;


        public SettingItemFileAssociationGroupViewModel(FileAssociationAccessorCollection collection, FileAssociationCategory category, IHasWindowHandle window)
        {
            _category = category;
            _items = collection.Where(e => e.Category == category).ToList();
            _window = window;
            UpdateCheckedFlag();
        }


        public string Title => _category.ToAliasName();

        public List<FileAssociationAccessor> Items
        {
            get { return _items; }
            set { SetProperty(ref _items, value); }
        }

        public bool? IsChecked
        {
            get { return _isChecked; }
            set { SetCheckedFlag(value); }
        }


        [RelayCommand]
        void ChangeCategoryIcon()
        {
            var icon = FileAssociationTools.ShowIconDialog(_window.GetWindowHandle(), new FileAssociationIcon(_category));
            if (icon is not null)
            {
                foreach (var item in _items)
                {
                    item.Icon = icon;
                }
            }
        }

        private void SetCheckedFlag(bool? flag)
        {
            if (flag is null) return;

            try
            {
                _lockCheckFlag = true;
                foreach (var item in _items)
                {
                    item.IsEnabled = flag.Value;
                }
            }
            finally
            {
                _lockCheckFlag = false;
            }

            UpdateCheckedFlag();
        }

        private void UpdateCheckedFlag()
        {
            if (_lockCheckFlag) return;

            var enables = _items.Count(e => e.IsEnabled);
            if (enables == 0)
            {
                _isChecked = false;
            }
            else if (enables == _items.Count)
            {
                _isChecked = true;
            }
            else
            {
                _isChecked = null;
            }

            OnPropertyChanged(nameof(IsChecked));
        }

        public void Attach()
        {
            Detach();
            foreach (var item in _items)
            {
                _disposables.Add(item.SubscribePropertyChanged(nameof(item.IsEnabled), (s, e) => UpdateCheckedFlag()));
            }
        }

        public void Detach()
        {
            _disposables.Dispose();
            _disposables.Clear();
        }
    }
}
