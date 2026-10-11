import SwiftUI

/// Окошко перед перезаходом: напоминает, что надо быть в битве и в оконном режиме,
/// и спрашивает, за кого заходить. Без точек предлагает сначала их выбрать.
struct RejoinDialog: View {
    @EnvironmentObject private var model: ClickerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Palette.accent)
                Text("Перезаход")
                    .font(.system(size: 16, weight: .bold))
                Spacer()
                HeaderIconButton(systemName: "xmark", help: "Отмена (Esc)") {
                    model.showRejoinDialog = false
                }
            }

            WarningBox(icon: "exclamationmark.triangle.fill",
                       title: "Ты должен быть в битве!",
                       text: "Перезаход нажимает Esc → Enter. В битве это выход из боя, а в меню игры — выход из игры: танки закроются.")
            WarningBox(icon: "macwindow",
                       title: "Только в оконном режиме!",
                       text: "Переключи игру в оконный режим. В полноэкранном перезаход не сработает.")

            if model.redPoint == nil && model.bluePoint == nil {
                noPoints
            } else {
                chooseTeam
            }

            HStack {
                Spacer()
                Button("Отмена") { model.showRejoinDialog = false }
                    .buttonStyle(SoftButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Spacer()
            }
        }
    }

    private var noPoints: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Сначала выбери точку — кнопку «Играть» в лобби битвы. Туда кликер начнёт жать сразу после выхода из боя.")
                .font(.system(size: 12.5))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button { model.pickForRejoin(1) } label: {
                    Label("За красных", systemImage: "scope")
                }
                .buttonStyle(GradientButtonStyle(colors: Palette.red, height: 42))
                Button { model.pickForRejoin(2) } label: {
                    Label("За синих", systemImage: "scope")
                }
                .buttonStyle(GradientButtonStyle(colors: Palette.blue, height: 42))
            }
        }
    }

    private var chooseTeam: some View {
        let both = model.redPoint != nil && model.bluePoint != nil
        return VStack(alignment: .leading, spacing: 10) {
            Text(both ? "За кого перезайти?" : (model.redPoint != nil ? "Перезайти за красных?" : "Перезайти за синих?"))
                .font(.system(size: 13, weight: .semibold))
            HStack(spacing: 10) {
                if model.redPoint != nil {
                    teamButton("За красных", colors: Palette.red) { model.beginRejoin(team: 0) }
                }
                if model.bluePoint != nil {
                    teamButton("За синих", colors: Palette.blue) { model.beginRejoin(team: 1) }
                }
            }
            Text(footnote(both: both))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func teamButton(_ title: String, colors: [Color], action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Circle().fill(Color.white).frame(width: 10, height: 10)
                Text(title)
            }
        }
        .buttonStyle(GradientButtonStyle(colors: colors, height: 48))
    }

    private func footnote(both: Bool) -> String {
        let tail = "Дальше отсчёт 3-2-1 — переключись в игру. Кликер сам выключится через 2 секунды."
        if both { return tail }
        let missing = model.redPoint == nil ? "Точка за красных не выбрана" : "Точка за синих не выбрана"
        return missing + " — её можно поставить в «Куда кликать». " + tail
    }
}

private struct HelpSection: Identifiable {
    let icon: String
    let title: String
    let text: String
    var id: String { title }
}

/// Справка: что умеет приложение.
struct HelpDialog: View {
    @EnvironmentObject private var model: ClickerModel

    private let sections: [HelpSection] = [
        HelpSection(icon: "cursorarrow.click", title: "Кликер",
                    text: "Интервал — раз в сколько миллисекунд кликать (50 мс = 20 кликов в секунду). «Под курсором» — кликает туда, где мышь. «В выбранную точку» — в кнопку «Играть»: выбери точку за красных и за синих, они запоминаются. «Заходить за» — красных, синих или обе по очереди. «Показать» — на 3 секунды подсветит, где стоят точки."),
        HelpSection(icon: "keyboard", title: "Старт и стоп",
                    text: "Клавиша 6 (можно поменять) — старт и стоп из любого окна, пока AmigoCapy не свёрнут. Esc тоже останавливает кликер. При старте и стопе — короткий звук и плашка сверху экрана, их можно выключить кнопками «Звук» и «Подсказка»."),
        HelpSection(icon: "arrow.clockwise", title: "Перезаход",
                    text: "Только в битве и в оконном режиме игры — в меню Esc → Enter закроет игру. Нажми «Перезаход» и выбери команду. Дальше отсчёт 3-2-1, клик в точку (окно игры станет активным), Esc, Enter и 2 секунды кликов в «Играть» — потом кликер выключится сам."),
        HelpSection(icon: "clock", title: "Таймер голда",
                    text: "Нажми 7 — сверху появится табличка «Голд упадёт примерно через 45 с», последние 10 секунд красным, в конце — «Удачи, маленький амигос!!». Ещё раз 7 — сброс. Выключить клавишу — кнопка «Вкл» в карточке."),
        HelpSection(icon: "paintpalette", title: "Подбор краски",
                    text: "Отметь пушки врагов: клик — +1, «−» или правый клик — убрать, до 4 видов. Ниже краски, отсортированные по средней защите от всей команды врагов. «Только мои» — выбирать только из твоих красок."),
        HelpSection(icon: "checkmark", title: "Мои краски",
                    text: "Отметь краски, которые у тебя есть, — в «Подборе» у них будет «✓ есть»."),
        HelpSection(icon: "pin", title: "Полезно знать",
                    text: "Булавка сверху — держать окно поверх игры. Не открывай две копии AmigoCapy сразу. Для кликов нужен доступ в «Конфиденциальность и безопасность → Универсальный доступ»."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Palette.accent)
                Text("Справка")
                    .font(.system(size: 16, weight: .bold))
                Spacer()
                HeaderIconButton(systemName: "xmark", help: "Закрыть (Esc)") {
                    model.showHelp = false
                }
                .keyboardShortcut(.cancelAction)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Image(systemName: section.icon)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Palette.accent)
                                    .frame(width: 16)
                                Text(section.title)
                                    .font(.system(size: 13.5, weight: .semibold))
                            }
                            Text(section.text)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .lineSpacing(2)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.leading, 24)
                        }
                    }
                }
                .padding(.trailing, 8)
            }
        }
    }
}
