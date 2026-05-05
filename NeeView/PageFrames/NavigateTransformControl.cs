using CommunityToolkit.Mvvm.ComponentModel;
using System;
using System.Diagnostics;
using System.Windows;
using System.Windows.Media.Animation;

namespace NeeView.PageFrames
{
    public partial class NavigateTransformControl : ObservableObject, ITransformControl
    {
        private PageFrameBoxPresenter _presenter;
        private PageFrameTransformAccessor? _source;

        public NavigateTransformControl(PageFrameBoxPresenter presenter)
        {
            _presenter = presenter;
            _presenter.SelectedRangeChanged += (s, e) => UpdateSource();

            UpdateSource();
        }

        public double Scale => _source?.Scale ?? 1.0;

        public double Angle => _source?.Angle ?? 0.0;

        public Point Point => _source?.Point ?? default;

        public bool IsFlipHorizontal => _source?.IsFlipHorizontal ?? false;

        public bool IsFlipVertical => _source?.IsFlipVertical ?? false;


        private void UpdateSource()
        {
            var source = _presenter.CreateSelectedTransform();
            if (_source == source) return;

            Detach();
            Attach(source);
        }

        private void Attach(PageFrameTransformAccessor? source)
        {
            Debug.Assert(_source is null);
            if (source is null) return;
            _source = source;
            _source.TransformChanged += Source_TransformChanged;
            OnPropertyChanged("");
        }

        private void Detach()
        {
            if (_source is null) return;
            _source.TransformChanged -= Source_TransformChanged;
            _source = null;
        }

        private void Source_TransformChanged(object? sender, TransformChangedEventArgs e)
        {
            switch (e.Action)
            {
                case TransformAction.Scale:
                    OnPropertyChanged(nameof(Scale));
                    break;
                case TransformAction.Angle:
                    OnPropertyChanged(nameof(Angle));
                    break;
                case TransformAction.Point:
                    OnPropertyChanged(nameof(Point));
                    break;
                case TransformAction.FlipHorizontal:
                    OnPropertyChanged(nameof(IsFlipHorizontal));
                    break;
                case TransformAction.FlipVertical:
                    OnPropertyChanged(nameof(IsFlipVertical));
                    break;
            }
        }

        public void SetPoint(Point value, TimeSpan span)
        {
            SetPoint(value, span, null, null);
        }

        public void SetPoint(Point value, TimeSpan span, IEasingFunction? easeX, IEasingFunction? easeY)
        {
            _source?.SetPoint(value, span, easeX, easeY);
        }

        public void SetAngle(double value, TimeSpan span)
        {
            _source?.SetAngle(value, span);
        }

        public void SetFlipHorizontal(bool value, TimeSpan span)
        {
            _source?.SetFlipHorizontal(value, span);
        }

        public void SetFlipVertical(bool value, TimeSpan span)
        {
            _source?.SetFlipVertical(value, span);
        }

        public void SetScale(double value, TimeSpan span, TransformTrigger trigger = TransformTrigger.None)
        {
            _source?.SetScale(value, span, trigger);
        }

        public void SnapView()
        {
            _presenter.Stretch(false);
        }
    }





}
