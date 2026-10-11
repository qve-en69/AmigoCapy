using System.Diagnostics;
using System.Threading;

namespace AmigoClick
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

        /// <param name="target">null — кликать под курсором, иначе в эту точку (физические пиксели).</param>
        public void Start(int intervalMs, Native.POINT? target)
        {
            Stop();
            var run = new Run();
            current = run;
            var thread = new Thread(() => Loop(run, intervalMs, target))
            {
                IsBackground = true,
                Priority = ThreadPriority.AboveNormal,
                Name = "AmigoClick engine",
            };
            thread.Start();
        }

        public void Stop()
        {
            if (current != null) current.Stopped = true;
            current = null;
        }

        private void Loop(Run run, int intervalMs, Native.POINT? target)
        {
            Native.timeBeginPeriod(1);
            try
            {
                var clock = Stopwatch.StartNew();
                double next = 0;
                while (!run.Stopped)
                {
                    if (target.HasValue) Native.SetCursorPos(target.Value.X, target.Value.Y);
                    Native.LeftClick();
                    Interlocked.Increment(ref count);

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
