using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text;

namespace AmigoClick
{
    /// <summary>Настройки в %APPDATA%\AmigoClick\settings.ini.</summary>
    internal sealed class Settings
    {
        public int IntervalMs = 100;
        public bool PointMode;
        public bool HasPoint;
        public int PointX;
        public int PointY;
        public bool AlwaysOnTop;
        public HotKey HotKey = HotKey.Default;

        private static string FilePath =>
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "AmigoClick", "settings.ini");

        public static Settings Load()
        {
            var s = new Settings();
            try
            {
                if (!File.Exists(FilePath)) return s;
                var map = new Dictionary<string, string>();
                foreach (var line in File.ReadAllLines(FilePath, Encoding.UTF8))
                {
                    int eq = line.IndexOf('=');
                    if (eq > 0) map[line.Substring(0, eq).Trim()] = line.Substring(eq + 1).Trim();
                }
                s.IntervalMs = Int(map, "interval", 100);
                s.PointMode = Int(map, "pointMode", 0) == 1;
                s.HasPoint = Int(map, "hasPoint", 0) == 1;
                s.PointX = Int(map, "pointX", 0);
                s.PointY = Int(map, "pointY", 0);
                s.AlwaysOnTop = Int(map, "onTop", 0) == 1;
                if (map.TryGetValue("hotKeyName", out var name) && name.Length > 0)
                    s.HotKey = new HotKey((uint)Int(map, "hotKeyVk", 0x36), (uint)Int(map, "hotKeyMods", 0), name);
                if (s.PointMode && !s.HasPoint) s.PointMode = false;
            }
            catch
            {
                // Битый файл — работаем с настройками по умолчанию.
            }
            return s;
        }

        public void Save()
        {
            try
            {
                Directory.CreateDirectory(Path.GetDirectoryName(FilePath));
                var lines = new[]
                {
                    "interval=" + IntervalMs,
                    "pointMode=" + (PointMode ? 1 : 0),
                    "hasPoint=" + (HasPoint ? 1 : 0),
                    "pointX=" + PointX,
                    "pointY=" + PointY,
                    "onTop=" + (AlwaysOnTop ? 1 : 0),
                    "hotKeyVk=" + HotKey.Vk,
                    "hotKeyMods=" + HotKey.Modifiers,
                    "hotKeyName=" + HotKey.Name,
                };
                File.WriteAllLines(FilePath, lines, Encoding.UTF8);
            }
            catch
            {
                // Не удалось сохранить — не страшно, просто не запомним.
            }
        }

        private static int Int(Dictionary<string, string> map, string key, int fallback) =>
            map.TryGetValue(key, out var v) && int.TryParse(v, NumberStyles.Integer, CultureInfo.InvariantCulture, out var n)
                ? n
                : fallback;
    }
}
