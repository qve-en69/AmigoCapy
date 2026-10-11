using System;
using System.Collections.Generic;
using System.Linq;

namespace AmigoCapy
{
    internal sealed class Weapon
    {
        public Weapon(string key, string name)
        {
            Key = key;
            Name = name;
        }

        /// <summary>Имя файла иконки в Assets/weapons.</summary>
        public string Key { get; }
        public string Name { get; }
    }

    internal sealed class Paint
    {
        public Paint(string name, string image, params (Weapon weapon, int percent)[] protection)
        {
            Name = name;
            Image = image;
            Protection = protection.ToDictionary(p => p.weapon, p => p.percent);
        }

        public string Name { get; }

        /// <summary>Имя файла текстуры в Assets/paints.</summary>
        public string Image { get; }

        /// <summary>Защита в процентах; порядок как в игре.</summary>
        public IReadOnlyDictionary<Weapon, int> Protection { get; }

        public int Against(Weapon weapon) => Protection.TryGetValue(weapon, out var p) ? p : 0;
    }

    internal sealed class PaintMatch
    {
        public PaintMatch(Paint paint, int score, int covered, double average)
        {
            Paint = paint;
            Score = score;
            Covered = covered;
            Average = average;
        }

        public Paint Paint { get; }
        public int Score { get; }

        /// <summary>От скольких видов вражеских пушек защищает.</summary>
        public int Covered { get; }

        /// <summary>Средняя защита от вражеской команды с учётом количества пушек, %.</summary>
        public double Average { get; }
    }

    internal static class PaintCatalog
    {
        public static readonly Weapon Vulcan = new Weapon("vulcan", "Вулкан");
        public static readonly Weapon Thunder = new Weapon("thunder", "Гром");
        public static readonly Weapon Isida = new Weapon("isida", "Изида");
        public static readonly Weapon Hammer = new Weapon("hammer", "Молот");
        public static readonly Weapon Firebird = new Weapon("firebird", "Огнемёт");
        public static readonly Weapon Railgun = new Weapon("railgun", "Рельса");
        public static readonly Weapon Ricochet = new Weapon("ricochet", "Рикошет");
        public static readonly Weapon Smoky = new Weapon("smoky", "Смоки");
        public static readonly Weapon Twins = new Weapon("twins", "Твинс");
        public static readonly Weapon Freeze = new Weapon("freeze", "Фриз");
        public static readonly Weapon Shaft = new Weapon("shaft", "Шафт");

        /// <summary>Все пушки по алфавиту.</summary>
        public static readonly IReadOnlyList<Weapon> Weapons = new[]
        {
            Vulcan, Thunder, Isida, Hammer, Firebird, Railgun, Ricochet, Smoky, Twins, Freeze, Shaft,
        };

        /// <summary>Краски из игры. Чтобы добавить новую — допиши строку и положи текстуру в Assets/paints.</summary>
        public static readonly IReadOnlyList<Paint> Paints = new[]
        {
            new Paint("Атом", "atom", (Hammer, 33), (Firebird, 18), (Freeze, 11), (Twins, 11)),
            new Paint("Африка", "africa", (Hammer, 20), (Vulcan, 30), (Twins, 25), (Thunder, 25)),
            new Paint("Вишня", "cherry", (Vulcan, 22), (Twins, 34), (Thunder, 28)),
            new Paint("Граффити", "graffiti", (Vulcan, 50), (Twins, 25), (Shaft, 25)),
            new Paint("Диджитал", "digital", (Smoky, 24), (Railgun, 35), (Shaft, 14)),
            new Paint("Дровосек", "lumberjack", (Vulcan, 10), (Isida, 30), (Firebird, 30), (Freeze, 30)),
            new Paint("Енот", "raccoon", (Hammer, 33), (Vulcan, 27), (Isida, 19), (Railgun, 21)),
            new Paint("Зевс", "zeus", (Firebird, 50), (Freeze, 25), (Smoky, 25)),
            new Paint("Изумруд", "emerald", (Twins, 35), (Thunder, 50), (Railgun, 15)),
            new Paint("Инферно", "inferno", (Firebird, 36), (Freeze, 50), (Twins, 14)),
            new Paint("Ирбис", "irbis", (Isida, 50), (Freeze, 27), (Ricochet, 23)),
            new Paint("Искра", "spark", (Firebird, 30), (Twins, 18), (Ricochet, 42)),
            new Paint("Кузнец", "blacksmith", (Vulcan, 40), (Railgun, 18), (Shaft, 26)),
            new Paint("Марс", "mars", (Hammer, 50), (Firebird, 30), (Isida, 20)),
            new Paint("Метель", "blizzard", (Firebird, 12), (Thunder, 26), (Railgun, 12), (Shaft, 45)),
            new Paint("Мираж", "mirage", (Firebird, 35), (Smoky, 22), (Thunder, 20), (Vulcan, 23)),
            new Paint("Нано", "nano", (Hammer, 35), (Ricochet, 32), (Smoky, 22), (Firebird, 11)),
            new Paint("Носорог", "rhino", (Hammer, 30), (Vulcan, 30), (Firebird, 18)),
            new Paint("Нефрит", "jade", (Thunder, 11), (Smoky, 24), (Shaft, 50), (Hammer, 15)),
            new Paint("Песчаник", "sandstone", (Twins, 12), (Thunder, 22), (Railgun, 34), (Shaft, 22)),
            new Paint("Пикассо", "picasso", (Freeze, 20), (Thunder, 20), (Railgun, 27), (Shaft, 33)),
            new Paint("Питон", "python", (Freeze, 44), (Shaft, 40)),
            new Paint("Продиджи", "prodigy", (Firebird, 7), (Thunder, 23), (Railgun, 50), (Shaft, 20)),
            new Paint("Сакура", "sakura", (Hammer, 25), (Vulcan, 12), (Isida, 25)),
            new Paint("Скала", "rock", (Isida, 28), (Freeze, 12), (Twins, 50), (Hammer, 10)),
            new Paint("Тайга", "taiga", (Isida, 35), (Firebird, 24), (Twins, 17), (Ricochet, 24)),
            new Paint("Тигр", "tiger", (Hammer, 47), (Smoky, 35), (Railgun, 18)),
            new Paint("Тина", "tina", (Ricochet, 50), (Thunder, 20), (Railgun, 30)),
            new Paint("Улей", "hive", (Vulcan, 42), (Freeze, 26), (Ricochet, 32)),
            new Paint("Хвоя", "needles", (Ricochet, 22), (Smoky, 50), (Shaft, 28)),
            new Paint("Хохлома", "khokhloma", (Freeze, 22), (Ricochet, 30), (Smoky, 22)),
            new Paint("Шелест", "rustle", (Isida, 15), (Freeze, 30), (Thunder, 40)),
            new Paint("Электра", "electra", (Isida, 38), (Twins, 20), (Smoky, 20)),
        };

        /// <summary>
        /// Краски, которые защищают хотя бы от одной пушки врага.
        /// Вес пушки — сколько таких у врагов: «Шафт ×3» считается втрое сильнее одной Рельсы.
        /// </summary>
        public static List<PaintMatch> Rank(IReadOnlyList<(Weapon weapon, int count)> enemies)
        {
            int total = enemies.Sum(e => e.count);
            return Paints
                .Select(paint =>
                {
                    int score = 0, covered = 0;
                    foreach (var (weapon, count) in enemies)
                    {
                        int p = paint.Against(weapon);
                        score += p * count;
                        if (p > 0) covered++;
                    }
                    return new PaintMatch(paint, score, covered, total > 0 ? (double)score / total : 0);
                })
                .Where(m => m.Covered > 0)
                .OrderByDescending(m => m.Score)
                .ThenByDescending(m => m.Covered)
                .ThenBy(m => m.Paint.Name, StringComparer.CurrentCulture)
                .ToList();
        }
    }
}
