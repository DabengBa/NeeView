using CommunityToolkit.Mvvm.ComponentModel;
using NeeLaboratory.ComponentModel;

namespace NeeView
{
    public partial class PageLoadingViewModel : ObservableObject
    {
        private PageLoading _model;

        public PageLoadingViewModel(PageLoading model)
        {
            _model = model;
            _model.SubscribePropertyChanged(nameof(_model.IsActive), (s, e) => OnPropertyChanged(nameof(IsActive)));
            _model.SubscribePropertyChanged(nameof(_model.Message), (s, e) => OnPropertyChanged(nameof(Message)));
        }

        public bool IsActive
        {
            get => _model.IsActive;
            set => _model.IsActive = value;
        }

        public string Message
        {
            get => _model.Message;
            set => _model.Message = value;
        }
    }
}
