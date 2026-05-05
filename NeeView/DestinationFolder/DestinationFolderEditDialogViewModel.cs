using CommunityToolkit.Mvvm.ComponentModel;

namespace NeeView
{
    public class DestinationFolderEditDialogViewModel : ObservableObject
    {
        private readonly DestinationFolder _model;


        public DestinationFolderEditDialogViewModel(DestinationFolder model)
        {
            _model = model;
        }


        public string Name
        {
            get => _model.Name;
            set => _model.Name = value;
        }

        public string Path
        {
            get => _model.Path;
            set
            {
                _model.Path = value;
                OnPropertyChanged(nameof(Name));
            }
        }

    }
}
