using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Shapes;

namespace AmigoCapy
{
    /// <summary>Затемняет все мониторы; клик выбирает точку, Esc или правый клик — отмена.</summary>
    internal sealed class PickerSession
    {
        private readonly List<PickerWindow> windows = new List<PickerWindow>();
        private readonly string hint;
        private bool finished;

        public PickerSession(string hint = "Кликни в нужное место")
        {
            this.hint = hint;
        }

        /// <summary>Точка в физических пикселях экрана или null при отмене.</summary>
        public event Action<Native.POINT?> Completed;

        public void Start()
        {
            foreach (var rect in Native.MonitorRects())
            {
                var window = new PickerWindow(rect, hint);
                window.Picked += Finish;
                windows.Add(window);
                window.Show();
            }

            Native.GetCursorPos(out var cursor);
            var underCursor = windows.FirstOrDefault(w => w.Bounds.Contains(cursor)) ?? windows.FirstOrDefault();
            underCursor?.Activate();
        }

        private void Finish(Native.POINT? point)
        {
            if (finished) return;
            finished = true;
            foreach (var window in windows) window.Close();
            windows.Clear();
            Completed?.Invoke(point);
        }
    }

    internal sealed class PickerWindow : Window
    {
        private const double RingRadius = 16;

        private static readonly Color Accent = Color.FromRgb(0x29, 0xCC, 0x9E);

        private readonly Canvas canvas = new Canvas { IsHitTestVisible = false };
        private readonly RectangleGeometry fullArea = new RectangleGeometry();
        private readonly EllipseGeometry hole = new EllipseGeometry(new Point(-100, -100), RingRadius, RingRadius);
        private readonly Line horizontal = MakeLine();
        private readonly Line vertical = MakeLine();
        private readonly Ellipse ring = new Ellipse
        {
            Width = RingRadius * 2,
            Height = RingRadius * 2,
            Stroke = new SolidColorBrush(Accent),
            StrokeThickness = 2.5,
        };
        private readonly Ellipse dot = new Ellipse { Width = 4, Height = 4, Fill = new SolidColorBrush(Accent) };
        private readonly TextBlock labelText = new TextBlock
        {
            Foreground = Brushes.White,
            FontFamily = new FontFamily("Consolas"),
            FontWeight = FontWeights.SemiBold,
            FontSize = 12.5,
        };
        private readonly Border label;

        public PickerWindow(Native.RECT bounds, string hintText)
        {
            Bounds = bounds;

            WindowStyle = WindowStyle.None;
            AllowsTransparency = true;
            ResizeMode = ResizeMode.NoResize;
            ShowInTaskbar = false;
            Topmost = true;
            Cursor = Cursors.Cross;
            // Почти прозрачный, но не нулевой фон — иначе клики пройдут сквозь окно.
            Background = new SolidColorBrush(Color.FromArgb(1, 0, 0, 0));
            WindowStartupLocation = WindowStartupLocation.Manual;
            Left = bounds.Left;
            Top = bounds.Top;
            Width = bounds.Width;
            Height = bounds.Height;

            label = new Border
            {
                Background = new SolidColorBrush(Color.FromArgb(0xF2, 0x12, 0x80, 0x78)),
                CornerRadius = new CornerRadius(7),
                Padding = new Thickness(10, 5, 10, 5),
                Child = labelText,
            };

            var dim = new Path
            {
                Fill = new SolidColorBrush(Color.FromArgb(0x55, 0, 0, 0)),
                Data = new CombinedGeometry(GeometryCombineMode.Exclude, fullArea, hole),
                IsHitTestVisible = false,
            };

            var hint = new Border
            {
                Background = new SolidColorBrush(Color.FromArgb(0x99, 0, 0, 0)),
                CornerRadius = new CornerRadius(19),
                Padding = new Thickness(20, 9, 20, 10),
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Top,
                Margin = new Thickness(0, 80, 0, 0),
                IsHitTestVisible = false,
                Child = new TextBlock
                {
                    Text = hintText + "   ·   Esc — отмена",
                    Foreground = Brushes.White,
                    FontFamily = new FontFamily("Segoe UI"),
                    FontSize = 14,
                    FontWeight = FontWeights.Medium,
                },
            };

            canvas.Children.Add(horizontal);
            canvas.Children.Add(vertical);
            canvas.Children.Add(ring);
            canvas.Children.Add(dot);
            canvas.Children.Add(label);
            SetCrosshairVisible(false);

            var root = new Grid();
            root.Children.Add(dim);
            root.Children.Add(hint);
            root.Children.Add(canvas);
            Content = root;

            SourceInitialized += (s, e) => SnapToMonitor();
            Loaded += (s, e) =>
            {
                SnapToMonitor();
                Native.GetCursorPos(out var cursor);
                if (Bounds.Contains(cursor)) MoveCrosshair(Mouse.GetPosition(canvas));
            };
            DpiChanged += (s, e) => Dispatcher.BeginInvoke(new Action(SnapToMonitor));
            SizeChanged += (s, e) => fullArea.Rect = new Rect(0, 0, ActualWidth, ActualHeight);

            MouseMove += (s, e) => MoveCrosshair(e.GetPosition(canvas));
            MouseLeave += (s, e) => SetCrosshairVisible(false);
            MouseLeftButtonUp += (s, e) =>
            {
                Native.GetCursorPos(out var point);
                Picked?.Invoke(point);
            };
            MouseRightButtonUp += (s, e) => Picked?.Invoke(null);
            KeyDown += (s, e) =>
            {
                if (e.Key == Key.Escape) Picked?.Invoke(null);
            };
        }

        public Native.RECT Bounds { get; }

        public event Action<Native.POINT?> Picked;

        /// <summary>Ставит окно ровно на монитор в физических пикселях, независимо от масштаба.</summary>
        private void SnapToMonitor()
        {
            var hwnd = new WindowInteropHelper(this).Handle;
            if (hwnd == IntPtr.Zero) return;
            Native.SetWindowPos(hwnd, Native.HWND_TOPMOST, Bounds.Left, Bounds.Top, Bounds.Width, Bounds.Height,
                Native.SWP_NOACTIVATE);
        }

        private void MoveCrosshair(Point p)
        {
            SetCrosshairVisible(true);
            hole.Center = p;

            horizontal.X1 = 0;
            horizontal.X2 = ActualWidth;
            horizontal.Y1 = horizontal.Y2 = p.Y;
            vertical.Y1 = 0;
            vertical.Y2 = ActualHeight;
            vertical.X1 = vertical.X2 = p.X;

            Canvas.SetLeft(ring, p.X - RingRadius);
            Canvas.SetTop(ring, p.Y - RingRadius);
            Canvas.SetLeft(dot, p.X - 2);
            Canvas.SetTop(dot, p.Y - 2);

            Native.GetCursorPos(out var screen);
            labelText.Text = "X " + screen.X + "   Y " + screen.Y;
            label.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
            var size = label.DesiredSize;
            double x = p.X + 22, y = p.Y + 22;
            if (x + size.Width > ActualWidth - 8) x = p.X - 22 - size.Width;
            if (y + size.Height > ActualHeight - 8) y = p.Y - 22 - size.Height;
            Canvas.SetLeft(label, x);
            Canvas.SetTop(label, y);
        }

        private void SetCrosshairVisible(bool visible)
        {
            var v = visible ? Visibility.Visible : Visibility.Hidden;
            horizontal.Visibility = vertical.Visibility = ring.Visibility = dot.Visibility = label.Visibility = v;
            if (!visible) hole.Center = new Point(-100, -100);
        }

        private static Line MakeLine() => new Line
        {
            Stroke = new SolidColorBrush(Color.FromArgb(0x5A, 0xFF, 0xFF, 0xFF)),
            StrokeThickness = 1,
            SnapsToDevicePixels = true,
        };
    }
}
