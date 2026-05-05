using CommunityToolkit.Mvvm.ComponentModel;
using NeeLaboratory.ComponentModel;
using NeeView.ComponentModel;
using System;
using System.Windows;

namespace NeeView
{
    /// <summary>
    /// NormalInfoMessage : ViewModel
    /// </summary>
    public class NormalInfoMessageViewModel : ObservableObject
    {
        private readonly WeakBindableBase<NormalInfoMessage> _model;
        private int _changeCount;


        public NormalInfoMessageViewModel(NormalInfoMessage model)
        {
            _model = new WeakBindableBase<NormalInfoMessage>(model);

            _model.SubscribePropertyChanged(nameof(NormalInfoMessage.Message),
                (s, e) =>
                {
                    if (!string.IsNullOrWhiteSpace(_model.Model.Message)) ChangeCount++;
                    OnPropertyChanged(nameof(Message));
                    OnPropertyChanged(nameof(Visibility));
                });

            _model.SubscribePropertyChanged(nameof(NormalInfoMessage.BookMementoIcon),
                (s, e) =>
                {
                    OnPropertyChanged(nameof(BookmarkIconVisibility));
                    OnPropertyChanged(nameof(HistoryIconVisibility));
                });

            _model.SubscribePropertyChanged(nameof(NormalInfoMessage.DisplayTime),
                (s, e) =>
                {
                    OnPropertyChanged(nameof(DisplayTime));
                });
        }


        /// <summary>
        /// 表示の更新通知に利用するカウンタ
        /// </summary>
        public int ChangeCount
        {
            get { return _changeCount; }
            set { SetProperty(ref _changeCount, value); }
        }

        public string? Message => _model.Model.Message;

        public TimeSpan DisplayTime => TimeSpan.FromSeconds(_model.Model.DisplayTime);

        public Visibility Visibility => string.IsNullOrEmpty(_model.Model.Message) ? Visibility.Collapsed : Visibility.Visible;

        public Visibility BookmarkIconVisibility => _model.Model.BookMementoIcon == BookMementoType.Bookmark ? Visibility.Visible : Visibility.Collapsed;

        public Visibility HistoryIconVisibility => _model.Model.BookMementoIcon == BookMementoType.History ? Visibility.Visible : Visibility.Collapsed;
    }

}
