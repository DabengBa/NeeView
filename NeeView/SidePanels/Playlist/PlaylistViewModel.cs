using CommunityToolkit.Mvvm.Input;
using NeeLaboratory.ComponentModel;
using NeeView.Properties;
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Threading.Tasks;
using System.Windows.Controls;
using System.Windows.Data;

namespace NeeView
{
    public partial class PlaylistViewModel : BindableBase
    {
        private readonly PlaylistHub _model;


        public PlaylistViewModel(PlaylistHub model)
        {
            _model = model;

            MoreMenuDescription = new PlaylistMoreMenuDescription(this);

            _model.AddPropertyChanged(nameof(_model.PlaylistFiles), Model_PlaylistFilesChanged);
            _model.AddPropertyChanged(nameof(_model.SelectedItem), Model_SelectedItemChanged);
            _model.AddPropertyChanged(nameof(_model.FilterMessage), (s, e) => RaisePropertyChanged(nameof(FilterMessage)));
        }


        public void UpdatePlaylistCollection()
        {
            _model.UpdatePlaylistCollection();
        }


        public EventHandler? RenameRequest;


        public List<object> PlaylistFiles
        {
            get => _model.PlaylistFiles;
        }

        public string SelectedItem
        {
            get => _model.SelectedItem;
            set => _model.SelectedItem = value;
        }

        public string? FilterMessage
        {
            get => _model.FilterMessage;
        }



        private void Model_PlaylistFilesChanged(object? sender, PropertyChangedEventArgs e)
        {
            RaisePropertyChanged(nameof(PlaylistFiles));
        }

        private void Model_SelectedItemChanged(object? sender, PropertyChangedEventArgs e)
        {
            RaisePropertyChanged(nameof(SelectedItem));
            DeleteCommand.NotifyCanExecuteChanged();
            RenameCommand.NotifyCanExecuteChanged();
        }



        #region MoreMenu

        public PlaylistMoreMenuDescription MoreMenuDescription { get; }

        public class PlaylistMoreMenuDescription : ItemsListMoreMenuDescription
        {
            private readonly PlaylistViewModel _vm;

            public PlaylistMoreMenuDescription(PlaylistViewModel vm)
            {
                _vm = vm;
            }

            public override ContextMenu Create()
            {
                var menu = new ContextMenu();
                menu.Items.Add(CreateListItemStyleMenuItem(TextResources.GetString("Word.StyleList"), PanelListItemStyle.Normal));
                menu.Items.Add(CreateListItemStyleMenuItem(TextResources.GetString("Word.StyleContent"), PanelListItemStyle.Content));
                menu.Items.Add(CreateListItemStyleMenuItem(TextResources.GetString("Word.StyleBanner"), PanelListItemStyle.Banner));
                menu.Items.Add(CreateListItemStyleMenuItem(TextResources.GetString("Word.StyleThumbnail"), PanelListItemStyle.Thumbnail));
                menu.Items.Add(new Separator());
                menu.Items.Add(CreateCheckMenuItem(TextResources.GetString("Menu.GroupBy"), new Binding(nameof(PlaylistConfig.IsGroupBy)) { Source = Config.Current.Playlist }));
                menu.Items.Add(CreateCheckMenuItem(TextResources.GetString("Playlist.MoreMenu.CurrentBook"), new Binding(nameof(PlaylistConfig.IsCurrentBookFilterEnabled)) { Source = Config.Current.Playlist }));
                menu.Items.Add(new Separator());
                menu.Items.Add(CreateCommandMenuItem(TextResources.GetString("Playlist.MoreMenu.New"), _vm.CreateNewCommand));
                menu.Items.Add(CreateCommandMenuItem(TextResources.GetString("Playlist.MoreMenu.Open"), _vm.OpenCommand));
                menu.Items.Add(CreateCommandMenuItem(TextResources.GetString("Playlist.MoreMenu.Delete"), _vm.DeleteCommand));
                menu.Items.Add(CreateCommandMenuItem(TextResources.GetString("Playlist.MoreMenu.Rename"), _vm.RenameCommand));
                menu.Items.Add(new Separator());
                menu.Items.Add(CreateCommandMenuItem(TextResources.GetString("Playlist.MoreMenu.DeleteInvalid"), _vm.DeleteInvalidItemsCommand));
                menu.Items.Add(CreateCommandMenuItem(TextResources.GetString("Playlist.MoreMenu.Sort"), _vm.SortItemsCommand));
                menu.Items.Add(new Separator());
                menu.Items.Add(CreateCommandMenuItem(TextResources.GetString("Playlist.MoreMenu.OpenAsBook"), _vm.OpenAsBookCommand));

                return menu;
            }

            private MenuItem CreateListItemStyleMenuItem(string header, PanelListItemStyle style)
            {
                return CreateListItemStyleMenuItem(header, _vm.SetListItemStyleCommand, style, Config.Current.Playlist);
            }
        }

        #endregion

        #region Commands


        [RelayCommand]
        private void SetListItemStyle(PanelListItemStyle style)
        {
            Config.Current.Playlist.PanelListItemStyle = style;
        }

        [RelayCommand]
        private void CreateNew()
        {
            _model.CreateNew();
        }

        [RelayCommand]
        private void Open()
        {
            _model.Open();
        }

        private bool CanDelete()
        {
            return _model.CanDelete();
        }

        [RelayCommand(CanExecute = nameof(CanDelete))]
        private async Task Delete()
        {
            await _model.DeleteAsync();
        }

        private bool CanRename()
        {
            return _model.CanRename();
        }

        [RelayCommand(CanExecute = nameof(CanRename))]
        private void Rename()
        {
            RenameRequest?.Invoke(this, EventArgs.Empty);
        }

        public bool Rename(string newName)
        {
            return _model.Rename(newName);
        }

        [RelayCommand]
        private void OpenAsBook()
        {
            _model.OpenAsBook();
        }

        [RelayCommand]
        private async Task DeleteInvalidItems()
        {
            await _model.DeleteInvalidItemsAsync();
        }

        [RelayCommand]
        private void SortItems()
        {
            var dialog = new MessageDialog(TextResources.GetString("PlaylistSortDialog.Title"), TextResources.GetString("PlaylistSortDialog.Message"));
            dialog.Commands.AddRange(UICommands.OKCancel);
            var result = dialog.ShowDialog();
            if (!result.IsPossible)
            {
                return;
            }

            _model.SortItems();
        }

        #endregion
    }
}
