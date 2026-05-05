using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using NeeLaboratory.ComponentModel;
using NeeView.Properties;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Controls;
using System.Windows.Data;

namespace NeeView
{
    /// <summary>
    /// 
    /// </summary>
    public partial class HistoryListViewModel : ObservableObject
    {
        private readonly HistoryList _model;


        public HistoryListViewModel(HistoryList model)
        {
            _model = model;
            _model.SubscribePropertyChanged(nameof(HistoryList.FilterPath), (s, e) => OnPropertyChanged(nameof(FilterPath)));

            MoreMenuDescription = new HistoryListMoreMenuDescription(this);
        }


        public HistoryConfig HistoryConfig => Config.Current.History;

        public HistoryList Model => _model;

        public string FilterPath => string.IsNullOrEmpty(_model.FilterPath) ? TextResources.GetString("Word.AllHistory") : _model.FilterPath;

        public SearchBoxModel SearchBoxModel => _model.SearchBoxModel;


        #region MoreMenu

        public HistoryListMoreMenuDescription MoreMenuDescription { get; }

        public class HistoryListMoreMenuDescription : ItemsListMoreMenuDescription
        {
            private readonly HistoryListViewModel _vm;

            public HistoryListMoreMenuDescription(HistoryListViewModel vm)
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
                menu.Items.Add(CreateCheckMenuItem(TextResources.GetString("Menu.GroupBy"), new Binding(nameof(HistoryConfig.IsGroupBy)) { Source = Config.Current.History }));
                menu.Items.Add(CreateCheckMenuItem(TextResources.GetString("History.MoreMenu.IsCurrentFolder"), new Binding(nameof(HistoryConfig.IsCurrentFolder)) { Source = Config.Current.History }));
                menu.Items.Add(new Separator());
                menu.Items.Add(CreateCheckableMenuItem(TextResources.GetString("HistoryConfig.IsVisibleItemsCount"), new Binding(nameof(HistoryConfig.IsVisibleItemsCount)) { Source = Config.Current.History }));
                menu.Items.Add(CreateCheckableMenuItem(TextResources.GetString("HistoryConfig.IsVisibleSearchBox"), new Binding(nameof(HistoryConfig.IsVisibleSearchBox)) { Source = Config.Current.History }));
                menu.Items.Add(new Separator());
                menu.Items.Add(CreateCommandMenuItem(TextResources.GetString("History.MoreMenu.DeleteInvalid"), _vm.RemoveUnlinkedCommand));
                menu.Items.Add(CreateCommandMenuItem(TextResources.GetString("History.MoreMenu.DeleteAll"), _vm.RemoveAllCommand));
                return menu;
            }

            private MenuItem CreateListItemStyleMenuItem(string header, PanelListItemStyle style)
            {
                return CreateListItemStyleMenuItem(header, _vm.SetListItemStyleCommand, style, Config.Current.History);
            }

            private MenuItem CreateCheckableMenuItem(string header, Binding binding)
            {
                var menuItem = new MenuItem()
                {
                    Header = header,
                    IsCheckable = true,
                };
                menuItem.SetBinding(MenuItem.IsCheckedProperty, binding);
                return menuItem;
            }
        }

        #endregion

        #region Commands

        private CancellationTokenSource? _removeUnlinkedCommandCancellationToken;

        [RelayCommand]
        private void SetListItemStyle(PanelListItemStyle style)
        {
            Config.Current.History.PanelListItemStyle = style;
        }

        [RelayCommand]
        private void RemoveAll()
        {
            if (BookHistoryCollection.Current.Items.Any())
            {
                var dialog = new MessageDialog(TextResources.GetString("HistoryDeleteAllDialog.Title"), TextResources.GetString("HistoryDeleteAllDialog.Message"));
                dialog.Commands.Add(UICommands.Delete);
                dialog.Commands.Add(UICommands.Cancel);
                var answer = dialog.ShowDialog();
                if (answer.Command != UICommands.Delete) return;
            }

            BookHistoryCollection.Current.Clear();
        }

        [RelayCommand]
        private async Task RemoveUnlinked()
        {
            // 直前の命令はキャンセル
            _removeUnlinkedCommandCancellationToken?.Cancel();
            _removeUnlinkedCommandCancellationToken = new CancellationTokenSource();
            int count = await BookHistoryCollection.Current.RemoveUnlinkedAsync(_removeUnlinkedCommandCancellationToken.Token);
            BookHistoryCollection.Current.ShowRemovedMessage(count);
        }

        #endregion
    }
}
