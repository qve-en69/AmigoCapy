using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Media;
using System.Text;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Effects;
using System.Windows.Threading;

namespace AmigoCapy
{
    /// <summary>Короткие звуки старта и остановки кликов (генерируются на лету, без файлов).</summary>
    internal static class Sounds
    {
        private static readonly SoundPlayer StartSound = Make(660, 990);
        private static readonly SoundPlayer StopSound = Make(880, 520);
        private static readonly SoundPlayer TickSound = Make(740);

        /// <summary>Короткий тик для отсчёта 3-2-1.</summary>
        public static void Tick()
        {
            try
            {
                TickSound.Play();
            }
            catch
            {
                // Нет звукового устройства — просто молчим.
            }
        }

        public static void Play(bool started)
        {
            try
            {
                (started ? StartSound : StopSound).Play();
            }
            catch
            {
                // Нет звукового устройства — просто молчим.
            }
        }

        /// <summary>Два коротких тона подряд: вверх — старт, вниз — стоп.</summary>
        private static SoundPlayer Make(params double[] notes)
        {
            const int rate = 44100;
            const int noteMs = 70;
            const int gapMs = 15;
            var samples = new List<short>();
            foreach (var freq in notes)
            {
                int n = rate * noteMs / 1000;
                for (int i = 0; i < n; i++)
                {
                    double attack = Math.Min(1, i / (rate * 0.005));
                    double release = Math.Min(1, (n - i) / (rate * 0.02));
                    double value = Math.Sin(2 * Math.PI * freq * i / rate) * attack * release * 0.22;
                    samples.Add((short)(value * short.MaxValue));
                }
                samples.AddRange(Enumerable.Repeat((short)0, rate * gapMs / 1000));
            }

            var stream = new MemoryStream();
            var w = new BinaryWriter(stream);
            int dataLength = samples.Count * 2;
            w.Write(Encoding.ASCII.GetBytes("RIFF"));
            w.Write(36 + dataLength);
            w.Write(Encoding.ASCII.GetBytes("WAVEfmt "));
            w.Write(16);
            w.Write((short)1);        // PCM
            w.Write((short)1);        // моно
            w.Write(rate);
            w.Write(rate * 2);
            w.Write((short)2);
            w.Write((short)16);
            w.Write(Encoding.ASCII.GetBytes("data"));
            w.Write(dataLength);
            foreach (var s in samples) w.Write(s);
            stream.Position = 0;

            var player = new SoundPlayer(stream);
            player.Load();
            return player;
        }
    }

    /// <summary>
    /// Плашка «Кликер включён / выключен» сверху экрана на секунду с небольшим.
    /// Не забирает фокус и пропускает клики сквозь себя, поэтому не мешает игре.
    /// </summary>
    internal sealed class ToastWindow : Window
    {
        private const int GWL_EXSTYLE = -20;
        private const int WS_EX_TRANSPARENT = 0x20;
        private const int WS_EX_TOOLWINDOW = 0x80;
        private const int WS_EX_NOACTIVATE = 0x08000000;

        private static ToastWindow current;
        private bool closed;

        public static void Show(bool started, string hint)
        {
            current?.CloseOnce();
            current = new ToastWindow(started, hint);
            current.Show();
        }

        private ToastWindow(bool started, string hint)
        {
            WindowStyle = WindowStyle.None;
            AllowsTransparency = true;
            Background = Brushes.Transparent;
            ResizeMode = ResizeMode.NoResize;
            SizeToContent = SizeToContent.WidthAndHeight;
            Topmost = true;
            ShowInTaskbar = false;
            ShowActivated = false;
            Focusable = false;
            IsHitTestVisible = false;
            WindowStartupLocation = WindowStartupLocation.Manual;
            Left = -10000;
            Top = -10000;
            Opacity = 0;

            var app = Application.Current;
            var row = new StackPanel { Orientation = Orientation.Horizontal };
            row.Children.Add(new TextBlock
            {
                Text = started ? "" : "",
                FontFamily = (FontFamily)app.FindResource("IconFont"),
                FontSize = 14,
                Foreground = Brushes.White,
                VerticalAlignment = VerticalAlignment.Center,
                Margin = new Thickness(0, 1, 10, 0),
            });
            row.Children.Add(new TextBlock
            {
                Text = started ? "Кликер включён" : "Кликер выключен",
                FontFamily = new FontFamily("Segoe UI"),
                FontSize = 15,
                FontWeight = FontWeights.SemiBold,
                Foreground = Brushes.White,
                VerticalAlignment = VerticalAlignment.Center,
            });
            if (!string.IsNullOrEmpty(hint))
            {
                row.Children.Add(new TextBlock
                {
                    Text = hint,
                    FontFamily = new FontFamily("Segoe UI"),
                    FontSize = 12.5,
                    Foreground = Brushes.White,
                    Opacity = 0.8,
                    VerticalAlignment = VerticalAlignment.Center,
                    Margin = new Thickness(12, 1, 0, 0),
                });
            }

            Content = new Border
            {
                Background = (Brush)app.FindResource(started ? "StartGradient" : "StopGradient"),
                CornerRadius = new CornerRadius(16),
                Padding = new Thickness(18, 10, 20, 11),
                Margin = new Thickness(16),
                Child = row,
                Effect = new DropShadowEffect { BlurRadius = 16, ShadowDepth = 3, Direction = 270, Opacity = 0.35 },
            };

            Closed += (s, e) => closed = true;
            SourceInitialized += (s, e) =>
            {
                var hwnd = new WindowInteropHelper(this).Handle;
                int style = Native.GetWindowLong(hwnd, GWL_EXSTYLE);
                Native.SetWindowLong(hwnd, GWL_EXSTYLE, style | WS_EX_TRANSPARENT | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE);
            };
            Loaded += (s, e) =>
            {
                PlaceAtTopOfCursorScreen();
                Animate();
            };
        }

        private void PlaceAtTopOfCursorScreen()
        {
            var monitors = Native.MonitorRects();
            if (monitors.Count == 0) return;
            Native.GetCursorPos(out var cursor);
            var monitor = monitors.FirstOrDefault(m => m.Contains(cursor));
            if (!monitor.Contains(cursor)) monitor = monitors[0];

            var dpi = VisualTreeHelper.GetDpi(this);
            int width = (int)(ActualWidth * dpi.DpiScaleX);
            int x = monitor.Left + (monitor.Width - width) / 2;
            int y = monitor.Top + (int)(24 * dpi.DpiScaleY);
            var hwnd = new WindowInteropHelper(this).Handle;
            Native.SetWindowPos(hwnd, Native.HWND_TOPMOST, x, y, 0, 0, Native.SWP_NOSIZE | Native.SWP_NOACTIVATE);
        }

        private void Animate()
        {
            var fade = new DoubleAnimationUsingKeyFrames();
            fade.KeyFrames.Add(new LinearDoubleKeyFrame(1, KeyTime.FromTimeSpan(TimeSpan.FromMilliseconds(120))));
            fade.KeyFrames.Add(new LinearDoubleKeyFrame(1, KeyTime.FromTimeSpan(TimeSpan.FromMilliseconds(1100))));
            fade.KeyFrames.Add(new LinearDoubleKeyFrame(0, KeyTime.FromTimeSpan(TimeSpan.FromMilliseconds(1500))));
            fade.Completed += (s, e) => CloseOnce();
            BeginAnimation(OpacityProperty, fade);
        }

        private void CloseOnce()
        {
            if (closed) return;
            closed = true;
            Close();
            if (current == this) current = null;
        }
    }

    /// <summary>
    /// Плашка с отсчётом сверху экрана («Перезаход через 3»). Висит, пока её не закроют,
    /// не забирает фокус и пропускает клики сквозь себя.
    /// </summary>
    internal sealed class CountdownWindow : Window
    {
        private const int GWL_EXSTYLE = -20;
        private const int WS_EX_TRANSPARENT = 0x20;
        private const int WS_EX_TOOLWINDOW = 0x80;
        private const int WS_EX_NOACTIVATE = 0x08000000;

        private readonly TextBlock number;
        private bool closed;

        public static CountdownWindow Open(string text, int value, string gradient = "WaitGradient")
        {
            var window = new CountdownWindow(text, value, gradient);
            window.Show();
            return window;
        }

        private CountdownWindow(string text, int value, string gradient)
        {
            WindowStyle = WindowStyle.None;
            AllowsTransparency = true;
            Background = Brushes.Transparent;
            ResizeMode = ResizeMode.NoResize;
            SizeToContent = SizeToContent.WidthAndHeight;
            Topmost = true;
            ShowInTaskbar = false;
            ShowActivated = false;
            Focusable = false;
            IsHitTestVisible = false;
            WindowStartupLocation = WindowStartupLocation.Manual;
            Left = -10000;
            Top = -10000;

            var app = Application.Current;
            var row = new StackPanel { Orientation = Orientation.Horizontal };
            row.Children.Add(new TextBlock
            {
                Text = "\uE72C",
                FontFamily = (FontFamily)app.FindResource("IconFont"),
                FontSize = 16,
                Foreground = Brushes.White,
                VerticalAlignment = VerticalAlignment.Center,
                Margin = new Thickness(0, 2, 12, 0),
            });
            row.Children.Add(new TextBlock
            {
                Text = text,
                FontFamily = new FontFamily("Segoe UI"),
                FontSize = 17,
                FontWeight = FontWeights.SemiBold,
                Foreground = Brushes.White,
                VerticalAlignment = VerticalAlignment.Center,
            });
            number = new TextBlock
            {
                Text = value.ToString(),
                FontFamily = new FontFamily("Segoe UI"),
                FontSize = 26,
                FontWeight = FontWeights.Bold,
                Foreground = Brushes.White,
                VerticalAlignment = VerticalAlignment.Center,
                Margin = new Thickness(12, -2, 0, 0),
            };
            row.Children.Add(number);

            Content = new Border
            {
                Background = (Brush)app.FindResource(gradient),
                CornerRadius = new CornerRadius(18),
                Padding = new Thickness(22, 10, 26, 12),
                Margin = new Thickness(16),
                Child = row,
                Effect = new DropShadowEffect { BlurRadius = 18, ShadowDepth = 3, Direction = 270, Opacity = 0.4 },
            };

            Closed += (s, e) => closed = true;
            SourceInitialized += (s, e) =>
            {
                var hwnd = new WindowInteropHelper(this).Handle;
                int style = Native.GetWindowLong(hwnd, GWL_EXSTYLE);
                Native.SetWindowLong(hwnd, GWL_EXSTYLE, style | WS_EX_TRANSPARENT | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE);
            };
            Loaded += (s, e) => Place();
        }

        public void SetNumber(int value)
        {
            number.Text = value.ToString();
            var pop = new DoubleAnimation(0.4, 1, TimeSpan.FromMilliseconds(180));
            number.BeginAnimation(OpacityProperty, pop);
        }

        public void CloseBanner()
        {
            if (closed) return;
            closed = true;
            Close();
        }

        private void Place()
        {
            var monitors = Native.MonitorRects();
            if (monitors.Count == 0) return;
            Native.GetCursorPos(out var cursor);
            var monitor = monitors.FirstOrDefault(m => m.Contains(cursor));
            if (!monitor.Contains(cursor)) monitor = monitors[0];

            var dpi = VisualTreeHelper.GetDpi(this);
            int width = (int)(ActualWidth * dpi.DpiScaleX);
            int x = monitor.Left + (monitor.Width - width) / 2;
            int y = monitor.Top + (int)(24 * dpi.DpiScaleY);
            var hwnd = new WindowInteropHelper(this).Handle;
            Native.SetWindowPos(hwnd, Native.HWND_TOPMOST, x, y, 0, 0, Native.SWP_NOSIZE | Native.SWP_NOACTIVATE);
        }
    }

    /// <summary>
    /// Таймер голда сверху экрана: «Голд упадёт примерно через 45 с», цифры убывают,
    /// а в конце — «Удачи, маленький амигос!!». Не забирает фокус и пропускает клики сквозь себя.
    /// </summary>
    internal sealed class GoldTimerWindow : Window
    {
        public const int Seconds = 45;

        private const int GWL_EXSTYLE = -20;
        private const int WS_EX_TRANSPARENT = 0x20;
        private const int WS_EX_TOOLWINDOW = 0x80;
        private const int WS_EX_NOACTIVATE = 0x08000000;

        private static readonly Color Ink = Color.FromRgb(0x3A, 0x27, 0x00);
        private static readonly Color Hurry = Color.FromRgb(0xB3, 0x26, 0x1E);
        private static GoldTimerWindow current;

        private readonly Stopwatch clock = Stopwatch.StartNew();
        private readonly DispatcherTimer timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(50) };
        private readonly bool sound;
        private readonly TextBlock title;
        private readonly TextBlock number;
        private readonly TextBlock unit;
        private readonly Border track;
        private readonly ScaleTransform progress = new ScaleTransform(1, 1);
        private readonly ScaleTransform pop = new ScaleTransform(1, 1);
        private Native.RECT monitor;
        private int shown = Seconds;
        private bool finished;
        private bool closed;

        /// <summary>Идёт ли сейчас отсчёт (табличка «удачи» уже не считается).</summary>
        public static bool IsRunning => current != null && !current.finished;

        /// <summary>Отсчёт начался, закончился или сброшен.</summary>
        public static event Action TimerChanged;

        /// <summary>Клавиша 7: запустить таймер, а если он уже идёт — сбросить.</summary>
        public static void Toggle(bool sound)
        {
            bool wasRunning = IsRunning;
            CloseCurrent();
            if (!wasRunning)
            {
                current = new GoldTimerWindow(sound);
                current.Show();
            }
            if (sound) Sounds.Play(!wasRunning);
            TimerChanged?.Invoke();
        }

        public static void CloseCurrent()
        {
            current?.CloseOnce();
            current = null;
        }

        private GoldTimerWindow(bool sound)
        {
            this.sound = sound;
            WindowStyle = WindowStyle.None;
            AllowsTransparency = true;
            Background = Brushes.Transparent;
            ResizeMode = ResizeMode.NoResize;
            SizeToContent = SizeToContent.WidthAndHeight;
            Topmost = true;
            ShowInTaskbar = false;
            ShowActivated = false;
            Focusable = false;
            IsHitTestVisible = false;
            WindowStartupLocation = WindowStartupLocation.Manual;
            Left = -10000;
            Top = -10000;

            var ink = new SolidColorBrush(Ink);
            var font = new FontFamily("Segoe UI");

            // Монетка с буквой G.
            var coin = new Grid
            {
                Width = 28,
                Height = 28,
                Margin = new Thickness(0, 0, 12, 0),
                VerticalAlignment = VerticalAlignment.Center,
            };
            coin.Children.Add(new System.Windows.Shapes.Ellipse
            {
                Fill = new SolidColorBrush(Color.FromRgb(0xFF, 0xFB, 0xEA)),
                Stroke = new SolidColorBrush(Color.FromRgb(0x9A, 0x66, 0x00)),
                StrokeThickness = 2,
            });
            coin.Children.Add(new TextBlock
            {
                Text = "G",
                FontFamily = font,
                FontSize = 15,
                FontWeight = FontWeights.Black,
                Foreground = new SolidColorBrush(Color.FromRgb(0xD9, 0x8E, 0x04)),
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center,
                Margin = new Thickness(0, -1, 0, 0),
            });

            title = new TextBlock
            {
                Text = "Голд упадёт примерно через",
                FontFamily = font,
                FontSize = 17,
                FontWeight = FontWeights.SemiBold,
                Foreground = ink,
                VerticalAlignment = VerticalAlignment.Center,
            };
            number = new TextBlock
            {
                Text = Seconds.ToString(),
                FontFamily = font,
                FontSize = 28,
                FontWeight = FontWeights.Bold,
                Foreground = ink,
                MinWidth = 36,
                TextAlignment = TextAlignment.Right,
                VerticalAlignment = VerticalAlignment.Center,
                Margin = new Thickness(10, -4, 0, 0),
                RenderTransformOrigin = new Point(0.5, 0.5),
                RenderTransform = pop,
            };
            unit = new TextBlock
            {
                Text = "с",
                FontFamily = font,
                FontSize = 17,
                FontWeight = FontWeights.SemiBold,
                Foreground = ink,
                VerticalAlignment = VerticalAlignment.Center,
                Margin = new Thickness(5, 0, 0, 0),
            };

            var row = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Center };
            row.Children.Add(coin);
            row.Children.Add(title);
            row.Children.Add(number);
            row.Children.Add(unit);

            // Полоска убывает вместе с таймером.
            track = new Border
            {
                Height = 5,
                CornerRadius = new CornerRadius(2.5),
                Background = new SolidColorBrush(Color.FromArgb(0x33, Ink.R, Ink.G, Ink.B)),
                Margin = new Thickness(0, 8, 0, 0),
                Child = new Border
                {
                    CornerRadius = new CornerRadius(2.5),
                    Background = ink,
                    RenderTransformOrigin = new Point(0, 0.5),
                    RenderTransform = progress,
                },
            };

            var stack = new StackPanel();
            stack.Children.Add(row);
            stack.Children.Add(track);

            Content = new Border
            {
                Background = (Brush)Application.Current.FindResource("GoldGradient"),
                BorderBrush = new SolidColorBrush(Color.FromArgb(0x66, 0xFF, 0xFF, 0xFF)),
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(18),
                Padding = new Thickness(18, 10, 24, 12),
                Margin = new Thickness(16),
                MinWidth = 300,
                RenderTransformOrigin = new Point(0.5, 0.5),
                Child = stack,
                Effect = new DropShadowEffect { BlurRadius = 18, ShadowDepth = 3, Direction = 270, Opacity = 0.4 },
            };

            timer.Tick += (s, e) => Update();
            Closed += (s, e) =>
            {
                closed = true;
                timer.Stop();
            };
            SourceInitialized += (s, e) =>
            {
                var hwnd = new WindowInteropHelper(this).Handle;
                int style = Native.GetWindowLong(hwnd, GWL_EXSTYLE);
                Native.SetWindowLong(hwnd, GWL_EXSTYLE, style | WS_EX_TRANSPARENT | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE);
            };
            Loaded += (s, e) =>
            {
                monitor = PickMonitor();
                Place();
                timer.Start();
            };
            // Текст «удачи» шире отсчёта — держим табличку по центру.
            SizeChanged += (s, e) => Place();
        }

        private void Update()
        {
            double left = Seconds - clock.Elapsed.TotalSeconds;
            if (left <= 0)
            {
                Finish();
                return;
            }
            progress.ScaleX = left / Seconds;

            int whole = (int)Math.Ceiling(left);
            if (whole == shown) return;
            shown = whole;
            number.Text = whole.ToString();
            if (whole <= 10)
            {
                // Последние 10 секунд — красные цифры с «толчком».
                number.Foreground = new SolidColorBrush(Hurry);
                var bump = new DoubleAnimation(1.25, 1, TimeSpan.FromMilliseconds(260));
                pop.BeginAnimation(ScaleTransform.ScaleXProperty, bump);
                pop.BeginAnimation(ScaleTransform.ScaleYProperty, bump);
            }
            if (whole <= 3 && sound) Sounds.Tick();
        }

        private void Finish()
        {
            if (finished) return;
            finished = true;
            timer.Stop();
            title.Text = "Удачи, маленький амигос!!";
            title.FontSize = 19;
            title.FontWeight = FontWeights.Bold;
            number.Visibility = Visibility.Collapsed;
            unit.Visibility = Visibility.Collapsed;
            track.Visibility = Visibility.Collapsed;
            if (sound) Sounds.Play(true);
            TimerChanged?.Invoke();

            var scale = new ScaleTransform(1, 1);
            ((Border)Content).RenderTransform = scale;
            var bump = new DoubleAnimation(0.85, 1, TimeSpan.FromMilliseconds(320))
            {
                EasingFunction = new BackEase { EasingMode = EasingMode.EaseOut, Amplitude = 0.6 },
            };
            scale.BeginAnimation(ScaleTransform.ScaleXProperty, bump);
            scale.BeginAnimation(ScaleTransform.ScaleYProperty, bump);

            var fade = new DoubleAnimationUsingKeyFrames();
            fade.KeyFrames.Add(new LinearDoubleKeyFrame(1, KeyTime.FromTimeSpan(TimeSpan.FromMilliseconds(7000))));
            fade.KeyFrames.Add(new LinearDoubleKeyFrame(0, KeyTime.FromTimeSpan(TimeSpan.FromMilliseconds(7600))));
            fade.Completed += (s, e) =>
            {
                if (current == this) current = null;
                CloseOnce();
            };
            BeginAnimation(OpacityProperty, fade);
        }

        private static Native.RECT PickMonitor()
        {
            var monitors = Native.MonitorRects();
            if (monitors.Count == 0) return default(Native.RECT);
            Native.GetCursorPos(out var cursor);
            var monitor = monitors.FirstOrDefault(m => m.Contains(cursor));
            return monitor.Contains(cursor) ? monitor : monitors[0];
        }

        /// <summary>По центру сверху того монитора, где был курсор при старте (обычно там игра).</summary>
        private void Place()
        {
            if (closed || monitor.Width == 0) return;
            var dpi = VisualTreeHelper.GetDpi(this);
            int width = (int)(ActualWidth * dpi.DpiScaleX);
            int x = monitor.Left + (monitor.Width - width) / 2;
            int y = monitor.Top + (int)(24 * dpi.DpiScaleY);
            var hwnd = new WindowInteropHelper(this).Handle;
            Native.SetWindowPos(hwnd, Native.HWND_TOPMOST, x, y, 0, 0, Native.SWP_NOSIZE | Native.SWP_NOACTIVATE);
        }

        private void CloseOnce()
        {
            if (closed) return;
            closed = true;
            timer.Stop();
            Close();
        }
    }

    /// <summary>Подсвечивает на экране, где стоят выбранные точки: кольцо и подпись на 3 секунды.</summary>
    internal static class PointMarkers
    {
        private static readonly List<MarkerWindow> Open = new List<MarkerWindow>();

        public static void Show(IEnumerable<(Native.POINT point, string label, Color color)> markers)
        {
            foreach (var window in Open.ToList()) window.CloseMarker();
            Open.Clear();
            foreach (var (point, label, color) in markers)
            {
                var window = new MarkerWindow(point, label, color);
                Open.Add(window);
                window.Show();
            }
        }

        private sealed class MarkerWindow : Window
        {
            private const int GWL_EXSTYLE = -20;
            private const int WS_EX_TRANSPARENT = 0x20;
            private const int WS_EX_TOOLWINDOW = 0x80;
            private const int WS_EX_NOACTIVATE = 0x08000000;
            private const double Width0 = 170;
            private const double RingSize = 40;
            private const double RingTop = 6;

            private readonly Native.POINT point;
            private bool closed;

            public MarkerWindow(Native.POINT point, string label, Color color)
            {
                this.point = point;
                WindowStyle = WindowStyle.None;
                AllowsTransparency = true;
                Background = Brushes.Transparent;
                ResizeMode = ResizeMode.NoResize;
                Width = Width0;
                Height = 100;
                Topmost = true;
                ShowInTaskbar = false;
                ShowActivated = false;
                Focusable = false;
                IsHitTestVisible = false;
                WindowStartupLocation = WindowStartupLocation.Manual;
                Left = -10000;
                Top = -10000;

                var brush = new SolidColorBrush(color);
                var scale = new ScaleTransform(1, 1);
                var ring = new System.Windows.Shapes.Ellipse
                {
                    Width = RingSize,
                    Height = RingSize,
                    Stroke = brush,
                    StrokeThickness = 3.5,
                    Fill = new SolidColorBrush(Color.FromArgb(0x40, color.R, color.G, color.B)),
                    HorizontalAlignment = HorizontalAlignment.Center,
                    VerticalAlignment = VerticalAlignment.Top,
                    Margin = new Thickness(0, RingTop, 0, 0),
                    RenderTransformOrigin = new Point(0.5, 0.5),
                    RenderTransform = scale,
                };
                var dot = new System.Windows.Shapes.Ellipse
                {
                    Width = 6,
                    Height = 6,
                    Fill = Brushes.White,
                    Stroke = brush,
                    StrokeThickness = 1.5,
                    HorizontalAlignment = HorizontalAlignment.Center,
                    VerticalAlignment = VerticalAlignment.Top,
                    Margin = new Thickness(0, RingTop + RingSize / 2 - 3, 0, 0),
                };
                var tag = new Border
                {
                    Background = brush,
                    CornerRadius = new CornerRadius(8),
                    Padding = new Thickness(9, 3, 9, 4),
                    HorizontalAlignment = HorizontalAlignment.Center,
                    VerticalAlignment = VerticalAlignment.Top,
                    Margin = new Thickness(0, RingTop + RingSize + 6, 0, 0),
                    Effect = new DropShadowEffect { BlurRadius = 8, ShadowDepth = 1, Direction = 270, Opacity = 0.4 },
                    Child = new TextBlock
                    {
                        Text = label + "  ·  " + point.X + ", " + point.Y,
                        FontFamily = new FontFamily("Segoe UI"),
                        FontSize = 12.5,
                        FontWeight = FontWeights.SemiBold,
                        Foreground = Brushes.White,
                    },
                };
                var grid = new Grid();
                grid.Children.Add(ring);
                grid.Children.Add(dot);
                grid.Children.Add(tag);
                Content = grid;

                var pulse = new DoubleAnimation(1, 1.35, TimeSpan.FromMilliseconds(500))
                {
                    AutoReverse = true,
                    RepeatBehavior = RepeatBehavior.Forever,
                };
                scale.BeginAnimation(ScaleTransform.ScaleXProperty, pulse);
                scale.BeginAnimation(ScaleTransform.ScaleYProperty, pulse);

                Closed += (s, e) => closed = true;
                SourceInitialized += (s, e) =>
                {
                    var hwnd = new WindowInteropHelper(this).Handle;
                    int style = Native.GetWindowLong(hwnd, GWL_EXSTYLE);
                    Native.SetWindowLong(hwnd, GWL_EXSTYLE, style | WS_EX_TRANSPARENT | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE);
                };
                Loaded += (s, e) =>
                {
                    Place();
                    var fade = new DoubleAnimationUsingKeyFrames();
                    fade.KeyFrames.Add(new LinearDoubleKeyFrame(1, KeyTime.FromTimeSpan(TimeSpan.FromMilliseconds(2600))));
                    fade.KeyFrames.Add(new LinearDoubleKeyFrame(0, KeyTime.FromTimeSpan(TimeSpan.FromMilliseconds(3100))));
                    fade.Completed += (s2, e2) => CloseMarker();
                    BeginAnimation(OpacityProperty, fade);
                };
            }

            /// <summary>Центр кольца — ровно в точке клика (физические пиксели).</summary>
            private void Place()
            {
                var dpi = VisualTreeHelper.GetDpi(this);
                int x = point.X - (int)(Width0 / 2 * dpi.DpiScaleX);
                int y = point.Y - (int)((RingTop + RingSize / 2) * dpi.DpiScaleY);
                var hwnd = new WindowInteropHelper(this).Handle;
                Native.SetWindowPos(hwnd, Native.HWND_TOPMOST, x, y, 0, 0, Native.SWP_NOSIZE | Native.SWP_NOACTIVATE);
            }

            public void CloseMarker()
            {
                if (closed) return;
                closed = true;
                Close();
            }
        }
    }
}
