using CommunityToolkit.Mvvm.ComponentModel;
using System.IO;

namespace NeeView
{
    public class FileIOProfile : ObservableObject
    {
        static FileIOProfile() => Current = new FileIOProfile();
        public static FileIOProfile Current { get; }


        private FileIOProfile()
        {
        }


        /// <summary>
        /// ファイル除外属性
        /// </summary>
        public FileAttributes AttributesToSkip => Config.Current.System.IsHiddenFileVisible ? FileAttributes.None : FileAttributes.Hidden;


        /// <summary>
        /// ファイルは項目として有効か？
        /// </summary>
        public bool IsFileValid(FileAttributes attributes)
        {
            return (attributes & AttributesToSkip) == 0;
        }

    }
}
