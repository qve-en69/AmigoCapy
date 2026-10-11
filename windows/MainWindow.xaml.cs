using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Threading;

namespace AmigoClick
{
    public partial class MainWindow : Window
    {
        private static readonly int[] Presets = { 10, 50, 100, 250, 500, 1000 };
        private const int MaxInterval = 600000;

        private static readonly Color AccentColor = Color.FromRgb(0x14, 0xA9, 0x8F);
        private static readonly Color BlueColor = Color.FromRgb(0x26, 0x85, 0xF2);
        private static readonly Color OrangeColor = Color.FromRgb(0xF0, 0x8A, 0x24);
        private static readonly Color GrayColor = Color.FromRgb(0x8A, 0x93, 0x9E);
        private static readonly Color RedColor = Color.FromRgb(0xE5, 0x48, 0x4D);

        private readonly Settings settings = Settings.Load();
        private readonly ClickEngine engine = new ClickEngine();
        private readonly DispatcherTimer counterTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(100) };
        private readonly DispatcherTimer countdownTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
        private readonly List<Button> chips = new List<Button>();

        private HotKeyService hotKeys;
        private bool loading = true;
        private bool running;
        private bool picking;
        private bool recording;
        private bool editingInterval;
        private bool appActive = true;
        private bool hotKeyConflict;
        private bool pulsing;
        private int? countdown;

        public MainWindow()
        {
            InitializeComponent();

            foreach (var value in Presets)
            {
                var chip = new Button
                {
                    Content = value >= 1000 ? (value / 1000) + " с" : value.ToString(),
                    Style = (Style)FindResource("Chip"),
                    Margin = new Thickness(3, 0, 3, 0),
                };
                chip.Click += (s, e) =>
                {
                    SetInterval(value, updateText: true);
                    Root.Focus();
                };
                chips.Add(chip);
                PresetsPanel.Children.Add(chip);
            }

            IntervalBox.Text = settings.IntervalMs.ToString();
            ModeCursor.IsChecked = !settings.PointMode;
            ModePoint.IsChecked = settings.PointMode;
            Topmost = settings.AlwaysOnTop;

            counterTimer.Tick += (s, e) => UpdateClicks();
            countdownTimer.Tick += CountdownTick;
            SourceInitialized += OnSourceInitialized;
            Activated += (s, e) => { appActive = true; UpdateHotKeyRegistration(); };
            Deactivated += (s, e) => { appActive = false; UpdateHotKeyRegistration(); };
            PreviewKeyDown += Window_PreviewKeyDown;
            Closed += (s, e) =>
            {
                engine.Stop();
                hotKeys?.Unregister();
                settings.Save();
            };

            loading = false;
            RefreshAll();
        }

        private void OnSourceInitialized(object sender, EventArgs e)
        {
            var hwnd = new WindowInteropHelper(this).Handle;
            Theme.ApplyWindowAttributes(hwnd);
            hotKeys = new HotKeyService(hwnd);
            hotKeys.Pressed += Toggle;
            UpdateHotKeyRegistration();
        }

        // ───────────── Старт / стоп ─────────────

        /// <summary>Горячая клавиша: мгновенный старт или стоп.</summary>
        private void Toggle()
        {
            if (picking || recording) return;
            if (running || countdown.HasValue) StopClicking();
            else StartClicking();
        }

        /// <summary>
        /// Кнопка в окне. В режиме «под курсором» даёт 3 секунды увести мышь с кнопки,
        /// иначе первый же клик попал бы в «Стоп».
        /// </summary>
        private void Start_Click(object sender, RoutedEventArgs e)
        {
            Root.Focus();
            if (running || countdown.HasValue) StopClicking();
            else if (!settings.PointMode) BeginCountdown();
            else StartClicking();
        }

        private void StartClicking()
        {
            if (running) return;
            if (settings.PointMode && !settings.HasPoint)
            {
                PickLocation();
                return;
            }
            engine.ResetCount();
            engine.Start(settings.IntervalMs, CurrentTarget);
            running = true;
            counterTimer.Start();
            UpdateHotKeyRegistration();
            RefreshAll();
        }

        private void StopClicking()
        {
            countdownTimer.Stop();
            countdown = null;
            if (running)
            {
                engine.Stop();
                counterTimer.Stop();
                running = false;
            }
            UpdateClicks();
            UpdateHotKeyRegistration();
            RefreshAll();
        }

        private void BeginCountdown()
        {
            countdown = 3;
            countdownTimer.Start();
            UpdateHotKeyRegistration();
            RefreshAll();
        }

        private void CountdownTick(object sender, EventArgs e)
        {
            countdown--;
            if (countdown > 0)
            {
                RefreshAll();
                return;
            }
            countdownTimer.Stop();
            countdown = null;
            StartClicking();
        }

        private Native.POINT? CurrentTarget =>
            settings.PointMode && settings.HasPoint
                ? new Native.POINT { X = settings.PointX, Y = settings.PointY }
                : (Native.POINT?)null;

        private void RestartIfRunning()
        {
            if (running) engine.Start(settings.IntervalMs, CurrentTarget);
        }

        private void UpdateClicks()
        {
            ClicksText.Text = "Кликов: " + engine.Count.ToString("N0", CultureInfo.GetCultureInfo("ru-RU"));
        }

        // ───────────── Интервал ─────────────

        private void SetInterval(int value, bool updateText)
        {
            settings.IntervalMs = Math.Max(1, Math.Min(MaxInterval, value));
            settings.Save();
            RestartIfRunning();
            if (updateText) IntervalBox.Text = settings.IntervalMs.ToString();
            RefreshInterval();
        }

        private void IntervalBox_PreviewTextInput(object sender, TextCompositionEventArgs e)
        {
            e.Handled = !e.Text.All(char.IsDigit);
        }

        private void IntervalBox_TextChanged(object sender, TextChangedEventArgs e)
        {
            if (loading) return;
            var digits = new string(IntervalBox.Text.Where(c => c >= '0' && c <= '9').ToArray());
            if (digits != IntervalBox.Text)
            {
                IntervalBox.Text = digits;
                IntervalBox.CaretIndex = digits.Length;
                return;
            }
            if (int.TryParse(digits, out var value) && value > 0) SetInterval(value, updateText: false);
        }

        private void IntervalBox_KeyDown(object sender, KeyEventArgs e)
        {
            if (e.Key == Key.Enter || e.Key == Key.Escape)
            {
                Root.Focus();
                e.Handled = true;
            }
        }

        private void IntervalBox_GotKeyboardFocus(object sender, KeyboardFocusChangedEventArgs e)
        {
            editingInterval = true;
            UpdateHotKeyRegistration();
            RefreshStart();
        }

        private void IntervalBox_LostKeyboardFocus(object sender, KeyboardFocusChangedEventArgs e)
        {
            editingInterval = false;
            IntervalBox.Text = settings.IntervalMs.ToString();
            UpdateHotKeyRegistration();
            RefreshStart();
        }

        private void Root_MouseDown(object sender, MouseButtonEventArgs e)
        {
            if (!IntervalBox.IsMouseOver) Root.Focus();
        }

        // ───────────── Куда кликать ─────────────

        private void Mode_Checked(object sender, RoutedEventArgs e)
        {
            if (loading) return;
            bool point = ModePoint.IsChecked == true;
            if (point == settings.PointMode) return;
            settings.PointMode = point;
            settings.Save();
            if (point && !settings.HasPoint)
            {
                PickLocation();
                return;
            }
            RestartIfRunning();
            RefreshAll();
        }

        private void Pick_Click(object sender, RoutedEventArgs e) => PickLocation();

        private void PickLocation()
        {
            if (picking) return;
            StopClicking();
            picking = true;
            RefreshAll();
            Hide();

            var session = new PickerSession();
            session.Completed += point =>
            {
                picking = false;
                if (point.HasValue)
                {
                    settings.HasPoint = true;
                    settings.PointX = point.Value.X;
                    settings.PointY = point.Value.Y;
                    settings.PointMode = true;
                }
                else if (!settings.HasPoint)
                {
                    settings.PointMode = false;
                }
                settings.Save();

                loading = true;
                ModeCursor.IsChecked = !settings.PointMode;
                ModePoint.IsChecked = settings.PointMode;
                loading = false;

                Show();
                Activate();
                RefreshAll();
            };
            session.Start();
        }

        // ───────────── Горячая клавиша ─────────────

        private void HotKey_Click(object sender, RoutedEventArgs e)
        {
            if (recording)
            {
                StopRecording();
                return;
            }
            StopClicking();
            recording = true;
            Root.Focus();
            UpdateHotKeyRegistration();
            RefreshAll();
        }

        private void StopRecording()
        {
            recording = false;
            UpdateHotKeyRegistration();
            RefreshAll();
        }

        private void Window_PreviewKeyDown(object sender, KeyEventArgs e)
        {
            if (!recording) return;
            e.Handled = true;

            var key = e.Key == Key.System ? e.SystemKey : e.Key;
            if (key == Key.Escape)
            {
                StopRecording();
                return;
            }
            if (HotKey.IsModifier(key)) return; // ждём основную клавишу

            int vk = KeyInterop.VirtualKeyFromKey(key);
            var name = HotKey.NameFor(key, vk);
            if (name == null || vk == 0) return;

            settings.HotKey = new HotKey((uint)vk, HotKey.ModifiersFrom(Keyboard.Modifiers), name);
            settings.Save();
            StopRecording();
        }

        /// <summary>
        /// Пока в поле интервала печатают, клавиша (например, «6») нужна для ввода цифр — отпускаем её.
        /// Во время кликов клавиша работает всегда, чтобы кликер точно можно было остановить.
        /// </summary>
        private void UpdateHotKeyRegistration()
        {
            if (hotKeys == null) return;
            bool busy = running || countdown.HasValue;
            bool suspended = recording || (!busy && editingInterval && appActive);
            if (suspended)
            {
                hotKeys.Unregister();
                hotKeyConflict = false;
            }
            else
            {
                hotKeyConflict = !hotKeys.Register(settings.HotKey);
            }
            RefreshHotKey();
        }

        // ───────────── Шапка ─────────────

        private void Header_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
        {
            if (e.ButtonState == MouseButtonState.Pressed) DragMove();
        }

        private void Pin_Click(object sender, RoutedEventArgs e)
        {
            settings.AlwaysOnTop = !settings.AlwaysOnTop;
            Topmost = settings.AlwaysOnTop;
            settings.Save();
            RefreshHeader();
        }

        private void Minimize_Click(object sender, RoutedEventArgs e) => WindowState = WindowState.Minimized;

        private void Close_Click(object sender, RoutedEventArgs e) => Close();

        // ───────────── Отрисовка состояния ─────────────

        private void RefreshAll()
        {
            RefreshHeader();
            RefreshInterval();
            RefreshTarget();
            RefreshHotKey();
            RefreshStart();
            UpdateClicks();
        }

        private void RefreshHeader()
        {
            string text;
            Color color;
            bool pulse;
            if (picking) { text = "Выбор точки"; color = BlueColor; pulse = false; }
            else if (countdown.HasValue) { text = "Старт через " + countdown.Value; color = OrangeColor; pulse = true; }
            else if (running) { text = "Кликает"; color = AccentColor; pulse = true; }
            else { text = "Готов"; color = GrayColor; pulse = false; }

            StatusText.Text = text;
            StatusText.Foreground = new SolidColorBrush(color);
            StatusDot.Fill = new SolidColorBrush(color);
            StatusRing.Stroke = new SolidColorBrush(color);
            StatusPill.Background = new SolidColorBrush(Color.FromArgb(0x26, color.R, color.G, color.B));
            SetPulse(pulse);

            PinGlyph.Text = settings.AlwaysOnTop ? "" : "";
            PinButton.Foreground = settings.AlwaysOnTop
                ? (Brush)FindResource("Accent")
                : (Brush)FindResource("SubText");
            PinButton.ToolTip = settings.AlwaysOnTop ? "Окно закреплено поверх остальных" : "Закрепить окно поверх остальных";
        }

        private void SetPulse(bool on)
        {
            if (on == pulsing) return;
            pulsing = on;
            if (on)
            {
                var duration = new Duration(TimeSpan.FromSeconds(1.2));
                var grow = new DoubleAnimation(1, 2.6, duration) { RepeatBehavior = RepeatBehavior.Forever };
                var fade = new DoubleAnimation(1, 0, duration) { RepeatBehavior = RepeatBehavior.Forever };
                StatusRingScale.BeginAnimation(ScaleTransform.ScaleXProperty, grow);
                StatusRingScale.BeginAnimation(ScaleTransform.ScaleYProperty, grow);
                StatusRing.BeginAnimation(OpacityProperty, fade);
            }
            else
            {
                StatusRingScale.BeginAnimation(ScaleTransform.ScaleXProperty, null);
                StatusRingScale.BeginAnimation(ScaleTransform.ScaleYProperty, null);
                StatusRing.BeginAnimation(OpacityProperty, null);
                StatusRing.Opacity = 0;
            }
        }

        private void RefreshInterval()
        {
            int ms = settings.IntervalMs;
            var ru = CultureInfo.GetCultureInfo("ru-RU");
            if (ms <= 1000)
            {
                double perSecond = 1000.0 / ms;
                RateText.Text = perSecond >= 10
                    ? "≈ " + Math.Round(perSecond) + " в секунду"
                    : "≈ " + perSecond.ToString("0.0", ru) + " в секунду";
            }
            else
            {
                RateText.Text = "раз в " + (ms / 1000.0).ToString("0.0", ru) + " с";
            }

            for (int i = 0; i < chips.Count; i++)
                chips[i].Tag = Presets[i] == ms ? "sel" : null;
        }

        private void RefreshTarget()
        {
            if (settings.PointMode && settings.HasPoint)
            {
                TargetIcon.Visibility = Visibility.Visible;
                TargetText.Text = "X " + settings.PointX + "   Y " + settings.PointY;
                TargetText.FontWeight = FontWeights.SemiBold;
                TargetText.FontFamily = new FontFamily("Consolas");
                TargetText.FontSize = 13;
                TargetText.Foreground = (Brush)FindResource("Text");
            }
            else
            {
                TargetIcon.Visibility = Visibility.Collapsed;
                TargetText.Text = settings.PointMode ? "Точка ещё не выбрана" : "Кликает туда, где сейчас курсор";
                TargetText.FontWeight = FontWeights.Normal;
                TargetText.FontFamily = (FontFamily)FindResource("UiFont");
                TargetText.FontSize = 12;
                TargetText.Foreground = (Brush)FindResource("SubText");
            }
            PickText.Text = settings.HasPoint ? "Выбрать заново" : "Выбрать точку";
        }

        private void RefreshHotKey()
        {
            KeycapText.Text = recording ? "…" : settings.HotKey.Display;
            Keycap.BorderBrush = recording ? (Brush)FindResource("Accent") : (Brush)FindResource("KeycapEdge");
            HotKeyButton.Content = recording ? "Отмена" : "Изменить";
            HotKeyTitle.Text = recording ? "Нажми нужную клавишу" : "Старт и стоп";

            if (hotKeyConflict && !recording)
            {
                HotKeySub.Text = "Клавиша занята другой программой — выбери другую";
                HotKeySub.Foreground = new SolidColorBrush(RedColor);
            }
            else
            {
                HotKeySub.Text = recording ? "Esc — отмена" : "Работает в любом окне";
                HotKeySub.Foreground = (Brush)FindResource("SubText");
            }
            RefreshStart();
        }

        private void RefreshStart()
        {
            string key = settings.HotKey.Display;
            StartKey.Text = key;

            string gradient;
            Color shadow;
            if (countdown.HasValue)
            {
                StartGlyph.Text = "";
                StartText.Text = "Отменить старт · " + countdown.Value;
                gradient = "WaitGradient";
                shadow = Color.FromRgb(0xFA, 0x80, 0x4D);
            }
            else if (running)
            {
                StartGlyph.Text = "";
                StartText.Text = "Стоп";
                gradient = "StopGradient";
                shadow = Color.FromRgb(0xEB, 0x42, 0x80);
            }
            else
            {
                StartGlyph.Text = "";
                StartText.Text = "Старт";
                gradient = "StartGradient";
                shadow = BlueColor;
            }
            StartButton.Background = (Brush)FindResource(gradient);
            StartShadow.Color = shadow;
            StartButton.IsEnabled = !picking;

            if (editingInterval && !running) HintText.Text = "Enter — применить, затем жми " + key;
            else if (running || countdown.HasValue) HintText.Text = key + " — остановить";
            else HintText.Text = key + " — старт из любого окна";
        }
    }
}
