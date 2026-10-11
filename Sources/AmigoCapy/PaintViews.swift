import SwiftUI

/// Картинка из Resources (пушка или текстура краски); если файла нет — значок-заглушка.
struct AssetImageView: View {
    let folder: String
    let name: String
    var fill = false

    var body: some View {
        if let image = AssetImages.load(folder, name) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: fill ? .fill : .fit)
        } else {
            Image(systemName: "photo")
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Подбор краски

/// Вкладка «Подбор»: отмечаешь состав вражеской команды (до 4 видов пушек, у каждой счётчик) —
/// ниже краски, отсортированные по защите с учётом количества пушек.
struct PaintPickerView: View {
    @ObservedObject var store: PaintStore

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 6)

    var body: some View {
        VStack(spacing: 12) {
            Card("Пушки врагов", icon: "scope") {
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(PaintCatalog.weapons) { weapon in
                        WeaponTile(weapon: weapon,
                                   count: store.count(of: weapon),
                                   enabled: store.canAdd(weapon),
                                   add: { store.add(weapon) },
                                   remove: { store.remove(weapon) })
                    }
                }
                HStack(spacing: 8) {
                    Text(hint)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if !store.order.isEmpty {
                        Button("Сбросить") { store.reset() }
                            .buttonStyle(SoftButtonStyle())
                    }
                }
            }

            HStack {
                Text(resultsTitle)
                    .font(.system(size: 10.5, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                Spacer()
                ToggleChip(title: "Только мои", icon: "checkmark", on: store.onlyMine) {
                    store.onlyMine.toggle()
                }
                .help("Показывать только краски, отмеченные во вкладке «Мои краски»")
            }
            .padding(.horizontal, 4)

            ScrollView {
                LazyVStack(spacing: 8) {
                    results
                }
                .padding(.trailing, 4)
                .padding(.bottom, 4)
            }
        }
    }

    private var hint: String {
        if store.order.isEmpty { return "Отметь пушки врагов: клик — +1, «−» или правый клик — убрать (до 4 видов)" }
        return "Враги: " + store.enemies.map { "\($0.weapon.name) ×\($0.count)" }.joined(separator: " · ")
    }

    private var matches: [PaintMatch] {
        let all = PaintCatalog.rank(store.enemies)
        return store.onlyMine ? all.filter { store.owned.contains($0.paint.image) } : all
    }

    private var resultsTitle: String {
        if store.order.isEmpty { return "ПОДХОДЯЩИЕ КРАСКИ" }
        return (store.onlyMine ? "МОИ ПОДХОДЯЩИЕ КРАСКИ · " : "ПОДХОДЯЩИЕ КРАСКИ · ") + "\(matches.count)"
    }

    @ViewBuilder private var results: some View {
        if store.order.isEmpty {
            EmptyState(icon: "scope", text: "Отметь, какие пушки у врагов, —\nи здесь появятся лучшие краски против них")
        } else {
            let list = matches
            if list.isEmpty {
                if store.onlyMine && store.owned.isEmpty {
                    EmptyState(icon: "checkmark.circle", text: "Ты ещё не отметил свои краски —\nсделай это во вкладке «Мои краски»")
                } else if store.onlyMine {
                    EmptyState(icon: "shield.slash", text: "Среди твоих красок нет защиты\nот выбранных пушек")
                } else {
                    EmptyState(icon: "shield.slash", text: "Пока нет красок с защитой\nот выбранных пушек")
                }
            } else {
                let enemies = store.enemies
                let chosen = Set(store.order.map { $0.key })
                ForEach(Array(list.enumerated()), id: \.element.id) { index, match in
                    PaintResultCard(match: match,
                                    enemies: enemies,
                                    chosenKeys: chosen,
                                    best: index == 0,
                                    owned: store.owned.contains(match.paint.image),
                                    onlyMine: store.onlyMine)
                }
            }
        }
    }
}

private struct WeaponTile: View {
    let weapon: Weapon
    let count: Int
    let enabled: Bool
    let add: () -> Void
    let remove: () -> Void
    @State private var hovering = false

    var body: some View {
        let chosen = count > 0
        return VStack(spacing: 2) {
            AssetImageView(folder: "turrets", name: weapon.key)
                .frame(height: 30)
            Text(weapon.name)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(chosen ? Palette.accent.opacity(0.16) : Color.primary.opacity(hovering ? 0.09 : 0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(chosen ? Palette.accent : Color.clear, lineWidth: 1.5)
        )
        .overlay(alignment: .topTrailing) {
            if chosen {
                Text("×\(count)")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .frame(minWidth: 17, minHeight: 15)
                    .background(Capsule().fill(LinearGradient(colors: Palette.start,
                                                              startPoint: .leading, endPoint: .trailing)))
                    .offset(x: 3, y: -4)
            }
        }
        .overlay(alignment: .topLeading) {
            if chosen {
                Button(action: remove) {
                    Image(systemName: "minus")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: 15, height: 15)
                        .background(Circle().fill(Palette.redDot))
                }
                .buttonStyle(.plain)
                .offset(x: -3, y: -4)
                .help("Убрать одну")
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onTapGesture { if enabled { add() } }
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Добавить ещё одну", action: add).disabled(!enabled)
            Button("Убрать одну", action: remove).disabled(!chosen)
        }
        .opacity(enabled ? 1 : 0.4)
        .help("\(weapon.name) — клик: +1, «−» или правый клик: убрать")
    }
}

private struct PaintResultCard: View {
    let match: PaintMatch
    let enemies: [Enemy]
    let chosenKeys: Set<String>
    let best: Bool
    let owned: Bool
    let onlyMine: Bool

    private let chipColumns = [GridItem(.adaptive(minimum: 100), spacing: 4, alignment: .leading)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                AssetImageView(folder: "paints", name: match.paint.image, fill: true)
                    .frame(width: 84, height: 38)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    titleRow
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .help("Средняя защита от вражеской команды с учётом количества каждой пушки")
                }
                Spacer(minLength: 0)
            }
            LazyVGrid(columns: chipColumns, alignment: .leading, spacing: 4) {
                ForEach(enemies) { enemy in
                    ProtectionChip(enemy: enemy, percent: match.paint.against(enemy.weapon))
                }
            }
            if !others.isEmpty {
                Text("Ещё: " + others.map { "\($0.weapon.name) \($0.percent)%" }.joined(separator: "  ·  "))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(others.map { "\($0.weapon.name): защита \($0.percent)%" }.joined(separator: "\n"))
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(best ? Palette.accent : Color.primary.opacity(0.08), lineWidth: best ? 1.5 : 1)
        )
    }

    private var titleRow: some View {
        HStack(spacing: 8) {
            Text(match.paint.name)
                .font(.system(size: 14, weight: .bold))
            if owned && !onlyMine {
                Text("✓ есть")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Palette.accent.opacity(0.15)))
                    .help("Эта краска у тебя есть")
            }
            if best {
                Text("лучший выбор")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(LinearGradient(colors: Palette.start,
                                                              startPoint: .leading, endPoint: .trailing)))
            }
        }
    }

    private var subtitle: String {
        let coverage: String
        if match.covered == enemies.count {
            coverage = enemies.count == 1 ? "от этой пушки" : "от всех пушек врага"
        } else {
            coverage = "от \(match.covered) из \(enemies.count) пушек"
        }
        return "Средняя защита \(Int(match.average.rounded()))% · " + coverage
    }

    private var others: [(weapon: Weapon, percent: Int)] {
        match.paint.protection.filter { !chosenKeys.contains($0.weapon.key) }
    }
}

/// «Шафт 45%» — подписанный чип защиты от пушки врага; 0% — красным.
private struct ProtectionChip: View {
    let enemy: Enemy
    let percent: Int

    var body: some View {
        let missing = percent == 0
        let tint = missing ? Palette.redDot : Palette.accent
        let who = enemy.count > 1 ? "\(enemy.weapon.name) ×\(enemy.count)" : enemy.weapon.name
        return HStack(spacing: 5) {
            Text(enemy.weapon.name)
                .font(.system(size: 11.5, weight: .medium))
                .lineLimit(1)
            Text("\(percent)%")
                .font(.system(size: 11.5, weight: .bold))
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tint.opacity(missing ? 0.14 : 0.15))
        )
        .help(missing ? "\(who): защиты нет" : "\(who): защита \(percent)%")
    }
}

private struct EmptyState: View {
    let icon: String
    let text: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundStyle(Palette.accent.opacity(0.8))
            Text(text)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 28)
    }
}

// MARK: - Мои краски

/// Вкладка «Мои краски»: отмечаешь краски, которые у тебя есть.
struct MyPaintsView: View {
    @ObservedObject var store: PaintStore

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        VStack(spacing: 12) {
            Card("Мои краски", icon: "checkmark.circle") {
                Text("Отметь краски, которые у тебя есть, — в «Подборе» кнопка «Только мои» покажет лучшие из них.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Text("ОТМЕЧЕНО \(store.owned.count) ИЗ \(PaintCatalog.paints.count)")
                        .font(.system(size: 10.5, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Снять все") { store.setAllOwned(false) }
                        .buttonStyle(SoftButtonStyle())
                        .disabled(store.owned.isEmpty)
                    Button("Отметить все") { store.setAllOwned(true) }
                        .buttonStyle(SoftButtonStyle())
                }
            }
            ScrollView {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(PaintCatalog.paints) { paint in
                        OwnedTile(paint: paint, owned: store.owned.contains(paint.image)) {
                            store.toggleOwned(paint.image)
                        }
                    }
                }
                .padding(.trailing, 4)
                .padding(.bottom, 4)
            }
        }
    }
}

private struct OwnedTile: View {
    let paint: Paint
    let owned: Bool
    let toggle: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AssetImageView(folder: "paints", name: paint.image, fill: true)
                .frame(height: 44)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            HStack(spacing: 4) {
                Text(paint.name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: owned ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13))
                    .foregroundStyle(owned ? Palette.accent : Color.secondary.opacity(0.6))
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(owned ? Palette.accent.opacity(0.12) : Color.primary.opacity(hovering ? 0.08 : 0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(owned ? Palette.accent : Color.primary.opacity(0.08), lineWidth: owned ? 1.5 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture(perform: toggle)
        .onHover { hovering = $0 }
    }
}
