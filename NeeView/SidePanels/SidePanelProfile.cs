using NeeLaboratory.ComponentModel;

namespace NeeView
{
    public class SidePanelProfile
    {
        public void Initialize()
        {
            FontParameters.Current.SubscribePropertyChanged(nameof(FontParameters.DefaultFontName),
                (s, e) => ValidatePanelListItemProfile());

            FontParameters.Current.SubscribePropertyChanged(nameof(FontParameters.PaneFontSize),
                (s, e) => ValidatePanelListItemProfile());

            ValidatePanelListItemProfile();
        }

        public static string GetDecoratePlaceName(string s)
        {
            if (string.IsNullOrEmpty(s)) return s;
            return Config.Current.Panels.IsDecoratePlace ? LoosePath.GetPlaceName(s) : s;
        }

        private static void ValidatePanelListItemProfile()
        {
            Config.Current.Panels.ContentItemProfile.UpdateTextHeight();
            Config.Current.Panels.BannerItemProfile.UpdateTextHeight();
            Config.Current.Panels.ThumbnailItemProfile.UpdateTextHeight();
        }

    }

}
