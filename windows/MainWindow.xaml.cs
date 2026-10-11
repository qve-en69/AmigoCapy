using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Threading;

namespace AmigoCapy
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
        private readonly DispatcherTimer countdownTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
        private readonly DispatcherTimer rejoinTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
        private readonly DispatcherTimer foregroundTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(300) };
        private readonly List<Button> chips = new List<Button>();
        private readonly StopGuard guard = new StopGuard();

        /// <summary>Клавиша таймера голда — цифра 7.</summary>
        private static readonly HotKey GoldKey = new HotKey(0x37, 0, "7");

        private HotKeyService hotKeys;
        private HotKeyService goldKeys;
        private bool goldConflict;
        private bool rejoinAfterPick;
        private bool loading = true;
        private bool running;
        private bool picking;
        private bool recording;
        private bool editingInterval;
        private bool appActive = true;
        private bool hotKeyConflict;
        private bool pulsing;
        private int? countdown;
        private int? rejoinCountdown;
        private int rejoinRun;
        private CountdownWindow rejoinBanner;
        private IntPtr lastExternalWindow;

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
            TeamRed.IsChecked = settings.Team == 0;
            TeamBlue.IsChecked = settings.Team == 1;
            TeamBoth.IsChecked = settings.Team == 2;
            Topmost = settings.AlwaysOnTop;
            // Окно стало шире по умолчанию (крупнее пушки в подборе) — старую узкую ширину не восстанавливаем.
            if (settings.WindowWidth >= 440) Width = settings.WindowWidth;
            if (settings.WindowHeight >= MinHeight) Height = settings.WindowHeight;
            // На маленьких экранах (ноутбук 1366×768) окно не должно вылезать за край.
            double maxHeight = SystemParameters.WorkArea.Height - 16;
            MinHeight = Math.Min(MinHeight, maxHeight);
            Height = Math.Min(Height, maxHeight);
            PaintsPanel.SelectionKeys = settings.PaintWeapons;
            PaintsPanel.SelectionChanged += () =>
            {
                settings.PaintWeapons = PaintsPanel.SelectionKeys;
                settings.Save();
            };
            var owned = new HashSet<string>(settings.OwnedPaints.Split(new[] { ',' }, StringSplitOptions.RemoveEmptyEntries));
            PaintsPanel.Owned = owned;
            PaintsPanel.OnlyMine = settings.OnlyMine;
            PaintsPanel.OnlyMineChanged += () =>
            {
                settings.OnlyMine = PaintsPanel.OnlyMine;
                settings.Save();
            };
            MinePanel.Owned = owned;
            MinePanel.OwnedChanged += () =>
            {
                settings.OwnedPaints = string.Join(",", owned);
                settings.Save();
                PaintsPanel.RefreshResults();
            };
            TabClicker.IsChecked = settings.Tab == 0;
            TabPaints.IsChecked = settings.Tab == 1;
            TabMine.IsChecked = settings.Tab == 2;
            ShowTab(settings.Tab);

            countdownTimer.Tick += CountdownTick;
            rejoinTimer.Tick += RejoinTick;
            foregroundTimer.Tick += (s, e) => TrackForegroundWindow();
            foregroundTimer.Start();
            SourceInitialized += OnSourceInitialized;
            Activated += (s, e) => { appActive = true; UpdateHotKeyRegistration(); };
            Deactivated += (s, e) => { appActive = false; UpdateHotKeyRegistration(); };
            // Кликер работает, только пока окно открыто: при сворачивании останавливаемся
            // и отпускаем клавишу, чтобы она снова печаталась в других программах.
            StateChanged += (s, e) =>
            {
                if (WindowState == WindowState.Minimized)
                {
                    CloseRejoinDialog();
                    StopClicking();
                }
                else UpdateHotKeyRegistration();
            };
            GoldTimerWindow.TimerChanged += RefreshGold;
            // Аварийный стоп: Esc или клавиша старта, даже если клавишу перехватила другая программа.
            guard.Triggered += reason =>
            {
                if (running || countdown.HasValue || rejoinCountdown.HasValue) StopClicking(reason);
            };
            PreviewKeyDown += Window_PreviewKeyDown;
            Closed += (s, e) =>
            {
                if (WindowState == WindowState.Normal)
                {
                    settings.WindowWidth = (int)Width;
                    settings.WindowHeight = (int)Height;
                }
                engine.Stop();
                hotKeys?.Unregister();
                guard.Dispose();
                goldKeys?.Unregister();
                GoldTimerWindow.CloseCurrent();
                settings.Save();
            };

            loading = false;
            RefreshAll();
        }

        private void OnSourceInitialized(object sender, EventArgs e)
        {
            var hwnd = new WindowInteropHelper(this).Handle;
            Theme.ApplyWindowAttributes(hwnd);
            hotKeys = new HotKeyService(hwnd, 0xA11C);
            hotKeys.Pressed += Toggle;
            goldKeys = new HotKeyService(hwnd, 0xA11D);
            goldKeys.Pressed += () => GoldTimerWindow.Toggle(settings.SoundOn);
            UpdateHotKeyRegistration();
        }

        // ───────────── Старт / стоп ─────────────

        /// <summary>Горячая клавиша: мгновенный старт или стоп.</summary>
        private void Toggle()
        {
            if (picking || recording) return;
            CloseRejoinDialog();
            if (running || countdown.HasValue || rejoinCountdown.HasValue) StopClicking();
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
            if (settings.PointMode && !PointsReady)
            {
                PickLocation(MissingPoint);
                return;
            }
            engine.Start(settings.IntervalMs, CurrentTargets);
            running = true;
            Signal(started: true);
            UpdateHotKeyRegistration();
            RefreshAll();
        }

        /// <param name="reason">Почему остановились (для плашки), если стоп пришёл не от кнопки или клавиши.</param>
        private void StopClicking(string reason = null)
        {
            countdownTimer.Stop();
            countdown = null;
            CancelRejoin();
            if (running)
            {
                engine.Stop();
                running = false;
                Signal(started: false, reason);
            }
            UpdateHotKeyRegistration();
            RefreshAll();
        }

        /// <summary>Звук и плашка на экране, чтобы было понятно, что кликер включился или выключился.</summary>
        private void Signal(bool started, string reason = null)
        {
            if (settings.SoundOn) Sounds.Play(started);
            if (settings.ToastOn)
                ToastWindow.Show(started, started ? settings.HotKey.Display + " или Esc — стоп" : reason);
        }

        private void SoundToggle_Click(object sender, RoutedEventArgs e)
        {
            settings.SoundOn = !settings.SoundOn;
            settings.Save();
            if (settings.SoundOn) Sounds.Play(true);
            RefreshHotKey();
        }

        private void ToastToggle_Click(object sender, RoutedEventArgs e)
        {
            settings.ToastOn = !settings.ToastOn;
            settings.Save();
            if (settings.ToastOn) ToastWindow.Show(true, "так выглядит подсказка");
            RefreshHotKey();
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

        /// <summary>Пустой список — кликать под курсором; иначе в выбранную точку (и во вторую, если включена).</summary>
        private List<Native.POINT> CurrentTargets
        {
            get
            {
                var targets = new List<Native.POINT>();
                if (!settings.PointMode) return targets;
                if (settings.Team != 1 && settings.HasPoint)
                    targets.Add(new Native.POINT { X = settings.PointX, Y = settings.PointY });
                if (settings.Team != 0 && settings.HasPoint2)
                    targets.Add(new Native.POINT { X = settings.Point2X, Y = settings.Point2Y });
                return targets;
            }
        }

        /// <summary>Выбраны ли точки, нужные для текущего «заходить за».</summary>
        private bool PointsReady =>
            (settings.Team == 1 || settings.HasPoint) && (settings.Team == 0 || settings.HasPoint2);

        /// <summary>Какую точку не хватает: 1 — красные, 2 — синие.</summary>
        private int MissingPoint => settings.Team != 1 && !settings.HasPoint ? 1 : 2;

        private void RestartIfRunning()
        {
            if (running) engine.Start(settings.IntervalMs, CurrentTargets);
        }

        // ───────────── Перезаход ─────────────

        /// <summary>Запоминаем последнее чужое активное окно (обычно игру), чтобы отправить Esc и Enter именно туда.</summary>
        private void TrackForegroundWindow()
        {
            var foreground = Native.GetForegroundWindow();
            if (foreground == IntPtr.Zero) return;
            Native.GetWindowThreadProcessId(foreground, out var pid);
            if (pid != (uint)System.Diagnostics.Process.GetCurrentProcess().Id) lastExternalWindow = foreground;
        }

        private void Rejoin_Click(object sender, RoutedEventArgs e)
        {
            Root.Focus();
            if (rejoinCountdown.HasValue)
            {
                StopClicking();
                return;
            }
            StopClicking();
            OpenRejoinDialog();
        }

        /// <summary>
        /// Окошко перед перезаходом: напоминает, что надо быть в битве, и спрашивает,
        /// за кого заходить. Без точек предлагает сначала их выбрать.
        /// </summary>
        private void OpenRejoinDialog()
        {
            bool red = settings.HasPoint, blue = settings.HasPoint2;
            RejoinNoPoints.Visibility = red || blue ? Visibility.Collapsed : Visibility.Visible;
            RejoinChoose.Visibility = red || blue ? Visibility.Visible : Visibility.Collapsed;

            RejoinRedButton.Visibility = red ? Visibility.Visible : Visibility.Collapsed;
            RejoinBlueButton.Visibility = blue ? Visibility.Visible : Visibility.Collapsed;
            RejoinRedColumn.Width = red ? new GridLength(1, GridUnitType.Star) : new GridLength(0);
            RejoinBlueColumn.Width = blue ? new GridLength(1, GridUnitType.Star) : new GridLength(0);
            RejoinRedButton.Margin = new Thickness(0, 0, blue ? 5 : 0, 0);
            RejoinBlueButton.Margin = new Thickness(red ? 5 : 0, 0, 0, 0);

            if (red && blue)
            {
                RejoinQuestion.Text = "За кого перезайти?";
                RejoinFootnote.Text = "Дальше отсчёт 3-2-1 — переключись в игру. Кликер сам выключится через 2 секунды.";
            }
            else
            {
                RejoinQuestion.Text = red ? "Перезайти за красных?" : "Перезайти за синих?";
                RejoinFootnote.Text = (red
                    ? "Точка за синих не выбрана"
                    : "Точка за красных не выбрана") + " — её можно поставить в «Куда кликать». "
                    + "Дальше отсчёт 3-2-1 — переключись в игру. Кликер сам выключится через 2 секунды.";
            }

            RejoinOverlay.Visibility = Visibility.Visible;
            Root.Focus();
        }

        private void CloseRejoinDialog() => RejoinOverlay.Visibility = Visibility.Collapsed;

        private void RejoinCancel_Click(object sender, RoutedEventArgs e) => CloseRejoinDialog();

        /// <summary>Клик по затемнению вокруг окошка — отмена.</summary>
        private void RejoinOverlay_MouseDown(object sender, MouseButtonEventArgs e)
        {
            if (e.OriginalSource == RejoinOverlay) CloseRejoinDialog();
            e.Handled = true;
        }

        private void RejoinRed_Click(object sender, RoutedEventArgs e) => BeginRejoin(0);

        private void RejoinBlue_Click(object sender, RoutedEventArgs e) => BeginRejoin(1);

        private void RejoinPickRed_Click(object sender, RoutedEventArgs e) => PickForRejoin(1);

        private void RejoinPickBlue_Click(object sender, RoutedEventArgs e) => PickForRejoin(2);

        /// <summary>Выбрать точку прямо из окошка, а затем вернуться к нему.</summary>
        private void PickForRejoin(int which)
        {
            CloseRejoinDialog();
            rejoinAfterPick = true;
            PickLocation(which);
        }

        /// <param name="team">0 — за красных, 1 — за синих. Выбор запоминается в «Заходить за».</param>
        private void BeginRejoin(int team)
        {
            CloseRejoinDialog();
            settings.Team = team;
            settings.Save();
            loading = true;
            TeamRed.IsChecked = team == 0;
            TeamBlue.IsChecked = team == 1;
            TeamBoth.IsChecked = false;
            loading = false;
            if (!PointsReady) return;

            StopClicking();
            rejoinCountdown = 3;
            rejoinBanner = CountdownWindow.Open(team == 0 ? "Перезаход за красных через" : "Перезаход за синих через", 3,
                team == 0 ? "RedGradient" : "BlueGradient");
            if (settings.SoundOn) Sounds.Tick();
            rejoinTimer.Start();
            UpdateHotKeyRegistration();
            RefreshAll();
        }

        private void RejoinTick(object sender, EventArgs e)
        {
            rejoinCountdown--;
            if (rejoinCountdown > 0)
            {
                rejoinBanner?.SetNumber(rejoinCountdown.Value);
                if (settings.SoundOn) Sounds.Tick();
                RefreshAll();
                return;
            }
            rejoinTimer.Stop();
            rejoinCountdown = null;
            rejoinBanner?.CloseBanner();
            rejoinBanner = null;
            DoRejoin();
        }

        private void CancelRejoin()
        {
            rejoinRun++;
            rejoinTimer.Stop();
            rejoinCountdown = null;
            rejoinBanner?.CloseBanner();
            rejoinBanner = null;
        }

        /// <summary>Сколько кликать в «Играть» после перезахода, потом кликер выключается сам.</summary>
        private const int RejoinClickMs = 2000;

        /// <summary>
        /// Клик в выбранную точку (чтобы окно игры стало активным) → Esc → Enter →
        /// клики в «Играть» 2 секунды — и стоп.
        /// </summary>
        private async void DoRejoin()
        {
            int run = ++rejoinRun;
            if (!settings.PointMode)
            {
                settings.PointMode = true;
                settings.Save();
                loading = true;
                ModeCursor.IsChecked = false;
                ModePoint.IsChecked = true;
                loading = false;
            }

            var me = new WindowInteropHelper(this).Handle;
            if (Native.GetForegroundWindow() == me && lastExternalWindow != IntPtr.Zero)
            {
                Native.SetForegroundWindow(lastExternalWindow);
                await Task.Delay(150);
                if (run != rejoinRun) return;
            }

            // Один клик в точку выбранной команды — так окно игры точно становится активным.
            var targets = CurrentTargets;
            if (targets.Count > 0)
            {
                Native.SetCursorPos(targets[0].X, targets[0].Y);
                Native.LeftClick();
                await Task.Delay(250);
                if (run != rejoinRun) return;
            }

            Native.PressKey(Native.VK_ESCAPE);
            await Task.Delay(150);
            if (run != rejoinRun) return;
            Native.PressKey(Native.VK_RETURN);
            await Task.Delay(120);
            if (run != rejoinRun) return;

            StartClicking();

            // Ручной стоп или новый перезаход меняют rejoinRun — тогда чужой запуск не трогаем.
            await Task.Delay(RejoinClickMs);
            if (run == rejoinRun && running) StopClicking("перезаход выполнен");
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
            if (point && !PointsReady)
            {
                PickLocation(MissingPoint);
                return;
            }
            RestartIfRunning();
            RefreshAll();
        }

        private void PickRed_Click(object sender, RoutedEventArgs e) => PickLocation(1);

        private void PickBlue_Click(object sender, RoutedEventArgs e) => PickLocation(2);

        private void Team_Checked(object sender, RoutedEventArgs e)
        {
            if (loading) return;
            settings.Team = TeamBlue.IsChecked == true ? 1 : TeamBoth.IsChecked == true ? 2 : 0;
            settings.Save();
            if (!PointsReady)
            {
                PickLocation(MissingPoint);
                return;
            }
            RestartIfRunning();
            RefreshAll();
        }

        private void ShowPoints_Click(object sender, RoutedEventArgs e)
        {
            Root.Focus();
            var markers = new List<(Native.POINT point, string label, Color color)>();
            if (settings.HasPoint)
                markers.Add((new Native.POINT { X = settings.PointX, Y = settings.PointY }, "Красные", RedColor));
            if (settings.HasPoint2)
                markers.Add((new Native.POINT { X = settings.Point2X, Y = settings.Point2Y }, "Синие", Color.FromRgb(0x3B, 0x82, 0xF6)));
            PointMarkers.Show(markers);
        }

        /// <param name="which">1 — «Играть» за красных, 2 — за синих.</param>
        private void PickLocation(int which)
        {
            if (picking) return;
            StopClicking();
            picking = true;
            RefreshAll();
            Hide();

            var session = new PickerSession(which == 1
                ? "Кликни на кнопку «Играть» за КРАСНЫХ"
                : "Кликни на кнопку «Играть» за СИНИХ");
            session.Completed += point =>
            {
                picking = false;
                if (point.HasValue && which == 2)
                {
                    settings.HasPoint2 = true;
                    settings.Point2X = point.Value.X;
                    settings.Point2Y = point.Value.Y;
                    settings.PointMode = true;
                }
                else if (point.HasValue)
                {
                    settings.HasPoint = true;
                    settings.PointX = point.Value.X;
                    settings.PointY = point.Value.Y;
                    settings.PointMode = true;
                }
                else if (!settings.HasPoint && !settings.HasPoint2)
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
                if (rejoinAfterPick)
                {
                    rejoinAfterPick = false;
                    if (point.HasValue) OpenRejoinDialog();
                }
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
            if (!recording)
            {
                if (e.Key == Key.Escape && RejoinOverlay.Visibility == Visibility.Visible)
                {
                    CloseRejoinDialog();
                    e.Handled = true;
                }
                if (e.Key == Key.Escape && HelpOverlay.Visibility == Visibility.Visible)
                {
                    HelpOverlay.Visibility = Visibility.Collapsed;
                    e.Handled = true;
                }
                return;
            }
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
            bool busy = running || countdown.HasValue || rejoinCountdown.HasValue;
            guard.StopVk = settings.HotKey.Modifiers == 0 ? settings.HotKey.Vk : 0;
            guard.Update(busy);
            bool minimized = WindowState == WindowState.Minimized;
            bool suspended = recording || minimized || (!busy && editingInterval && appActive);
            if (suspended)
            {
                hotKeys.Unregister();
                hotKeyConflict = false;
            }
            else
            {
                hotKeyConflict = !hotKeys.Register(settings.HotKey);
            }

            // Клавиша 7 для таймера голда — по тем же правилам, но без «занятости» кликера.
            bool goldSuspended = !settings.GoldTimerOn || recording || minimized || (editingInterval && appActive);
            if (goldSuspended)
            {
                goldKeys.Unregister();
                goldConflict = false;
            }
            else
            {
                goldConflict = !goldKeys.Register(GoldKey);
            }
            RefreshHotKey();
            RefreshGold();
        }

        // ───────────── Таймер голда ─────────────

        private void GoldStart_Click(object sender, RoutedEventArgs e)
        {
            Root.Focus();
            GoldTimerWindow.Toggle(settings.SoundOn);
        }

        private void GoldToggle_Click(object sender, RoutedEventArgs e)
        {
            Root.Focus();
            settings.GoldTimerOn = !settings.GoldTimerOn;
            settings.Save();
            if (!settings.GoldTimerOn) GoldTimerWindow.CloseCurrent();
            UpdateHotKeyRegistration();
        }

        private void RefreshGold()
        {
            bool on = settings.GoldTimerOn;
            GoldToggle.Content = on ? "Вкл" : "Выкл";
            GoldToggle.Tag = on ? "sel" : null;
            GoldKeycap.Opacity = on ? 1 : 0.45;
            GoldStartButton.Content = GoldTimerWindow.IsRunning ? "Сбросить" : "Запустить";

            if (on && goldConflict)
            {
                GoldSub.Text = settings.HotKey.Vk == GoldKey.Vk && settings.HotKey.Modifiers == 0
                    ? "Клавиша 7 уже стоит на кликере — смени её там"
                    : "Клавиша 7 занята другой программой";
                GoldSub.Foreground = new SolidColorBrush(RedColor);
            }
            else
            {
                GoldSub.Text = on
                    ? "Жми 7 — сверху пойдёт отсчёт, ещё раз 7 — сброс"
                    : "Выключен — клавиша 7 работает как обычно";
                GoldSub.Foreground = (Brush)FindResource("SubText");
            }
        }

        // ───────────── Вкладки ─────────────

        private void Tab_Checked(object sender, RoutedEventArgs e)
        {
            if (loading) return;
            int tab = TabMine.IsChecked == true ? 2 : TabPaints.IsChecked == true ? 1 : 0;
            settings.Tab = tab;
            settings.Save();
            ShowTab(tab);
        }

        /// <summary>0 — кликер, 1 — подбор краски, 2 — мои краски.</summary>
        private void ShowTab(int tab)
        {
            Root.Focus();
            ClickerPanel.Visibility = tab == 0 ? Visibility.Visible : Visibility.Collapsed;
            PaintsPanel.Visibility = tab == 1 ? Visibility.Visible : Visibility.Collapsed;
            MinePanel.Visibility = tab == 2 ? Visibility.Visible : Visibility.Collapsed;
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

        private void Help_Click(object sender, RoutedEventArgs e)
        {
            CloseRejoinDialog();
            HelpOverlay.Visibility = Visibility.Visible;
            Root.Focus();
        }

        private void HelpClose_Click(object sender, RoutedEventArgs e) => HelpOverlay.Visibility = Visibility.Collapsed;

        /// <summary>Клик по затемнению вокруг справки — закрыть.</summary>
        private void HelpOverlay_MouseDown(object sender, MouseButtonEventArgs e)
        {
            if (e.OriginalSource == HelpOverlay) HelpOverlay.Visibility = Visibility.Collapsed;
            e.Handled = true;
        }

        private void Close_Click(object sender, RoutedEventArgs e) => Close();

        // ───────────── Отрисовка состояния ─────────────

        private void RefreshAll()
        {
            RefreshHeader();
            RefreshInterval();
            RefreshTarget();
            RefreshHotKey();
            RefreshStart();
        }

        private void RefreshHeader()
        {
            string text;
            Color color;
            bool pulse;
            if (picking) { text = "Выбор точки"; color = BlueColor; pulse = false; }
            else if (rejoinCountdown.HasValue) { text = "Перезаход через " + rejoinCountdown.Value; color = OrangeColor; pulse = true; }
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
            bool point = settings.PointMode;
            CursorHint.Visibility = point ? Visibility.Collapsed : Visibility.Visible;
            PointPanel.Visibility = point ? Visibility.Visible : Visibility.Collapsed;

            ShowPointText(RedText, settings.HasPoint, settings.PointX, settings.PointY);
            ShowPointText(BlueText, settings.HasPoint2, settings.Point2X, settings.Point2Y);
            PickRedText.Text = settings.HasPoint ? "Заново" : "Выбрать";
            PickBlueText.Text = settings.HasPoint2 ? "Заново" : "Выбрать";

            // Точку, за которую сейчас не заходим, приглушаем.
            RedInfo.Opacity = settings.Team == 1 ? 0.45 : 1;
            BlueInfo.Opacity = settings.Team == 0 ? 0.45 : 1;
            ShowPointsButton.IsEnabled = settings.HasPoint || settings.HasPoint2;
        }

        private void ShowPointText(TextBlock text, bool has, int x, int y)
        {
            if (has)
            {
                text.Text = "X " + x + "   Y " + y;
                text.FontFamily = new FontFamily("Consolas");
                text.FontSize = 13;
                text.FontWeight = FontWeights.SemiBold;
                text.Foreground = (Brush)FindResource("Text");
            }
            else
            {
                text.Text = "не выбрана";
                text.FontFamily = (FontFamily)FindResource("UiFont");
                text.FontSize = 12;
                text.FontWeight = FontWeights.Normal;
                text.Foreground = (Brush)FindResource("SubText");
            }
        }

        private void RefreshHotKey()
        {
            KeycapText.Text = recording ? "…" : settings.HotKey.Display;
            SoundToggle.Tag = settings.SoundOn ? "sel" : null;
            ToastToggle.Tag = settings.ToastOn ? "sel" : null;
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
                HotKeySub.Text = recording ? "Esc — отмена" : "Работает, пока окно не свёрнуто";
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

            // Без точек кнопка всё равно открывает окошко — там предложим их выбрать.
            RejoinButton.IsEnabled = !picking;
            RejoinHint.Text = !settings.HasPoint && !settings.HasPoint2
                ? "Сначала выбери точку «Играть» · только в битве и в окне"
                : "Только в битве и в оконном режиме игры";
            RejoinText.Text = rejoinCountdown.HasValue ? "Отменить перезаход · " + rejoinCountdown.Value : "Перезаход";
            RejoinSub.Visibility = rejoinCountdown.HasValue ? Visibility.Collapsed : Visibility.Visible;

            if (editingInterval && !running) HintText.Text = "Enter — применить, затем жми " + key;
            else if (running || countdown.HasValue) HintText.Text = key + " или Esc — стоп";
            else HintText.Text = key + " — старт, пока окно открыто";
        }
    }
}
