using CommunityToolkit.Mvvm.ComponentModel;
using System;
using System.ComponentModel;
using System.Windows;
using System.Windows.Controls;

namespace NeeView.Windows.Controls
{
    [INotifyPropertyChanged]
    public partial class SizeInspector : Control
    {
        static SizeInspector()
        {
            DefaultStyleKeyProperty.OverrideMetadata(typeof(SizeInspector), new FrameworkPropertyMetadata(typeof(SizeInspector)));
        }


        public override void OnApplyTemplate()
        {
            base.OnApplyTemplate();

            var root = this.GetTemplateChild("PART_Root") as Grid ?? throw new InvalidOperationException();
            root.DataContext = this;
        }


        public Size Size
        {
            get { return (Size)GetValue(SizeProperty); }
            set { SetValue(SizeProperty, value); }
        }

        public static readonly DependencyProperty SizeProperty =
            DependencyProperty.Register("Size", typeof(Size), typeof(SizeInspector), new FrameworkPropertyMetadata(new Size(), FrameworkPropertyMetadataOptions.BindsTwoWayByDefault, SizePropertyChanged));

        private static void SizePropertyChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
        {
            (d as SizeInspector)?.OnPropertyChanged("");
        }


        public double X
        {
            get { return Size.Width; }
            set { if (Size.Width != value) { Size = new Size(value, Size.Height); OnPropertyChanged(); } }
        }

        public double Y
        {
            get { return Size.Height; }
            set { if (Size.Height != value) { Size = new Size(Size.Width, value); OnPropertyChanged(); } }
        }
    }
}
