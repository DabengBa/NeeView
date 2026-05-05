using CommunityToolkit.Mvvm.ComponentModel;
using NeeLaboratory.ComponentModel;
using NeeView.Windows;
using System;
using System.ComponentModel;
using System.Windows;

namespace NeeView
{
    /// <summary>
    /// SidePanelFrame ViewModel
    /// </summary>
    public class SidePanelFrameViewModel : ObservableObject
    {
        private SidePanelFrame _model;


        public SidePanelFrameViewModel(SidePanelFrame model, LeftPanelViewModel left, RightPanelViewModel right)
        {
            _model = model;
            _model.VisibleAtOnceRequest += Model_VisibleAtOnceRequest;

            MainLayoutPanelManager = CustomLayoutPanelManager.Current;

            Left = left;
            Left.PropertyChanged += Left_PropertyChanged;

            Right = right;
            Right.PropertyChanged += Right_PropertyChanged;

            MainWindowModel.Current.SubscribePropertyChanged(nameof(MainWindowModel.CanHideLeftPanel),
                (s, e) => OnPropertyChanged(nameof(LeftPanelOpacity)));

            MainWindowModel.Current.SubscribePropertyChanged(nameof(MainWindowModel.CanHideRightPanel),
                (s, e) => OnPropertyChanged(nameof(RightPanelOpacity)));

            Config.Current.Panels.SubscribePropertyChanged(nameof(PanelsConfig.Opacity),
                (s, e) =>
                {
                    OnPropertyChanged(nameof(LeftPanelOpacity));
                    OnPropertyChanged(nameof(RightPanelOpacity));
                });

            Config.Current.Panels.SubscribePropertyChanged(nameof(PanelsConfig.IsSideBarEnabled),
                (s, e) => OnPropertyChanged(nameof(IsSideBarVisible)));

            Config.Current.Panels.SubscribePropertyChanged(nameof(PanelsConfig.IsLimitPanelWidth),
                (s, e) => OnPropertyChanged(nameof(IsLimitPanelWidth)));

            MainLayoutPanelManager.DragBegin +=
                (s, e) => DragBegin(this, EventArgs.Empty);
            MainLayoutPanelManager.DragEnd +=
                (s, e) => DragEnd(this, EventArgs.Empty);

            LeftSidePanelIconDescriptor = new SidePanelIconDescriptor(this, MainLayoutPanelManager.LeftDock);
            RightSidePanelIconDescriptor = new SidePanelIconDescriptor(this, MainLayoutPanelManager.RightDock);
        }


        public event EventHandler? PanelVisibilityChanged;


        public SidePanelIconDescriptor LeftSidePanelIconDescriptor { get; }
        public SidePanelIconDescriptor RightSidePanelIconDescriptor { get; }

        public bool IsSideBarVisible
        {
            get => Config.Current.Panels.IsSideBarEnabled;
            set => Config.Current.Panels.IsSideBarEnabled = value;
        }

        public double LeftPanelOpacity
        {
            get => MainWindowModel.Current.CanHideLeftPanel ? Config.Current.Panels.Opacity : 1.0;
        }

        public double RightPanelOpacity
        {
            get => MainWindowModel.Current.CanHideRightPanel ? Config.Current.Panels.Opacity : 1.0;
        }

        public GridLength LeftPanelWidth
        {
            get => new(this.Left.Width);
            set => this.Left.Width = value.Value;
        }

        public GridLength RightPanelWidth
        {
            get => new(this.Right.Width);
            set => this.Right.Width = value.Value;
        }

        public bool IsLeftPanelActive
        {
            get => this.Left.IsPanelActive;
        }

        public bool IsRightPanelActive
        {
            get => this.Right.IsPanelActive;
        }

        public bool IsLimitPanelWidth
        {
            get => Config.Current.Panels.IsLimitPanelWidth;
            set => Config.Current.Panels.IsLimitPanelWidth = value;
        }


        /// <summary>
        /// パネル表示リクエスト
        /// </summary>
        private void Model_VisibleAtOnceRequest(object? sender, VisibleAtOnceRequestEventArgs e)
        {
            VisibleAtOnce(e.Key, e.State);
        }

        /// <summary>
        /// パネルを一度だけ表示
        /// </summary>
        public void VisibleAtOnce(string key, StateRequest state)
        {
            if (string.IsNullOrEmpty(key))
            {
                Left.VisibleOnce(state);
                Right.VisibleOnce(state);
            }
            else if (Left.SelectedItemContains(key))
            {
                Left.VisibleOnce(state);
            }
            else if (Right.SelectedItemContains(key))
            {
                Right.VisibleOnce(state);
            }
        }


        public SidePanelFrame Model
        {
            get { return _model; }
            set { SetProperty(ref _model, value); }
        }

        public SidePanelViewModel Left { get; private set; }

        public SidePanelViewModel Right { get; private set; }

        public App App => App.Current;

        public AutoHideConfig AutoHideConfig => Config.Current.AutoHide;

        public CustomLayoutPanelManager MainLayoutPanelManager { get; private set; }


        /// <summary>
        /// ドラッグ開始イベント処理.
        /// 強制的にパネル表示させる
        /// </summary>
        public void DragBegin(object? sender, EventArgs e)
        {
            Left.IsDragged = true;
            Right.IsDragged = true;
        }

        /// <summary>
        /// ドラッグ終了イベント処理
        /// </summary>
        public void DragEnd(object? sender, EventArgs e)
        {
            Left.IsDragged = false;
            Right.IsDragged = false;
        }


        /// <summary>
        /// 右パネルのプロパティ変更イベント処理
        /// </summary>
        private void Right_PropertyChanged(object? sender, PropertyChangedEventArgs e)
        {
            switch (e.PropertyName)
            {
                case nameof(Right.Width):
                    OnPropertyChanged(nameof(RightPanelWidth));
                    break;
                case nameof(Right.PanelVisibility):
                    PanelVisibilityChanged?.Invoke(this, EventArgs.Empty);
                    break;
                case nameof(Right.IsAutoHide):
                    PanelVisibilityChanged?.Invoke(this, EventArgs.Empty);
                    break;
                case nameof(Right.IsPanelActive):
                    OnPropertyChanged(nameof(IsRightPanelActive));
                    break;
            }
        }

        /// <summary>
        /// 左パネルのプロパティ変更イベント処理
        /// </summary>
        private void Left_PropertyChanged(object? sender, PropertyChangedEventArgs e)
        {
            switch (e.PropertyName)
            {
                case nameof(Left.Width):
                    OnPropertyChanged(nameof(LeftPanelWidth));
                    break;
                case nameof(Left.PanelVisibility):
                    PanelVisibilityChanged?.Invoke(this, EventArgs.Empty);
                    break;
                case nameof(Left.IsAutoHide):
                    PanelVisibilityChanged?.Invoke(this, EventArgs.Empty);
                    break;
                case nameof(Left.IsPanelActive):
                    OnPropertyChanged(nameof(IsLeftPanelActive));
                    break;
            }
        }
    }
}
