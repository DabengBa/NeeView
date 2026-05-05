using CommunityToolkit.Mvvm.ComponentModel;
using System.ComponentModel;
using System.Windows;

namespace NeeView
{
    [INotifyPropertyChanged]
    public partial class ProgressMessageDialog : Window
    {
        private bool _closeable = true;
        private ICancelableObject? _cancellableObject;

        public ProgressMessageDialog()
        {
            InitializeComponent();
            this.DataContext = this;
        }


        public string Message => _cancellableObject?.Name ?? "";

        public bool CanCancel => _cancellableObject?.CanCancel ?? false;

        public bool IsCanceled => _cancellableObject?.IsCanceled ?? false;


        public void SetCancellableObject(ICancelableObject? item)
        {
            _cancellableObject = item;
            OnPropertyChanged(nameof(Message));
            OnPropertyChanged(nameof(CanCancel));
            OnPropertyChanged(nameof(IsCanceled));
        }

        protected override void OnClosing(CancelEventArgs e)
        {
            if (!_closeable)
            {
                Cancel();
                e.Cancel = true;
                return;
            }

            base.OnClosing(e);
        }

        private void CancelButton_Click(object sender, RoutedEventArgs e)
        {
            Cancel();
        }

        private void Cancel()
        {
            if (_cancellableObject is null) return;
            if (_cancellableObject.IsCanceled) return;

            _cancellableObject.IsCanceled = true;
            OnPropertyChanged(nameof(IsCanceled));
            _cancellableObject.Cancel();
        }

        public new void Close()
        {
            _closeable = true;
            base.Close();
        }
    }
}
