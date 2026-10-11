using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace AmigoCapy
{
    /// <summary>Картинки из Assets, загруженные один раз.</summary>
    internal static class Images
    {
        private static readonly Dictionary<string, BitmapImage> Cache = new Dictionary<string, BitmapImage>();

        public static BitmapImage Load(string folder, string name)
        {
            string key = folder + "/" + name;
            if (Cache.TryGetValue(key, out var cached)) return cached;
            var image = new BitmapImage();
            image.BeginInit();
            image.UriSource = new Uri("pack://application:,,,/Assets/" + key + ".png");
            image.CacheOption = BitmapCacheOption.OnLoad;
            image.EndInit();
            image.Freeze();
            Cache[key] = image;
            return image;
        }
    }

    /// <summary>
    /// Вкладка «Мои краски»: отмечаешь краски, которые уже куплены,
    /// чтобы в подборе можно было показывать только их.
    /// </summary>
    public sealed class MyPaintsPanel : UserControl
    {
        private readonly Dictionary<Paint, (Button tile, Border check)> tiles = new Dictionary<Paint, (Button, Border)>();
        private readonly TextBlock counter;
        private readonly Button clearButton;
        private HashSet<string> owned = new HashSet<string>();

        public event Action OwnedChanged;

        public MyPaintsPanel()
        {
            counter = new TextBlock
            {
                FontSize = 11,
                FontWeight = FontWeights.SemiBold,
                VerticalAlignment = VerticalAlignment.Center,
                Foreground = (Brush)FindResource("SubText"),
            };

            clearButton = new Button
            {
                Content = "Снять все",
                Style = (Style)FindResource("SoftButton"),
                Height = 26,
                Padding = new Thickness(11, 0, 11, 0),
                Margin = new Thickness(0, 0, 6, 0),
            };
            clearButton.Click += (s, e) => SetAll(false);

            var allButton = new Button
            {
                Content = "Отметить все",
                Style = (Style)FindResource("SoftButton"),
                Height = 26,
                Padding = new Thickness(11, 0, 11, 0),
            };
            allButton.Click += (s, e) => SetAll(true);

            var header = new DockPanel { Margin = new Thickness(0, -2, 0, 6) };
            var title = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
            title.Children.Add(new TextBlock { Text = "", Style = (Style)FindResource("CardIcon") });
            title.Children.Add(new TextBlock { Text = "МОИ КРАСКИ", Style = (Style)FindResource("CardTitle") });
            var buttons = new StackPanel { Orientation = Orientation.Horizontal };
            buttons.Children.Add(clearButton);
            buttons.Children.Add(allButton);
            DockPanel.SetDock(buttons, Dock.Right);
            header.Children.Add(buttons);
            header.Children.Add(title);

            var hint = new TextBlock
            {
                Text = "Отметь краски, которые у тебя есть. В «Подборе» включи «Только мои» — и он покажет лучшее из твоих.",
                FontSize = 11,
                TextWrapping = TextWrapping.Wrap,
                Foreground = (Brush)FindResource("SubText"),
            };

            var headerStack = new StackPanel();
            headerStack.Children.Add(header);
            headerStack.Children.Add(hint);
            var headerCard = new Border
            {
                Style = (Style)FindResource("Card"),
                Margin = new Thickness(0, 12, 0, 0),
                Child = headerStack,
            };

            var countRow = new DockPanel { Margin = new Thickness(4, 14, 8, 8) };
            countRow.Children.Add(counter);

            var grid = new UniformGrid { Columns = 3, Margin = new Thickness(-3, 0, 5, 0) };
            foreach (var paint in PaintCatalog.Paints.OrderBy(p => p.Name, StringComparer.CurrentCulture))
                grid.Children.Add(MakeTile(paint));

            var scroll = new ScrollViewer
            {
                VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
                HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled,
                Focusable = false,
                Content = grid,
            };
            scroll.Resources.Add(typeof(ScrollBar), new Style(typeof(ScrollBar), (Style)FindResource("SlimScrollBar")));

            var root = new DockPanel();
            DockPanel.SetDock(headerCard, Dock.Top);
            DockPanel.SetDock(countRow, Dock.Top);
            root.Children.Add(headerCard);
            root.Children.Add(countRow);
            root.Children.Add(scroll);
            Content = root;

            Refresh();
        }

        /// <summary>Набор ключей купленных красок (общий с вкладкой подбора).</summary>
        public HashSet<string> Owned
        {
            get => owned;
            set
            {
                owned = value ?? new HashSet<string>();
                Refresh();
            }
        }

        private UIElement MakeTile(Paint paint)
        {
            var thumbnail = new Border
            {
                Height = 46,
                CornerRadius = new CornerRadius(8),
                Background = new ImageBrush(Images.Load("paints", paint.Image)) { Stretch = Stretch.UniformToFill },
                Margin = new Thickness(6, 6, 6, 0),
            };
            var name = new TextBlock
            {
                Text = paint.Name,
                FontSize = 12,
                FontWeight = FontWeights.SemiBold,
                HorizontalAlignment = HorizontalAlignment.Center,
                Margin = new Thickness(0, 5, 0, 5),
            };
            var stack = new StackPanel();
            stack.Children.Add(thumbnail);
            stack.Children.Add(name);

            var check = new Border
            {
                Width = 20,
                Height = 20,
                CornerRadius = new CornerRadius(10),
                Background = (Brush)FindResource("StartGradient"),
                HorizontalAlignment = HorizontalAlignment.Right,
                VerticalAlignment = VerticalAlignment.Top,
                Margin = new Thickness(0, 1, 1, 0),
                Child = new TextBlock
                {
                    Text = "",
                    FontFamily = (FontFamily)FindResource("IconFont"),
                    FontSize = 10,
                    Foreground = Brushes.White,
                    HorizontalAlignment = HorizontalAlignment.Center,
                    VerticalAlignment = VerticalAlignment.Center,
                },
            };

            var content = new Grid();
            content.Children.Add(stack);
            content.Children.Add(check);

            var tile = new Button
            {
                Content = content,
                Style = (Style)FindResource("WeaponButton"),
                Margin = new Thickness(3),
                ToolTip = paint.Name + "\n" + string.Join("\n", paint.Protection.Select(p => p.Key.Name + ": " + p.Value + "%")),
            };
            System.Windows.Automation.AutomationProperties.SetName(tile, paint.Name);
            tile.Click += (s, e) => Toggle(paint);

            tiles[paint] = (tile, check);
            return tile;
        }

        private void Toggle(Paint paint)
        {
            if (!owned.Remove(paint.Image)) owned.Add(paint.Image);
            Refresh();
            OwnedChanged?.Invoke();
        }

        private void SetAll(bool value)
        {
            owned.Clear();
            if (value)
                foreach (var paint in PaintCatalog.Paints) owned.Add(paint.Image);
            Refresh();
            OwnedChanged?.Invoke();
        }

        private void Refresh()
        {
            int count = 0;
            foreach (var pair in tiles)
            {
                bool mine = owned.Contains(pair.Key.Image);
                if (mine) count++;
                pair.Value.tile.Tag = mine ? "sel" : null;
                pair.Value.check.Visibility = mine ? Visibility.Visible : Visibility.Collapsed;
            }
            counter.Text = "ОТМЕЧЕНО " + count + " ИЗ " + tiles.Count;
            clearButton.Visibility = count > 0 ? Visibility.Visible : Visibility.Collapsed;
        }
    }
}
