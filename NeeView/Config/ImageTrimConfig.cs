using CommunityToolkit.Mvvm.ComponentModel;
using Generator.Equals;
using NeeLaboratory;
using NeeView.Windows.Property;

namespace NeeView
{
    [Equatable(Explicit = true, IgnoreInheritedMembers = true)]
    public partial class ImageTrimConfig : ObservableObject
    {
        private const double _maxRate = 0.9;

        [DefaultEquality] private bool _isEnabled;
        [DefaultEquality] private double _top;
        [DefaultEquality] private double _bottom;
        [DefaultEquality] private double _left;
        [DefaultEquality] private double _right;


        [PropertyMember(IsVisible = false)]
        public bool IsEnabled
        {
            get { return _isEnabled; }
            set { SetProperty(ref _isEnabled, value); }
        }


        [PropertyPercent(0.0, _maxRate)]
        public double Left
        {
            get { return _left; }
            set
            {
                if (SetProperty(ref _left, AppMath.Round(MathUtility.Clamp(value, 0.0, _maxRate))))
                {
                    if (_left + _right > _maxRate)
                    {
                        _right = _maxRate - _left;
                        OnPropertyChanged(nameof(Right));
                    }
                }
            }
        }

        [PropertyPercent(0.0, _maxRate)]
        public double Right
        {
            get { return _right; }
            set
            {
                if (SetProperty(ref _right, AppMath.Round(MathUtility.Clamp(value, 0.0, _maxRate))))
                {
                    if (_left + _right > _maxRate)
                    {
                        _left = _maxRate - _right;
                        OnPropertyChanged(nameof(Left));
                    }
                }
            }
        }


        [PropertyPercent(0.0, _maxRate)]
        public double Top
        {
            get { return _top; }
            set
            {
                if (SetProperty(ref _top, AppMath.Round(MathUtility.Clamp(value, 0.0, _maxRate))))
                {
                    if (_top + _bottom > _maxRate)
                    {
                        _bottom = _maxRate - _top;
                        OnPropertyChanged(nameof(Bottom));
                    }
                }
            }
        }

        [PropertyPercent(0.0, _maxRate)]
        public double Bottom
        {
            get { return _bottom; }
            set
            {
                if (SetProperty(ref _bottom, AppMath.Round(MathUtility.Clamp(value, 0.0, _maxRate))))
                {
                    if (_top + _bottom > _maxRate)
                    {
                        _top = _maxRate - _bottom;
                        OnPropertyChanged(nameof(Top));
                    }
                }
            }
        }


    }
}
