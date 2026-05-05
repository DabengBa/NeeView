using CommunityToolkit.Mvvm.ComponentModel;

namespace NeeView
{
    /// <summary>
    /// 画面に表示する通知：小さく通知
    /// </summary>
    public class TinyInfoMessage : ObservableObject
    {
        private string? _message;
        private double _displayTime = 1.0;

        /// <summary>
        /// Message property.
        /// </summary>
        public string? Message
        {
            get { return _message; }
            set { _message = value; }
        }

        /// <summary>
        /// DisplayTime property. (sec)
        /// </summary>
        public double DisplayTime
        {
            get { return _displayTime; }
            set { SetProperty(ref _displayTime, value); }
        }

        /// <summary>
        /// 通知
        /// </summary>
        /// <param name="message"></param>
        public void SetMessage(string message)
        {
            this.Message = message;
            OnPropertyChanged(nameof(Message));
        }
    }
}
