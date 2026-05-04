using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using NeeView.Properties;
using System;
using System.Globalization;

namespace NeeView
{
    public class PageSelectDialogDecidedEventArgs : EventArgs
    {
        public PageSelectDialogDecidedEventArgs(bool result)
        {
            Result = result;
        }

        public bool Result { get; set; }
    }

    public partial class PageSelectDialogViewModel : ObservableObject
    {
        private readonly PageSelectDialogModel _model;

        public PageSelectDialogViewModel(PageSelectDialogModel model)
        {
            _model = model;

            _model.AddPropertyChanged(nameof(_model.Value),
                (s, e) => OnPropertyChanged(nameof(Value)));
        }


        public event EventHandler<PageSelectDialogDecidedEventArgs>? Decided;


        public string Caption => TextResources.GetString("JumpPageCommand");

        public string Label => string.Format(CultureInfo.InvariantCulture, TextResources.GetString("Notice.JumpPageLabel"), _model.Min, _model.Max);

        public int Value
        {
            get => _model.Value;
            set => _model.Value = value;
        }


        [RelayCommand]
        private void Decide()
        {
            Decided?.Invoke(this, new PageSelectDialogDecidedEventArgs(true));
        }

        [RelayCommand]
        private void Cancel()
        {
            Decided?.Invoke(this, new PageSelectDialogDecidedEventArgs(false));
        }

        public void AddValue(int delta)
        {
            _model.AddValue(delta);
        }
    }
}
