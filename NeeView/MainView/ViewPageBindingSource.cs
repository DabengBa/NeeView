using CommunityToolkit.Mvvm.ComponentModel;
using System.Collections.Generic;
using System.Linq;

namespace NeeView
{
    public partial class ViewPageBindingSource : ObservableObject
    {
        public static ViewPageBindingSource Default { get; } = new ViewPageBindingSource(PageFrameBoxPresenter.Current);


        private readonly PageFrameBoxPresenter _presenter;

        public ViewPageBindingSource(PageFrameBoxPresenter presenter)
        {
            _presenter = presenter;
            _presenter.ViewPageChanged += PageFrameBoxPresenter_ViewPageChanged;
        }

        public IReadOnlyList<Page> ViewPages => _presenter.ViewPages;

        public bool AnyViewPages => ViewPages.Any();

        private void PageFrameBoxPresenter_ViewPageChanged(object? sender, ViewPageChangedEventArgs e)
        {
            OnPropertyChanged("");
        }
    }
}
