using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text;

namespace AmigoCapy
{
    /// <summary>Настройки в %APPDATA%\AmigoCapy\settings.ini.</summary>
    internal sealed class Settings
    {
        public int IntervalMs = 50;
        public bool PointMode;
        public bool HasPoint;
        public int PointX;
        public int PointY;
        public bool TwoPoints;

        /// <summary>За кого кликать в режиме точек: 0 — красные (точка 1), 1 — синие (точка 2), 2 — обе.</summary>
        public int Team;
        public bool HasPoint2;
        public int Point2X;
        public int Point2Y;
        public bool AlwaysOnTop;
        public HotKey HotKey = HotKey.Default;
        /// <summary>0 — кликер, 1 — подбор краски, 2 — мои краски.</summary>
        public int Tab;
        public string OwnedPaints = "";
        public bool OnlyMine;
        public string PaintWeapons = "";
        public int WindowWidth;
        public bool SoundOn = true;
        public bool ToastOn = true;
        public int WindowHeight;
        /// <summary>Таймер голда по клавише 7.</summary>
        public bool GoldTimerOn = true;

        private static string FilePath =>
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "AmigoCapy", "settings.ini");

        /// <summary>Где настройки лежали, пока программа называлась AmigoClick.</summary>
        private static string LegacyPath =>
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "AmigoClick", "settings.ini");

        public static Settings Load()
        {
            var s = new Settings();
            try
            {
                // После переименования один раз подхватываем старые настройки (точки, краски и т. д.).
                var path = File.Exists(FilePath) ? FilePath : LegacyPath;
                if (!File.Exists(path)) return s;
                var map = new Dictionary<string, string>();
                foreach (var line in File.ReadAllLines(path, Encoding.UTF8))
                {
                    int eq = line.IndexOf('=');
                    if (eq > 0) map[line.Substring(0, eq).Trim()] = line.Substring(eq + 1).Trim();
                }
                s.IntervalMs = Int(map, "interval", 50);
                s.PointMode = Int(map, "pointMode", 0) == 1;
                s.HasPoint = Int(map, "hasPoint", 0) == 1;
                s.PointX = Int(map, "pointX", 0);
                s.PointY = Int(map, "pointY", 0);
                s.TwoPoints = Int(map, "twoPoints", 0) == 1;
                s.Team = Int(map, "team", s.TwoPoints ? 2 : 0);
                s.HasPoint2 = Int(map, "hasPoint2", 0) == 1;
                s.Point2X = Int(map, "point2X", 0);
                s.Point2Y = Int(map, "point2Y", 0);
                s.AlwaysOnTop = Int(map, "onTop", 0) == 1;
                s.Tab = Int(map, "tab", Int(map, "paintsTab", 0));
                if (map.TryGetValue("ownedPaints", out var ownedPaints)) s.OwnedPaints = ownedPaints;
                s.OnlyMine = Int(map, "onlyMine", 0) == 1;
                if (map.TryGetValue("paintWeapons", out var weapons)) s.PaintWeapons = weapons;
                s.WindowWidth = Int(map, "windowWidth", 0);
                s.SoundOn = Int(map, "sound", 1) == 1;
                s.ToastOn = Int(map, "toast", 1) == 1;
                s.WindowHeight = Int(map, "windowHeight", 0);
                s.GoldTimerOn = Int(map, "goldTimer", 1) == 1;
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
                    "twoPoints=" + (TwoPoints ? 1 : 0),
                    "team=" + Team,
                    "hasPoint2=" + (HasPoint2 ? 1 : 0),
                    "point2X=" + Point2X,
                    "point2Y=" + Point2Y,
                    "onTop=" + (AlwaysOnTop ? 1 : 0),
                    "tab=" + Tab,
                    "ownedPaints=" + OwnedPaints,
                    "onlyMine=" + (OnlyMine ? 1 : 0),
                    "paintWeapons=" + PaintWeapons,
                    "windowWidth=" + WindowWidth,
                    "sound=" + (SoundOn ? 1 : 0),
                    "toast=" + (ToastOn ? 1 : 0),
                    "windowHeight=" + WindowHeight,
                    "goldTimer=" + (GoldTimerOn ? 1 : 0),
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
