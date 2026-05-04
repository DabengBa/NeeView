using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using NeeView.Properties;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Windows;

namespace NeeView.Setting
{
    /// <summary>
    /// MouseGestureSetting ViewModel
    /// </summary>
    public partial class MouseGestureSettingViewModel : ObservableObject
    {
        private readonly IReadOnlyDictionary<string, CommandElement> _commandMap;
        private readonly string _key;
        private readonly TouchInputForGestureEditor _touchGesture;
        private readonly MouseInputForGestureEditor _mouseGesture;
        private MouseGestureToken _gestureToken = new(MouseSequence.Empty);
        private MouseSequence _newGesture = MouseSequence.Empty;


        public MouseGestureSettingViewModel(IReadOnlyDictionary<string, CommandElement> commandMap, string key, FrameworkElement gestureSender)
        {
            _commandMap = commandMap;
            _key = key;

            _touchGesture = new TouchInputForGestureEditor(gestureSender);
            _touchGesture.Gesture.GestureProgressed += Gesture_MouseGestureProgressed;

            _mouseGesture = new MouseInputForGestureEditor(gestureSender);
            _mouseGesture.Gesture.GestureProgressed += Gesture_MouseGestureProgressed;

            OriginalGesture = NewGesture = _commandMap[_key].MouseGesture;
            UpdateGestureToken(NewGesture);
        }


        public MouseGestureToken GestureToken
        {
            get { return _gestureToken; }
            set { SetProperty(ref _gestureToken, value); }
        }

        public MouseSequence OriginalGesture { get; set; }

        public MouseSequence NewGesture
        {
            get { return _newGesture; }
            set { SetProperty(ref _newGesture, value); }
        }


        /// <summary>
        /// Gesture Changed
        /// </summary>
        /// <param name="sender"></param>
        /// <param name="e"></param>
        private void Gesture_MouseGestureProgressed(object? sender, MouseGestureEventArgs e)
        {
            NewGesture = e.Sequence;
            UpdateGestureToken(NewGesture);
        }

        /// <summary>
        /// Update Gesture Information
        /// </summary>
        /// <param name="gesture"></param>
        public void UpdateGestureToken(MouseSequence gesture)
        {
            // Check Conflict
            var token = new MouseGestureToken(gesture);

            if (!token.Gesture.IsEmpty)
            {
                token.Conflicts = _commandMap
                    .Where(i => i.Key != _key && i.Value.MouseGesture == token.Gesture)
                    .Select(i => i.Key)
                    .ToList();

                if (token.Conflicts.Count > 0)
                {
                    token.OverlapsText = string.Format(CultureInfo.InvariantCulture, TextResources.GetString("Notice.Conflict"), TextResources.Join(token.Conflicts.Select(i => CommandTable.Current.GetElement(i).Text)));
                }
            }

            GestureToken = token;
        }

        /// <summary>
        /// 決定
        /// </summary>
        public void Flush()
        {
            _commandMap[_key].MouseGesture = NewGesture;
        }

        /// <summary>
        /// ClearCommand
        /// </summary>
        [RelayCommand]
        private void Clear()
        {
            _commandMap[_key].MouseGesture = MouseSequence.Empty;
            _mouseGesture.Gesture.Reset();
        }
    }
}
