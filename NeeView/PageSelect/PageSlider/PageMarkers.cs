using CommunityToolkit.Mvvm.ComponentModel;
using System.Collections.Generic;
using System.Linq;

namespace NeeView
{
    /// <summary>
    /// マーカー群表示用コレクション
    /// </summary>
    public class PageMarkerCollection
    {
        public PageMarkerCollection(List<int> indexes, int maximum)
        {
            Indexes = indexes;
            Maximum = maximum;
        }

        public List<int> Indexes { get; set; }
        public int Maximum { get; set; }
    }

    /// <summary>
    /// PageMarkers : Model
    /// </summary>
    public class PageMarkers : ObservableObject
    {
        private readonly BookOperation _bookOperation;
        private PageMarkerCollection? _markerCollection;
        private bool _isSliderDirectionReversed;


        public PageMarkers(BookOperation bookOperation)
        {
            _bookOperation = bookOperation;

            _bookOperation.BookChanged +=
                (s, e) => Update();
            _bookOperation.Control.PagesChanged +=
                (s, e) => Update();
            _bookOperation.Playlist.MarkersChanged +=
                (s, e) => Update();
        }


        /// <summary>
        /// MarkerCollection property.
        /// </summary>
        public PageMarkerCollection? MarkerCollection
        {
            get { return _markerCollection; }
            set { SetProperty(ref _markerCollection, value); }
        }

        /// <summary>
        /// スライダー方向
        /// </summary>
        public bool IsSliderDirectionReversed
        {
            get { return _isSliderDirectionReversed; }
            set { SetProperty(ref _isSliderDirectionReversed, value); }
        }


        /// <summary>
        /// マーカー更新
        /// </summary>
        private void Update()
        {
            var book = BookOperation.Current.Book;
            if (book != null && book.Pages.Any() && book.Marker.Markers.Any())
            {
                this.MarkerCollection = new PageMarkerCollection(
                    indexes: book.Marker.Markers.Select(e => e.Index).ToList(),
                    maximum: book.Pages.Count - 1
                );
            }
            else
            {
                this.MarkerCollection = null;
            }
        }

    }
}
