using CommunityToolkit.Mvvm.ComponentModel;
using NeeLaboratory.Generators;
using System.Collections.Specialized;
using System.ComponentModel;


namespace NeeView.Collections.Generic
{
    public partial class TreeCollection<T> : ObservableObject
        where T : ITreeListNode
    {
        public TreeCollection(TreeListNode<T> root)
        {
            Root = root;
        }

        [Subscribable]
        public event NotifyCollectionChangedEventHandler? RoutedCollectionChanged
        {
            add => Root.RoutedCollectionChanged += value;
            remove => Root.RoutedCollectionChanged -= value;
        }

        [Subscribable]
        public event PropertyChangedEventHandler? RoutedPropertyChanged
        {
            add => Root.RoutedPropertyChanged += value;
            remove => Root.RoutedPropertyChanged -= value;
        }

        [Subscribable]
        public event PropertyChangedEventHandler? RoutedValuePropertyChanged
        {
            add => Root.RoutedValuePropertyChanged += value;
            remove => Root.RoutedValuePropertyChanged -= value;
        }


        public TreeListNode<T> Root { get; }
    }
}
