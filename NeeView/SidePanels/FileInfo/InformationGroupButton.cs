using CommunityToolkit.Mvvm.Input;
using NeeView.Properties;
using System.Windows;
using System.Windows.Controls;

namespace NeeView
{
    public partial class InformationGroupButton : Button
    {

        public InformationGroupButton() : base()
        {
        }


        public FileInformationSource Source
        {
            get { return (FileInformationSource)GetValue(SourceProperty); }
            set { SetValue(SourceProperty, value); }
        }

        public static readonly DependencyProperty SourceProperty =
            DependencyProperty.Register("Source", typeof(FileInformationSource), typeof(InformationGroupButton), new PropertyMetadata(null, AnyPropertyChanged));


        public string GroupName
        {
            get { return (string)GetValue(GroupNameProperty); }
            set { SetValue(GroupNameProperty, value); }
        }

        public static readonly DependencyProperty GroupNameProperty =
            DependencyProperty.Register("GroupName", typeof(string), typeof(InformationGroupButton), new PropertyMetadata(null, AnyPropertyChanged));


        private static void AnyPropertyChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
        {
            if (d is InformationGroupButton control)
            {
                control.Update();
            }
        }

        private void Update()
        {
            if (GroupName == InformationGroup.File.ToAliasName())
            {
                this.Content = TextResources.GetString("Information.OpenFolder");
                this.Command = OpenFolderCommand;
                this.Visibility = CanOpenFolder() ? Visibility.Visible : Visibility.Collapsed;
            }
            else if (GroupName == InformationGroup.Gps.ToAliasName())
            {
                this.Content = TextResources.GetString("Information.OpenMap");
                this.Command = OpenMapCommand;
                this.Visibility = CanOpenMap() ? Visibility.Visible : Visibility.Collapsed;
            }
            else
            {
                this.Visibility = Visibility.Collapsed;
            }
        }

        private bool CanOpenFolder()
        {
            return Source?.CanOpenPlace() == true;
        }

        [RelayCommand]
        private void OpenFolder()
        {
            Source?.OpenPlace();
        }

        private bool CanOpenMap()
        {
            return Source?.CanOpenMap() == true;
        }

        [RelayCommand]
        private void OpenMap()
        {
            Source?.OpenMap();
        }
    }

}
