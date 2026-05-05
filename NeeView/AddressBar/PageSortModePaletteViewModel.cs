using CommunityToolkit.Mvvm.ComponentModel;
using NeeLaboratory.ComponentModel;
using System.Collections.Generic;

namespace NeeView
{
    public class PageSortModePaletteViewModel : ObservableObject
    {
        private readonly PageSortModePaletteModel _model;


        public PageSortModePaletteViewModel()
        {
            _model = new PageSortModePaletteModel();
            _model.SubscribePropertyChanged(nameof(_model.PageSortModeList),
                (s, e) => OnPropertyChanged(nameof(PageSortModeList)));
        }


        public List<PageSortMode> PageSortModeList => _model.PageSortModeList;


        public void Decide(PageSortMode mode)
        {
            BookSettings.Current.SetSortMode(mode);
        }
    }

}
