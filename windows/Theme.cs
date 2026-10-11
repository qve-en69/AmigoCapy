using System;
using System.Windows;
using System.Windows.Media;
using Microsoft.Win32;

namespace AmigoCapy
{
    /// <summary>Светлая или тёмная палитра — как выбрано в Windows.</summary>
    internal static class Theme
    {
        public static bool IsDark { get; private set; }

        public static void Apply(ResourceDictionary resources)
        {
            IsDark = ReadSystemDark();
            if (!IsDark) return;

            Set(resources, "WindowBg", "#1A1D22");
            Set(resources, "CardBg", "#23272D");
            Set(resources, "CardBorder", "#30353C");
            Set(resources, "Text", "#EEF0F3");
            Set(resources, "SubText", "#99A2AD");
            Set(resources, "Field", "#2B3037");
            Set(resources, "ChipBg", "#2D3239");
            Set(resources, "ChipHover", "#383E46");
            Set(resources, "SegmentOn", "#3A4048");
            Set(resources, "KeycapBg", "#30353C");
            Set(resources, "KeycapEdge", "#15181C");
            Set(resources, "IconHover", "#2F343B");
        }

        /// <summary>Тёмная рамка окна и скруглённые углы на Windows 11.</summary>
        public static void ApplyWindowAttributes(IntPtr hwnd)
        {
            int dark = IsDark ? 1 : 0;
            Native.DwmSetWindowAttribute(hwnd, 20, ref dark, sizeof(int)); // DWMWA_USE_IMMERSIVE_DARK_MODE
            int round = 2;
            Native.DwmSetWindowAttribute(hwnd, 33, ref round, sizeof(int)); // DWMWA_WINDOW_CORNER_PREFERENCE
        }

        private static void Set(ResourceDictionary resources, string key, string hex)
        {
            var brush = new SolidColorBrush((Color)ColorConverter.ConvertFromString(hex));
            brush.Freeze();
            resources[key] = brush;
        }

        private static bool ReadSystemDark()
        {
            try
            {
                using (var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"))
                {
                    return key?.GetValue("AppsUseLightTheme") is int value && value == 0;
                }
            }
            catch
            {
                return false;
            }
        }
    }
}
