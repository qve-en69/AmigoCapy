using System;
using System.Windows.Input;
using System.Windows.Interop;

namespace AmigoCapy
{
    internal sealed class HotKey
    {
        public HotKey(uint vk, uint modifiers, string name)
        {
            Vk = vk;
            Modifiers = modifiers;
            Name = name;
        }

        public uint Vk { get; }
        public uint Modifiers { get; }
        public string Name { get; }

        /// <summary>Цифра 6 в верхнем ряду.</summary>
        public static HotKey Default => new HotKey(0x36, 0, "6");

        public string Display
        {
            get
            {
                var prefix = "";
                if ((Modifiers & Native.MOD_CONTROL) != 0) prefix += "Ctrl+";
                if ((Modifiers & Native.MOD_ALT) != 0) prefix += "Alt+";
                if ((Modifiers & Native.MOD_SHIFT) != 0) prefix += "Shift+";
                if ((Modifiers & Native.MOD_WIN) != 0) prefix += "Win+";
                return prefix + Name;
            }
        }

        public static uint ModifiersFrom(ModifierKeys keys)
        {
            uint result = 0;
            if (keys.HasFlag(ModifierKeys.Control)) result |= Native.MOD_CONTROL;
            if (keys.HasFlag(ModifierKeys.Alt)) result |= Native.MOD_ALT;
            if (keys.HasFlag(ModifierKeys.Shift)) result |= Native.MOD_SHIFT;
            if (keys.HasFlag(ModifierKeys.Windows)) result |= Native.MOD_WIN;
            return result;
        }

        public static bool IsModifier(Key key) =>
            key == Key.LeftCtrl || key == Key.RightCtrl || key == Key.LeftAlt || key == Key.RightAlt ||
            key == Key.LeftShift || key == Key.RightShift || key == Key.LWin || key == Key.RWin;

        /// <summary>Название клавиши для показа; null, если клавишу назвать не получается.</summary>
        public static string NameFor(Key key, int vk)
        {
            if (key >= Key.D0 && key <= Key.D9) return ((int)(key - Key.D0)).ToString();
            if (key >= Key.NumPad0 && key <= Key.NumPad9) return "Num " + (int)(key - Key.NumPad0);
            if (key >= Key.A && key <= Key.Z) return key.ToString();
            if (key >= Key.F1 && key <= Key.F24) return key.ToString();
            switch (key)
            {
                case Key.Space: return "Пробел";
                case Key.Enter: return "Enter";
                case Key.Tab: return "Tab";
                case Key.Back: return "Backspace";
                case Key.Insert: return "Insert";
                case Key.Delete: return "Delete";
                case Key.Home: return "Home";
                case Key.End: return "End";
                case Key.PageUp: return "PgUp";
                case Key.PageDown: return "PgDn";
                case Key.Left: return "←";
                case Key.Right: return "→";
                case Key.Up: return "↑";
                case Key.Down: return "↓";
                case Key.Pause: return "Pause";
                case Key.Scroll: return "Scroll Lock";
                case Key.Multiply: return "Num *";
                case Key.Add: return "Num +";
                case Key.Subtract: return "Num −";
                case Key.Divide: return "Num /";
                case Key.Decimal: return "Num .";
            }
            // Знаки препинания и прочие клавиши — по символу из текущей раскладки.
            uint ch = Native.MapVirtualKey((uint)vk, 2) & 0x7FFF;
            if (ch >= 32) return char.ToUpper((char)ch).ToString();
            return null;
        }
    }

    /// <summary>Системная горячая клавиша через RegisterHotKey — работает в любом окне.</summary>
    internal sealed class HotKeyService
    {
        private const int WM_HOTKEY = 0x0312;
        private readonly int id;
        private readonly IntPtr hwnd;
        private bool registered;

        public event Action Pressed;

        /// <param name="id">Свой номер для каждой клавиши: у кликера и таймера голда они разные.</param>
        public HotKeyService(IntPtr hwnd, int id)
        {
            this.hwnd = hwnd;
            this.id = id;
            HwndSource.FromHwnd(hwnd).AddHook(WndProc);
        }

        public bool Register(HotKey key)
        {
            Unregister();
            registered = Native.RegisterHotKey(hwnd, id, key.Modifiers | Native.MOD_NOREPEAT, key.Vk);
            return registered;
        }

        public void Unregister()
        {
            if (registered) Native.UnregisterHotKey(hwnd, id);
            registered = false;
        }

        private IntPtr WndProc(IntPtr h, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
        {
            if (msg == WM_HOTKEY && wParam.ToInt32() == id)
            {
                handled = true;
                Pressed?.Invoke();
            }
            return IntPtr.Zero;
        }
    }
}
