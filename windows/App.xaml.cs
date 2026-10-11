using System;
using System.Diagnostics;
using System.Linq;
using System.Windows;

namespace AmigoCapy
{
    public partial class App : Application
    {
        protected override void OnStartup(StartupEventArgs e)
        {
            Theme.Apply(Resources);
            StopGuard.AcceptTestInput = e.Args.Contains("--test-input");
            // --allow-second — только для автотестов рядом с уже открытой копией.
            if (!e.Args.Contains("--allow-second") && !CloseOtherCopies())
            {
                Shutdown();
                return;
            }
            base.OnStartup(e);
        }

        /// <summary>Наши копии — и новые AmigoCapy, и старые AmigoClick.</summary>
        private static bool IsOurName(string name) =>
            name.StartsWith("AmigoCapy", StringComparison.OrdinalIgnoreCase) ||
            name.StartsWith("AmigoClick", StringComparison.OrdinalIgnoreCase);

        /// <summary>
        /// Две копии кликера мешают друг другу: клавиша старта достаётся только одной,
        /// и вторую становится нечем остановить. Предлагаем закрыть старую копию.
        /// </summary>
        /// <returns>false — пользователь решил не открывать эту копию.</returns>
        private static bool CloseOtherCopies()
        {
            var me = Process.GetCurrentProcess();
            var others = Process.GetProcesses()
                .Where(p => p.Id != me.Id && IsOurName(p.ProcessName))
                .ToList();
            if (others.Count == 0) return true;

            var names = string.Join(", ", others.Select(p => p.ProcessName + ".exe").Distinct());
            var answer = MessageBox.Show(
                "Уже открыта другая копия кликера (" + names + ").\n\n" +
                "Две копии мешают друг другу: клавиша старта работает только в одной из них, " +
                "и кликер может не остановиться.\n\n" +
                "Закрыть старую копию и открыть эту?",
                "AmigoCapy уже запущен",
                MessageBoxButton.YesNo,
                MessageBoxImage.Warning,
                MessageBoxResult.Yes);
            if (answer != MessageBoxResult.Yes) return false;

            foreach (var other in others)
            {
                try
                {
                    // Сначала по-хорошему (копия сохранит настройки), потом принудительно.
                    other.CloseMainWindow();
                    if (!other.WaitForExit(3000))
                    {
                        other.Kill();
                        other.WaitForExit(2000);
                    }
                }
                catch
                {
                    // Процесс уже закрылся или нет прав — просто идём дальше.
                }
            }
            return true;
        }
    }
}
