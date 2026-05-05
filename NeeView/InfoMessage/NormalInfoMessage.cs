using CommunityToolkit.Mvvm.ComponentModel;

namespace NeeView
{
    /// <summary>
    /// 画面に表示する通知：通常
    /// </summary>
    public class NormalInfoMessage : ObservableObject
    {
        private BookMementoType _bookMementoIcon;
        private double _displayTime = 1.0;
        private string? _message;

        /// <summary>
        /// BookMementoIcon property.
        /// </summary>
        public BookMementoType BookMementoIcon
        {
            get { return _bookMementoIcon; }
            set { SetProperty(ref _bookMementoIcon, value); }
        }

        /// <summary>
        /// DisplayTime property. (sec)
        /// </summary>
        public double DisplayTime
        {
            get { return _displayTime; }
            set { SetProperty(ref _displayTime, value); }
        }

        // 通知テキスト
        public string? Message
        {
            get { return _message; }
            set { _message = value; OnPropertyChanged(); }
        }

        /// <summary>
        /// 通知
        /// </summary>
        /// <param name="message"></param>
        /// <param name="displayTime"></param>
        /// <param name="bookmarkType"></param>
        public void SetMessage(string message, double displayTime = 1.0, BookMementoType bookmarkType = BookMementoType.None)
        {
            this.BookMementoIcon = bookmarkType;
            this.DisplayTime = displayTime;
            this.Message = message;
        }
    }
}
