using CommunityToolkit.Mvvm.ComponentModel;
using System.Collections.Generic;

namespace NeeView
{
    public partial class TrackCollection : ObservableObject
    {
        public List<TrackItem> _items;
        private TrackItem? _selected;

        public TrackCollection(IEnumerable<TrackItem> items)
        {
            _items = new List<TrackItem>(items);
        }

        public List<TrackItem> Tracks => _items;

        public TrackItem? Selected
        {
            get { return _selected; }
            set
            {
                SetProperty(ref _selected, value);
            }
        }
    }
}

