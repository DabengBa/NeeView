using CommunityToolkit.Mvvm.ComponentModel;
using Generator.Equals;

namespace NeeView
{
    [Equatable(IgnoreInheritedMembers = true)]
    public partial class ArchiveConfig : ObservableObject
    {
        public ZipArchiveConfig Zip { get; set; } = new ZipArchiveConfig();

        public SevenZipArchiveConfig SevenZip { get; set; } = new SevenZipArchiveConfig();

        public PdfArchiveConfig Pdf { get; set; } = new PdfArchiveConfig();

        public MediaArchiveConfig Media { get; set; } = new MediaArchiveConfig();
    }
}
