using CommunityToolkit.Mvvm.ComponentModel;
using Generator.Equals;
using NeeView.Windows.Property;

namespace NeeView
{
    [Equatable(IgnoreInheritedMembers = true)]
    public partial class ImageConfig : ObservableObject
    {
        private bool _isMediaRepeat = true;

        public ImageStandardConfig Standard { get; set; } = new ImageStandardConfig();

        public ImageSvgConfig Svg { get; set; } = new ImageSvgConfig();


        /// <summary>
        /// 動画ページのループフラグ
        /// </summary>
        [PropertyMember]
        public bool IsMediaRepeat
        {
            get { return _isMediaRepeat; }
            set { SetProperty(ref _isMediaRepeat, value); }
        }
    }
}
