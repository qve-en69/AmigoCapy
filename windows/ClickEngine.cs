using System.Collections.Generic;
using System.Diagnostics;
using System.Threading;

namespace AmigoCapy
{
    /// <summary>
    /// Кликает в отдельном потоке по Stopwatch, чтобы ритм не зависел от интерфейса.
    /// </summary>
    internal sealed class ClickEngine
    {
        private sealed class Run
        {
            public volatile bool Stopped;
        }

        private Run current;
        private int count;

        public int Count => Volatile.Read(ref count);

        public void ResetCount() => Interlocked.Exchange(ref count, 0);

        /// <param name="targets">Пусто — кликать под курсором, иначе по очереди в эти точки (физические пиксели).</param>
        public void Start(int intervalMs, IReadOnlyList<Native.POINT> targets)
        {
            Stop();
            var run = new Run();
            current = run;
            var points = new List<Native.POINT>(targets ?? new Native.POINT[0]);
            var thread = new Thread(() => Loop(run, intervalMs, points))
            {
                IsBackground = true,
                Priority = ThreadPriority.AboveNormal,
                Name = "AmigoCapy engine",
            };
            thread.Start();
        }

        public void Stop()
        {
            if (current != null) current.Stopped = true;
            current = null;
        }

        private void Loop(Run run, int intervalMs, List<Native.POINT> targets)
        {
            Native.timeBeginPeriod(1);
            try
            {
                var clock = Stopwatch.StartNew();
                double next = 0;
                while (!run.Stopped)
                {
                    if (targets.Count == 0)
                    {
                        Native.LeftClick();
                        Interlocked.Increment(ref count);
                    }
                    for (int i = 0; i < targets.Count && !run.Stopped; i++)
                    {
                        // Небольшая пауза между точками, чтобы игра успела принять оба клика.
                        if (i > 0) Thread.Sleep(15);
                        Native.SetCursorPos(targets[i].X, targets[i].Y);
                        Native.LeftClick();
                        Interlocked.Increment(ref count);
                    }

                    next += intervalMs;
                    // Если поток надолго притормозили, не догоняем пачкой кликов.
                    if (clock.Elapsed.TotalMilliseconds - next > intervalMs * 5)
                        next = clock.Elapsed.TotalMilliseconds;

                    while (!run.Stopped)
                    {
                        double remaining = next - clock.Elapsed.TotalMilliseconds;
                        if (remaining <= 0) break;
                        if (remaining > 2) Thread.Sleep((int)System.Math.Min(50, remaining - 1));
                        else Thread.SpinWait(200);
                    }
                }
            }
            finally
            {
                Native.timeEndPeriod(1);
            }
        }
    }
}
