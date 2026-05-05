using CommunityToolkit.Mvvm.ComponentModel;
using System;
using System.ComponentModel;
using System.Windows;
using System.Windows.Controls;

namespace NeeView.Windows.Controls
{
    [INotifyPropertyChanged]
    public partial class PointInspector : Control
    {
        static PointInspector()
        {
            DefaultStyleKeyProperty.OverrideMetadata(typeof(PointInspector), new FrameworkPropertyMetadata(typeof(PointInspector)));
        }


        public override void OnApplyTemplate()
        {
            base.OnApplyTemplate();

            var root = this.GetTemplateChild("PART_Root") as Grid ?? throw new InvalidOperationException();
            root.DataContext = this;
        }


        public Point Point
        {
            get { return (Point)GetValue(PointProperty); }
            set { SetValue(PointProperty, value); }
        }

        public static readonly DependencyProperty PointProperty =
            DependencyProperty.Register("Point", typeof(Point), typeof(PointInspector), new PropertyMetadata(new Point()));


        public double X
        {
            get { return Point.X; }
            set { if (Point.X != value) { Point = new Point(value, Point.Y); OnPropertyChanged(); } }
        }

        public double Y
        {
            get { return Point.Y; }
            set { if (Point.Y != value) { Point = new Point(Point.X, value); OnPropertyChanged(); } }
        }
    }
}
