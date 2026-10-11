using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace AmigoCapy
{
    /// <summary>
    /// Вкладка «Подбор краски»: отмечаешь состав вражеской команды (до 4 видов пушек, у каждой счётчик) —
    /// ниже краски, отсортированные по защите с учётом количества пушек.
    /// </summary>
    public partial class PaintPanel : UserControl
    {
        private const int MaxWeapons = 4;
        private const int MaxCount = 9;

        /// <summary>Пушки врагов в порядке, в котором их отметили.</summary>
        private readonly List<Weapon> order = new List<Weapon>();
        private readonly Dictionary<Weapon, int> counts = new Dictionary<Weapon, int>();
        private readonly Dictionary<Weapon, (Button button, Border badge, TextBlock badgeText)> weaponButtons =
            new Dictionary<Weapon, (Button, Border, TextBlock)>();

        public PaintPanel()
        {
            InitializeComponent();
            foreach (var weapon in PaintCatalog.Weapons) AddWeaponButton(weapon);
            Refresh();
        }

        /// <summary>Состав врагов вида «shaft:3,isida:2» — чтобы запомнить его между запусками.</summary>
        public string SelectionKeys
        {
            get => string.Join(",", order.Select(w => w.Key + ":" + counts[w]));
            set
            {
                order.Clear();
                counts.Clear();
                foreach (var item in (value ?? "").Split(new[] { ',' }, StringSplitOptions.RemoveEmptyEntries))
                {
                    var parts = item.Split(':');
                    var weapon = PaintCatalog.Weapons.FirstOrDefault(w => w.Key == parts[0]);
                    if (weapon == null || counts.ContainsKey(weapon) || order.Count >= MaxWeapons) continue;
                    int count = parts.Length > 1 && int.TryParse(parts[1], out var n) ? n : 1;
                    order.Add(weapon);
                    counts[weapon] = Math.Max(1, Math.Min(MaxCount, count));
                }
                Refresh();
            }
        }

        public event Action SelectionChanged;

        /// <summary>Ключи купленных красок (общий набор с вкладкой «Мои краски»).</summary>
        public HashSet<string> Owned { get; set; } = new HashSet<string>();

        /// <summary>Показывать только купленные краски.</summary>
        public bool OnlyMine
        {
            get => onlyMine;
            set
            {
                onlyMine = value;
                Refresh();
            }
        }

        public event Action OnlyMineChanged;

        private bool onlyMine;

        /// <summary>Перерисовать список, например после изменения «Моих красок».</summary>
        public void RefreshResults() => Refresh();

        /// <summary>Враги для подсчёта: сначала самые многочисленные.</summary>
        private List<(Weapon weapon, int count)> Enemies =>
            order.Select((w, i) => (weapon: w, count: counts[w], index: i))
                .OrderByDescending(e => e.count)
                .ThenBy(e => e.index)
                .Select(e => (e.weapon, e.count))
                .ToList();

        // ───────────── Пушки ─────────────

        private void AddWeaponButton(Weapon weapon)
        {
            // Картинка растягивается на ширину кнопки: чем шире окно, тем крупнее пушки.
            var icon = new Image
            {
                Source = Images.Load("turrets", weapon.Key),
                Stretch = Stretch.Uniform,
                MaxHeight = 40,
                Margin = new Thickness(3, 2, 3, 0),
            };
            RenderOptions.SetBitmapScalingMode(icon, BitmapScalingMode.HighQuality);

            var name = new TextBlock
            {
                Text = weapon.Name,
                FontSize = 11,
                FontWeight = FontWeights.SemiBold,
                HorizontalAlignment = HorizontalAlignment.Center,
                Margin = new Thickness(0, 2, 0, 1),
            };

            var content = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
            content.Children.Add(icon);
            content.Children.Add(name);

            var badgeText = new TextBlock
            {
                Foreground = Brushes.White,
                FontSize = 9.5,
                FontWeight = FontWeights.Bold,
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center,
            };
            var badge = new Border
            {
                MinWidth = 17,
                Height = 15,
                Padding = new Thickness(3, 0, 3, 0),
                CornerRadius = new CornerRadius(7.5),
                Margin = new Thickness(0, -3, 1, 0),
                Background = (Brush)FindResource("StartGradient"),
                HorizontalAlignment = HorizontalAlignment.Right,
                VerticalAlignment = VerticalAlignment.Top,
                Child = badgeText,
                Visibility = Visibility.Collapsed,
            };

            var grid = new Grid();
            grid.Children.Add(content);
            grid.Children.Add(badge);

            var button = new Button
            {
                Content = grid,
                Style = (Style)FindResource("WeaponButton"),
                Margin = new Thickness(2),
                ToolTip = weapon.Name + " — клик: +1, правый клик: −1",
            };
            System.Windows.Automation.AutomationProperties.SetName(button, weapon.Name);
            button.Click += (s, e) => Add(weapon);
            button.PreviewMouseRightButtonUp += (s, e) =>
            {
                Remove(weapon);
                e.Handled = true;
            };

            weaponButtons[weapon] = (button, badge, badgeText);
            WeaponsGrid.Children.Add(button);
        }

        private void Add(Weapon weapon)
        {
            if (counts.TryGetValue(weapon, out var count))
            {
                counts[weapon] = Math.Min(MaxCount, count + 1);
            }
            else if (order.Count < MaxWeapons)
            {
                order.Add(weapon);
                counts[weapon] = 1;
            }
            Changed();
        }

        private void Remove(Weapon weapon)
        {
            if (!counts.TryGetValue(weapon, out var count)) return;
            if (count > 1)
            {
                counts[weapon] = count - 1;
            }
            else
            {
                counts.Remove(weapon);
                order.Remove(weapon);
            }
            Changed();
        }

        private void OnlyMine_Click(object sender, RoutedEventArgs e)
        {
            onlyMine = !onlyMine;
            Refresh();
            OnlyMineChanged?.Invoke();
        }

        private void Reset_Click(object sender, RoutedEventArgs e)
        {
            order.Clear();
            counts.Clear();
            Changed();
        }

        private void Changed()
        {
            Refresh();
            SelectionChanged?.Invoke();
        }

        // ───────────── Отрисовка ─────────────

        private void Refresh()
        {
            foreach (var pair in weaponButtons)
            {
                bool chosen = counts.TryGetValue(pair.Key, out var count);
                var (button, badge, badgeText) = pair.Value;
                button.Tag = chosen ? "sel" : null;
                // Когда отмечено 4 вида, новые гасим; отмеченные остаются активными, чтобы их можно было уменьшить.
                button.IsEnabled = chosen || order.Count < MaxWeapons;
                badge.Visibility = chosen ? Visibility.Visible : Visibility.Collapsed;
                badgeText.Text = "×" + count;
            }

            var enemies = Enemies;
            OnlyMineToggle.Tag = onlyMine ? "sel" : null;
            ResetButton.Visibility = order.Count > 0 ? Visibility.Visible : Visibility.Hidden;
            SelectionHint.Text = order.Count == 0
                ? "Отметь пушки врагов: клик — +1, правый клик — −1 (до 4 видов)"
                : "Враги: " + string.Join(" · ", enemies.Select(e => e.weapon.Name + " ×" + e.count));

            ResultsList.Children.Clear();
            ResultsScroll.ScrollToTop();

            if (order.Count == 0)
            {
                ResultsTitle.Text = "ПОДХОДЯЩИЕ КРАСКИ";
                ResultsList.Children.Add(EmptyState("", "Отметь, какие пушки у врагов, —\nи здесь появятся лучшие краски против них"));
                return;
            }

            var matches = PaintCatalog.Rank(enemies);
            if (onlyMine) matches = matches.Where(m => Owned.Contains(m.Paint.Image)).ToList();
            ResultsTitle.Text = (onlyMine ? "МОИ ПОДХОДЯЩИЕ КРАСКИ · " : "ПОДХОДЯЩИЕ КРАСКИ · ") + matches.Count;
            if (matches.Count == 0)
            {
                ResultsList.Children.Add(onlyMine && Owned.Count == 0
                    ? EmptyState("\uE73E", "Ты ещё не отметил свои краски —\nсделай это во вкладке «Мои краски»")
                    : onlyMine
                        ? EmptyState("\uE783", "Среди твоих красок нет защиты\nот выбранных пушек")
                        : EmptyState("\uE783", "Пока нет красок с защитой\nот выбранных пушек"));
                return;
            }

            for (int i = 0; i < matches.Count; i++)
                ResultsList.Children.Add(ResultCard(matches[i], enemies, i == 0));
        }

        private UIElement ResultCard(PaintMatch match, List<(Weapon weapon, int count)> enemies, bool best)
        {
            var paint = match.Paint;

            var thumbnail = new Border
            {
                Width = 84,
                Height = 38,
                CornerRadius = new CornerRadius(8),
                Background = new ImageBrush(Images.Load("paints", paint.Image)) { Stretch = Stretch.UniformToFill },
                VerticalAlignment = VerticalAlignment.Center,
            };

            var title = new StackPanel { Orientation = Orientation.Horizontal };
            title.Children.Add(new TextBlock
            {
                Text = paint.Name,
                FontSize = 14,
                FontWeight = FontWeights.Bold,
                VerticalAlignment = VerticalAlignment.Center,
            });
            if (!onlyMine && Owned.Contains(paint.Image))
            {
                title.Children.Add(new Border
                {
                    Background = (Brush)FindResource("AccentSoft"),
                    CornerRadius = new CornerRadius(8),
                    Padding = new Thickness(6, 1, 7, 2),
                    Margin = new Thickness(8, 1, 0, 0),
                    VerticalAlignment = VerticalAlignment.Center,
                    ToolTip = "Эта краска у тебя есть",
                    Child = new TextBlock
                    {
                        Text = "✓ есть",
                        Foreground = (Brush)FindResource("Accent"),
                        FontSize = 10,
                        FontWeight = FontWeights.SemiBold,
                    },
                });
            }
            if (best)
            {
                title.Children.Add(new Border
                {
                    Background = (Brush)FindResource("StartGradient"),
                    CornerRadius = new CornerRadius(8),
                    Padding = new Thickness(7, 1, 7, 2),
                    Margin = new Thickness(8, 1, 0, 0),
                    VerticalAlignment = VerticalAlignment.Center,
                    Child = new TextBlock
                    {
                        Text = "лучший выбор",
                        Foreground = Brushes.White,
                        FontSize = 10,
                        FontWeight = FontWeights.SemiBold,
                    },
                });
            }

            string coverage = match.Covered == enemies.Count
                ? (enemies.Count == 1 ? "от этой пушки" : "от всех пушек врага")
                : "от " + match.Covered + " из " + enemies.Count + " пушек";
            var subtitle = new TextBlock
            {
                Text = "Средняя защита " + Math.Round(match.Average).ToString(CultureInfo.InvariantCulture) + "% · " + coverage,
                FontSize = 11,
                Margin = new Thickness(0, 2, 0, 0),
                Foreground = (Brush)FindResource("SubText"),
                ToolTip = "Средняя защита от вражеской команды с учётом количества каждой пушки",
            };

            var info = new StackPanel { Margin = new Thickness(12, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center };
            info.Children.Add(title);
            info.Children.Add(subtitle);

            var top = new DockPanel();
            top.Children.Add(thumbnail);
            top.Children.Add(info);

            // Пушки врага (включая 0%) — подписанными чипами, остальная защита краски — строкой ниже.
            var chips = new WrapPanel { Margin = new Thickness(0, 8, 0, -4) };
            foreach (var (weapon, count) in enemies)
                chips.Children.Add(Chip(weapon, count, paint.Against(weapon)));

            var body = new StackPanel();
            body.Children.Add(top);
            body.Children.Add(chips);

            var others = paint.Protection.Where(p => !counts.ContainsKey(p.Key)).ToList();
            if (others.Count > 0)
            {
                body.Children.Add(new TextBlock
                {
                    Text = "Ещё: " + string.Join("  ·  ", others.Select(p => p.Key.Name + " " + p.Value + "%")),
                    FontSize = 11,
                    Margin = new Thickness(1, 6, 0, 0),
                    TextTrimming = TextTrimming.CharacterEllipsis,
                    Foreground = (Brush)FindResource("SubText"),
                    ToolTip = string.Join("\n", others.Select(p => p.Key.Name + ": защита " + p.Value + "%")),
                });
            }

            var card = new Border
            {
                Style = (Style)FindResource("Card"),
                Padding = new Thickness(10),
                Margin = new Thickness(0, 0, 8, 8),
                Child = body,
            };
            if (best)
            {
                card.BorderBrush = (Brush)FindResource("Accent");
                card.BorderThickness = new Thickness(1.5);
            }
            return card;
        }

        private UIElement Chip(Weapon weapon, int count, int percent)
        {
            bool missing = percent == 0;
            var accent = missing ? new SolidColorBrush(Color.FromRgb(0xE5, 0x48, 0x4D)) : (Brush)FindResource("Accent");

            var row = new StackPanel { Orientation = Orientation.Horizontal };
            row.Children.Add(new TextBlock
            {
                Text = weapon.Name,
                FontSize = 11.5,
                FontWeight = FontWeights.Medium,
                VerticalAlignment = VerticalAlignment.Center,
            });
            row.Children.Add(new TextBlock
            {
                Text = percent + "%",
                FontSize = 11.5,
                FontWeight = FontWeights.Bold,
                Margin = new Thickness(5, 0, 0, 0),
                VerticalAlignment = VerticalAlignment.Center,
                Foreground = accent,
            });

            string who = count > 1 ? weapon.Name + " ×" + count : weapon.Name;
            return new Border
            {
                Background = missing
                    ? new SolidColorBrush(Color.FromArgb(0x22, 0xE5, 0x48, 0x4D))
                    : (Brush)FindResource("AccentSoft"),
                CornerRadius = new CornerRadius(8),
                Padding = new Thickness(7, 3, 7, 4),
                Margin = new Thickness(0, 0, 4, 4),
                ToolTip = missing ? who + ": защиты нет" : who + ": защита " + percent + "%",
                Child = row,
            };
        }

        private UIElement EmptyState(string glyph, string text)
        {
            var panel = new StackPanel
            {
                HorizontalAlignment = HorizontalAlignment.Center,
                Margin = new Thickness(0, 28, 0, 0),
            };
            panel.Children.Add(new TextBlock
            {
                Text = glyph,
                FontFamily = (FontFamily)FindResource("IconFont"),
                FontSize = 30,
                Foreground = (Brush)FindResource("Accent"),
                HorizontalAlignment = HorizontalAlignment.Center,
                Opacity = 0.8,
            });
            panel.Children.Add(new TextBlock
            {
                Text = text,
                FontSize = 12.5,
                TextAlignment = TextAlignment.Center,
                Margin = new Thickness(0, 12, 0, 0),
                Foreground = (Brush)FindResource("SubText"),
            });
            return panel;
        }
    }
}
