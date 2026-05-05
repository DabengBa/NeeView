using CommunityToolkit.Mvvm.ComponentModel;

namespace NeeView
{
    public class AppState : ObservableObject
    {
        private static readonly AppState _instance = new AppState();
        public static AppState Instance => _instance;


        private bool _isProcessingBook;

        /// <summary>
        /// ブックの処理中
        /// </summary>
        public bool IsProcessingBook
        {
            get { return _isProcessingBook; }
            set { SetProperty(ref _isProcessingBook, value); }
        }
    }
}
