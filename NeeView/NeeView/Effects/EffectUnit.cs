using CommunityToolkit.Mvvm.ComponentModel;
using Generator.Equals;

namespace NeeView.Effects
{
    [Equatable(IgnoreInheritedMembers = true)]
    public partial class EffectUnit : ObservableObject
    {
        public void RaisePropertyChangedAll()
        {
            OnPropertyChanged("");
        }
    }
}
