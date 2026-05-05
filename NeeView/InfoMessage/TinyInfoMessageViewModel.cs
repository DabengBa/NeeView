using CommunityToolkit.Mvvm.ComponentModel;
using NeeLaboratory.ComponentModel;
using System;
using System.Windows;

namespace NeeView
{
    /// <summary>
    /// TinyInfoMessage : ViewModel
    /// </summary>
    public class TinyInfoMessageViewModel : ObservableObject
    {
        private int _changeCount;
        private TinyInfoMessage _model;

        public TinyInfoMessageViewModel(TinyInfoMessage model)
        {
            _model = model;

            _model.SubscribePropertyChanged(nameof(_model.Message),
                (s, e) =>
                {
                    if (!string.IsNullOrWhiteSpace(_model.Message)) ChangeCount++;
                    OnPropertyChanged(nameof(Visibility));
                });

            _model.SubscribePropertyChanged(nameof(_model.DisplayTime),
                (s, e) =>
                {
                    OnPropertyChanged(nameof(DisplayTime));
                });
        }

        /// <summary>
        /// ChangeCount property.
        /// 表示の更新通知に利用される。
        /// </summary>
        public int ChangeCount
        {
            get { return _changeCount; }
            set { SetProperty(ref _changeCount, value); }
        }

        /// <summary>
        /// Model property.
        /// </summary>
        public TinyInfoMessage Model
        {
            get { return _model; }
            set { SetProperty(ref _model, value); }
        }

        public TimeSpan DisplayTime => TimeSpan.FromSeconds(_model.DisplayTime);

        public Visibility Visibility => string.IsNullOrEmpty(_model.Message) ? Visibility.Collapsed : Visibility.Visible;
    }
}
