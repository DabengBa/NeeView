using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using NeeView.Properties;
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics.CodeAnalysis;
using System.Windows;
using System.Windows.Documents;

namespace NeeView
{
    public class PrintWindowCloseEventArgs : EventArgs
    {
        public bool? Result { get; set; }
    }


    public partial class PrintWindowViewModel : ObservableObject
    {
        private readonly PrintModel _model;
        private bool _isEnabled = true;
        private FrameworkElement? _mainContent;
        private List<FixedPage> _pageCollection = new();


        public PrintWindowViewModel(PrintContext context)
        {
            _model = new PrintModel(context);
            _model.Restore(Config.Current.Print);

            _model.PropertyChanged += PrintService_PropertyChanged;

            UpdatePreview();
        }


        public event EventHandler<PrintWindowCloseEventArgs>? Close;


        public PrintModel Model => _model;

        /// <summary>
        /// ウィンドウ操作有効フラグ
        /// </summary>
        /// <remarks>
        /// PrintDialog はサブウィンドウをオーナーとして表示できないため、ウィンドウ操作無効を独自実装するためのフラグ。
        /// 完全ではなく、ALT+F4等のシステムコマンドは実行されてしまうが、それらは許容する。
        /// </remarks>
        public bool IsEnabled
        {
            get { return _isEnabled; }
            set { SetProperty(ref _isEnabled, value); }
        }

        public FrameworkElement? MainContent
        {
            get { return _mainContent; }
            set { SetProperty(ref _mainContent, value); }
        }

        public List<FixedPage> PageCollection
        {
            get { return _pageCollection; }
            set { SetProperty(ref _pageCollection, value); }
        }

        public double MarginLeft
        {
            get { return _model.Margin.Left; }
            set { if (_model.Margin.Left != value) { _model.Margin = _model.Margin with { Left = value }; } }
        }

        public double MarginRight
        {
            get { return _model.Margin.Right; }
            set { if (_model.Margin.Right != value) { _model.Margin = _model.Margin with { Right = value }; } }
        }

        public double MarginTop
        {
            get { return _model.Margin.Top; }
            set { if (_model.Margin.Top != value) { _model.Margin = _model.Margin with { Top = value }; } }
        }

        public double MarginBottom
        {
            get { return _model.Margin.Bottom; }
            set { if (_model.Margin.Bottom != value) { _model.Margin = _model.Margin with { Bottom = value }; } }
        }


        /// <summary>
        /// 終了処理
        /// </summary>
        public void Closed()
        {
            Config.Current.Print = _model.CreateMemento();
        }

        /// <summary>
        /// パラメータ変更イベント処理
        /// </summary>
        /// <param name="sender"></param>
        /// <param name="e"></param>
        private void PrintService_PropertyChanged(object? sender, PropertyChangedEventArgs e)
        {
            UpdatePreview();
        }

        /// <summary>
        /// プレビュー更新
        /// </summary>
        [MemberNotNull(nameof(PageCollection))]
        private void UpdatePreview()
        {
            PageCollection = _model.CreatePageCollection();
        }

        [RelayCommand]
        private void Reset()
        {
            var dialog = new MessageDialog(TextResources.GetString("PrintResetDialog.Title"), TextResources.GetString("PrintResetDialog.Message"));
            dialog.Commands.Add(UICommands.OK);
            dialog.Commands.Add(UICommands.Cancel);
            var result = dialog.ShowDialog(App.Current.MainWindow);
            if (result.IsPossible)
            {
                _model.ResetDialog();
                Config.Current.Print = new();
            }
        }

        [RelayCommand]
        private void Print()
        {
            _model.Print();
            Close?.Invoke(this, new PrintWindowCloseEventArgs() { Result = true });
        }

        [RelayCommand]
        private void Cancel()
        {
            Close?.Invoke(this, new PrintWindowCloseEventArgs() { Result = false });
        }

        [RelayCommand]
        private void PrintDialog()
        {
            if (_model.PrintDialogShown) return;

            try
            {
                IsEnabled = false;
                _model.ShowPrintDialog();
            }
            finally
            {
                IsEnabled = true;
            }
            UpdatePreview();
        }
    }
}
