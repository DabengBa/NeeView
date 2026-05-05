using CommunityToolkit.Mvvm.ComponentModel;
using NeeLaboratory.ComponentModel;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Data;

namespace NeeView
{
    public partial class HistoryListBoxViewModel : ObservableObject
    {
        private readonly HistoryList _model;
        private readonly PanelThumbnailItemSize _thumbnailItemSize;

        public HistoryListBoxViewModel(HistoryList model)
        {
            _model = model;

            _model.SubscribePropertyChanged(nameof(HistoryList.SelectedItem),
                (s, e) => OnPropertyChanged(nameof(SelectedItem)));

            _thumbnailItemSize = new PanelThumbnailItemSize(Config.Current.Panels.ThumbnailItemProfile, 5.0 + 1.0, 4.0 + 1.0, new Size(18.0, 18.0));
            _thumbnailItemSize.SubscribePropertyChanged(nameof(PanelThumbnailItemSize.ItemSize), (s, e) => OnPropertyChanged(nameof(ThumbnailItemSize)));

            DetailToolTip = new PanelListItemDetailToolTip(Config.Current.History);
        }


        public bool IsThumbnailVisible => _model.IsThumbnailVisible;

        public Size ThumbnailItemSize => _thumbnailItemSize.ItemSize;

        public CollectionViewSource CollectionViewSource => _model.CollectionViewSource;

        public BookHistory? SelectedItem
        {
            get => _model.SelectedItem;
            set => _model.SelectedItem = value;
        }

        public PanelListItemDetailToolTip DetailToolTip { get; }


        public void Remove(IEnumerable<BookHistory> items)
        {
            _model.Remove(items);
        }

        public void Load(string path)
        {
            Load(path, ArchiveHint.None);
        }

        public void Load(string path, ArchiveHint archiveHint)
        {
            if (path == null) return;
            BookHub.Current?.RequestLoad(this, path, null, BookLoadOption.KeepHistoryOrder | BookLoadOption.SkipSamePlace | BookLoadOption.IsBook, true, archiveHint, null);
        }

        public bool IsLRKeyEnabled()
        {
            return Config.Current.Panels.IsLeftRightKeyEnabled || _model.PanelListItemStyle == PanelListItemStyle.Thumbnail;
        }

        public List<BookHistory> GetViewItems()
        {
            var collectionView = (CollectionView)CollectionViewSource.View;
            if (collectionView.NeedsRefresh)
            {
                collectionView.Refresh();
            }
            return collectionView.Cast<BookHistory>().ToList();
        }
    }
}
