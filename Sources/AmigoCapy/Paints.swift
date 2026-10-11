import AppKit
import Foundation

struct Weapon: Hashable, Identifiable {
    /// Имя файла картинки в Resources/turrets.
    let key: String
    let name: String
    var id: String { key }
}

struct Paint: Identifiable {
    let name: String
    /// Имя файла текстуры в Resources/paints.
    let image: String
    /// Защита в процентах; порядок как в игре.
    let protection: [(weapon: Weapon, percent: Int)]

    var id: String { image }

    init(_ name: String, _ image: String, _ protection: (Weapon, Int)...) {
        self.name = name
        self.image = image
        self.protection = protection.map { (weapon: $0.0, percent: $0.1) }
    }

    func against(_ weapon: Weapon) -> Int {
        protection.first(where: { $0.weapon == weapon })?.percent ?? 0
    }
}

/// Пушка врага и сколько таких в команде.
struct Enemy: Identifiable {
    let weapon: Weapon
    let count: Int
    var id: String { weapon.key }
}

struct PaintMatch: Identifiable {
    let paint: Paint
    let score: Int
    /// От скольких видов вражеских пушек защищает.
    let covered: Int
    /// Средняя защита от вражеской команды с учётом количества пушек, %.
    let average: Double
    var id: String { paint.image }
}

enum PaintCatalog {
    static let vulcan = Weapon(key: "vulcan", name: "Вулкан")
    static let thunder = Weapon(key: "thunder", name: "Гром")
    static let isida = Weapon(key: "isida", name: "Изида")
    static let hammer = Weapon(key: "hammer", name: "Молот")
    static let firebird = Weapon(key: "firebird", name: "Огнемёт")
    static let railgun = Weapon(key: "railgun", name: "Рельса")
    static let ricochet = Weapon(key: "ricochet", name: "Рикошет")
    static let smoky = Weapon(key: "smoky", name: "Смоки")
    static let twins = Weapon(key: "twins", name: "Твинс")
    static let freeze = Weapon(key: "freeze", name: "Фриз")
    static let shaft = Weapon(key: "shaft", name: "Шафт")

    /// Все пушки по алфавиту.
    static let weapons = [vulcan, thunder, isida, hammer, firebird, railgun, ricochet, smoky, twins, freeze, shaft]

    /// Краски из игры (те же, что в Windows-версии).
    static let paints: [Paint] = [
        Paint("Атом", "atom", (hammer, 33), (firebird, 18), (freeze, 11), (twins, 11)),
        Paint("Африка", "africa", (hammer, 20), (vulcan, 30), (twins, 25), (thunder, 25)),
        Paint("Вишня", "cherry", (vulcan, 22), (twins, 34), (thunder, 28)),
        Paint("Граффити", "graffiti", (vulcan, 50), (twins, 25), (shaft, 25)),
        Paint("Диджитал", "digital", (smoky, 24), (railgun, 35), (shaft, 14)),
        Paint("Дровосек", "lumberjack", (vulcan, 10), (isida, 30), (firebird, 30), (freeze, 30)),
        Paint("Енот", "raccoon", (hammer, 33), (vulcan, 27), (isida, 19), (railgun, 21)),
        Paint("Зевс", "zeus", (firebird, 50), (freeze, 25), (smoky, 25)),
        Paint("Изумруд", "emerald", (twins, 35), (thunder, 50), (railgun, 15)),
        Paint("Инферно", "inferno", (firebird, 36), (freeze, 50), (twins, 14)),
        Paint("Ирбис", "irbis", (isida, 50), (freeze, 27), (ricochet, 23)),
        Paint("Искра", "spark", (firebird, 30), (twins, 18), (ricochet, 42)),
        Paint("Кузнец", "blacksmith", (vulcan, 40), (railgun, 18), (shaft, 26)),
        Paint("Марс", "mars", (hammer, 50), (firebird, 30), (isida, 20)),
        Paint("Метель", "blizzard", (firebird, 12), (thunder, 26), (railgun, 12), (shaft, 45)),
        Paint("Мираж", "mirage", (firebird, 35), (smoky, 22), (thunder, 20), (vulcan, 23)),
        Paint("Нано", "nano", (hammer, 35), (ricochet, 32), (smoky, 22), (firebird, 11)),
        Paint("Носорог", "rhino", (hammer, 30), (vulcan, 30), (firebird, 18)),
        Paint("Нефрит", "jade", (thunder, 11), (smoky, 24), (shaft, 50), (hammer, 15)),
        Paint("Песчаник", "sandstone", (twins, 12), (thunder, 22), (railgun, 34), (shaft, 22)),
        Paint("Пикассо", "picasso", (freeze, 20), (thunder, 20), (railgun, 27), (shaft, 33)),
        Paint("Питон", "python", (freeze, 44), (shaft, 40)),
        Paint("Продиджи", "prodigy", (firebird, 7), (thunder, 23), (railgun, 50), (shaft, 20)),
        Paint("Сакура", "sakura", (hammer, 25), (vulcan, 12), (isida, 25)),
        Paint("Скала", "rock", (isida, 28), (freeze, 12), (twins, 50), (hammer, 10)),
        Paint("Тайга", "taiga", (isida, 35), (firebird, 24), (twins, 17), (ricochet, 24)),
        Paint("Тигр", "tiger", (hammer, 47), (smoky, 35), (railgun, 18)),
        Paint("Тина", "tina", (ricochet, 50), (thunder, 20), (railgun, 30)),
        Paint("Улей", "hive", (vulcan, 42), (freeze, 26), (ricochet, 32)),
        Paint("Хвоя", "needles", (ricochet, 22), (smoky, 50), (shaft, 28)),
        Paint("Хохлома", "khokhloma", (freeze, 22), (ricochet, 30), (smoky, 22)),
        Paint("Шелест", "rustle", (isida, 15), (freeze, 30), (thunder, 40)),
        Paint("Электра", "electra", (isida, 38), (twins, 20), (smoky, 20)),
    ]

    /// Краски, которые защищают хотя бы от одной пушки врага.
    /// Вес пушки — сколько таких у врагов: «Шафт ×3» считается втрое сильнее одной Рельсы.
    static func rank(_ enemies: [Enemy]) -> [PaintMatch] {
        let total = enemies.reduce(0) { $0 + $1.count }
        var matches: [PaintMatch] = []
        for paint in paints {
            var score = 0
            var covered = 0
            for enemy in enemies {
                let percent = paint.against(enemy.weapon)
                score += percent * enemy.count
                if percent > 0 { covered += 1 }
            }
            guard covered > 0 else { continue }
            let average = total > 0 ? Double(score) / Double(total) : 0
            matches.append(PaintMatch(paint: paint, score: score, covered: covered, average: average))
        }
        return matches.sorted { a, b in
            if a.score != b.score { return a.score > b.score }
            if a.covered != b.covered { return a.covered > b.covered }
            return a.paint.name.localizedCompare(b.paint.name) == .orderedAscending
        }
    }
}

/// Картинки пушек и красок из Contents/Resources (их кладёт туда scripts/build.sh).
@MainActor
enum AssetImages {
    private static var cache: [String: NSImage] = [:]

    static func load(_ folder: String, _ name: String) -> NSImage? {
        let key = folder + "/" + name
        if let cached = cache[key] { return cached }
        guard
            let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: folder),
            let image = NSImage(contentsOf: url)
        else { return nil }
        cache[key] = image
        return image
    }
}

/// Состав врагов, «Мои краски» и фильтр «Только мои». Запоминается между запусками.
@MainActor
final class PaintStore: ObservableObject {
    static let maxWeapons = 4
    static let maxCount = 9

    /// Пушки врагов в порядке, в котором их отметили.
    @Published private(set) var order: [Weapon] = []
    @Published private(set) var counts: [String: Int] = [:]
    @Published private(set) var owned: Set<String> = []
    @Published var onlyMine = false {
        didSet { defaults.set(onlyMine, forKey: Keys.onlyMine) }
    }

    private var defaults: UserDefaults { .standard }

    private enum Keys {
        static let weapons = "paintWeapons"
        static let owned = "ownedPaints"
        static let onlyMine = "onlyMine"
    }

    init() {
        let d = UserDefaults.standard
        _onlyMine = Published(initialValue: d.bool(forKey: Keys.onlyMine))
        let ownedList = (d.string(forKey: Keys.owned) ?? "").split(separator: ",").map(String.init)
        _owned = Published(initialValue: Set(ownedList))

        var order: [Weapon] = []
        var counts: [String: Int] = [:]
        for item in (d.string(forKey: Keys.weapons) ?? "").split(separator: ",") {
            let parts = item.split(separator: ":")
            guard
                let key = parts.first.map(String.init),
                let weapon = PaintCatalog.weapons.first(where: { $0.key == key }),
                counts[key] == nil,
                order.count < Self.maxWeapons
            else { continue }
            let count = parts.count > 1 ? (Int(parts[1]) ?? 1) : 1
            order.append(weapon)
            counts[key] = min(max(count, 1), Self.maxCount)
        }
        _order = Published(initialValue: order)
        _counts = Published(initialValue: counts)
    }

    func count(of weapon: Weapon) -> Int {
        counts[weapon.key] ?? 0
    }

    /// Можно ли ещё добавить эту пушку (отмечено меньше 4 видов или она уже отмечена).
    func canAdd(_ weapon: Weapon) -> Bool {
        count(of: weapon) > 0 || order.count < Self.maxWeapons
    }

    /// Враги для подсчёта: сначала самые многочисленные.
    var enemies: [Enemy] {
        var indexed: [(index: Int, enemy: Enemy)] = []
        for (index, weapon) in order.enumerated() {
            indexed.append((index: index, enemy: Enemy(weapon: weapon, count: counts[weapon.key] ?? 1)))
        }
        indexed.sort { a, b in
            a.enemy.count != b.enemy.count ? a.enemy.count > b.enemy.count : a.index < b.index
        }
        return indexed.map { $0.enemy }
    }

    func add(_ weapon: Weapon) {
        if let count = counts[weapon.key] {
            counts[weapon.key] = min(Self.maxCount, count + 1)
        } else if order.count < Self.maxWeapons {
            order.append(weapon)
            counts[weapon.key] = 1
        }
        saveSelection()
    }

    func remove(_ weapon: Weapon) {
        guard let count = counts[weapon.key] else { return }
        if count > 1 {
            counts[weapon.key] = count - 1
        } else {
            counts[weapon.key] = nil
            order.removeAll { $0 == weapon }
        }
        saveSelection()
    }

    func reset() {
        order = []
        counts = [:]
        saveSelection()
    }

    func toggleOwned(_ image: String) {
        if owned.contains(image) {
            owned.remove(image)
        } else {
            owned.insert(image)
        }
        saveOwned()
    }

    func setAllOwned(_ on: Bool) {
        owned = on ? Set(PaintCatalog.paints.map { $0.image }) : []
        saveOwned()
    }

    private func saveSelection() {
        let text = order.map { "\($0.key):\(counts[$0.key] ?? 1)" }.joined(separator: ",")
        defaults.set(text, forKey: Keys.weapons)
    }

    private func saveOwned() {
        defaults.set(owned.sorted().joined(separator: ","), forKey: Keys.owned)
    }
}
