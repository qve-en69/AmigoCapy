using System;
using System.Runtime.InteropServices;

namespace AmigoCapy
{
    /// <summary>
    /// Аварийная остановка, которая не зависит от горячей клавиши.
    /// Пока кликер работает, слушает настоящие (не наши) нажатия через низкоуровневый хук клавиатуры:
    /// Esc или клавиша старта — стоп, даже если клавишу старта перехватила другая программа.
    /// </summary>
    internal sealed class StopGuard
    {
        private const int WH_KEYBOARD_LL = 13;
        private const int WM_KEYDOWN = 0x0100;
        private const int WM_SYSKEYDOWN = 0x0104;
        private const int LLKHF_INJECTED = 0x10;

        [StructLayout(LayoutKind.Sequential)]
        private struct KBDLLHOOKSTRUCT
        {
            public uint vkCode;
            public uint scanCode;
            public uint flags;
            public uint time;
            public IntPtr dwExtraInfo;
        }

        private delegate IntPtr HookProc(int code, IntPtr wParam, IntPtr lParam);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern IntPtr SetWindowsHookEx(int idHook, HookProc proc, IntPtr hMod, uint threadId);

        [DllImport("user32.dll")]
        private static extern bool UnhookWindowsHookEx(IntPtr hook);

        [DllImport("user32.dll")]
        private static extern IntPtr CallNextHookEx(IntPtr hook, int code, IntPtr wParam, IntPtr lParam);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
        private static extern IntPtr GetModuleHandle(string name);

        // Делегат держим в поле, иначе сборщик мусора его удалит, пока Windows ещё вызывает хук.
        private readonly HookProc keyboardProc;
        private IntPtr keyboardHook;

        /// <summary>Метка в dwExtraInfo, которой автотест помечает «как будто настоящие» нажатия.</summary>
        private static readonly IntPtr TestMarker = new IntPtr(0xA5C1);

        /// <summary>Запуск с --test-input: события с меткой автотеста считаются настоящими.</summary>
        public static bool AcceptTestInput;

        /// <summary>Клавиша старта/стопа (только без модификаторов) — тоже останавливает.</summary>
        public uint StopVk;

        /// <summary>Вызывается в UI-потоке; аргумент — причина для подсказки.</summary>
        public event Action<string> Triggered;

        public StopGuard()
        {
            keyboardProc = KeyboardHook;
        }

        /// <param name="active">Слушать Esc и клавишу старта (во время кликов и отсчётов).</param>
        public void Update(bool active)
        {
            if (active && keyboardHook == IntPtr.Zero)
                keyboardHook = SetWindowsHookEx(WH_KEYBOARD_LL, keyboardProc, GetModuleHandle(null), 0);
            if (!active && keyboardHook != IntPtr.Zero)
            {
                UnhookWindowsHookEx(keyboardHook);
                keyboardHook = IntPtr.Zero;
            }
        }

        public void Dispose() => Update(false);

        private IntPtr KeyboardHook(int code, IntPtr wParam, IntPtr lParam)
        {
            if (code >= 0)
            {
                int msg = wParam.ToInt32();
                var data = (KBDLLHOOKSTRUCT)Marshal.PtrToStructure(lParam, typeof(KBDLLHOOKSTRUCT));
                bool physical = (data.flags & LLKHF_INJECTED) == 0 || IsTest(data.dwExtraInfo);
                if (physical && (msg == WM_KEYDOWN || msg == WM_SYSKEYDOWN))
                {
                    if (data.vkCode == Native.VK_ESCAPE)
                    {
                        // Esc «съедаем», чтобы в игре не открылось меню выхода.
                        Fire("нажат Esc");
                        return new IntPtr(1);
                    }
                    if (StopVk != 0 && data.vkCode == StopVk)
                    {
                        // Глотаем, чтобы та же клавиша сразу не запустила кликер снова (в том числе в другой копии).
                        Fire(null);
                        return new IntPtr(1);
                    }
                }
            }
            return CallNextHookEx(keyboardHook, code, wParam, lParam);
        }

        private static bool IsTest(IntPtr extra) => AcceptTestInput && extra == TestMarker;

        private void Fire(string reason)
        {
            // Сам хук должен отработать мгновенно — остановку делаем чуть позже в UI-потоке.
            System.Windows.Application.Current?.Dispatcher.BeginInvoke(new Action(() => Triggered?.Invoke(reason)));
        }
    }
}
