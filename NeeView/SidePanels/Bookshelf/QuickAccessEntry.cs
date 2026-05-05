using CommunityToolkit.Mvvm.ComponentModel;
using NeeView.Collections.Generic;
using System.Threading.Tasks;

namespace NeeView
{
    public abstract class QuickAccessEntry : ObservableObject, ITreeListNode, IRenameable
    {
        public abstract string? RawName { get; }
        public abstract string? Name { get; set; }
        public virtual string? Path { get => null; set { } }

        public virtual bool CanRename()
        {
            return false;
        }

        public virtual string GetRenameText()
        {
            return Name ?? "";
        }

        public virtual Task<bool> RenameAsync(string name)
        {
            return Task.FromResult(false);
        }

        public virtual object Clone()
        {
            return MemberwiseClone();
        }
    }

}
