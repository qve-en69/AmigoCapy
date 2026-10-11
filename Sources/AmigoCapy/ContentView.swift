import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: ClickerModel
    @StateObject private var paints = PaintStore()
    @FocusState private var intervalFocused: Bool
    @State private var intervalText = ""

    var body: some View {
        VStack(spacing: 12) {
            header
            tabBar
            tabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, 18)
        .padding(.top, 4)
        .padding(.bottom, 16)
        .frame(minWidth: 400, idealWidth: 420, maxWidth: 680, minHeight: 620, idealHeight: 800, maxHeight: .infinity)
        .background(Backdrop().ignoresSafeArea())
        .background(WindowAccessor { model.attach(window: $0) })
        .overlay { dialogs }
        .animation(.easeInOut(duration: 0.2), value: model.hasAccessibility)
        .onAppear {
            intervalText = String(model.intervalMs)
            Task { @MainActor in model.checkOtherCopies() }
        }
        .onChange(of: intervalFocused) { focused in
            model.setEditingInterval(focused)
            if !focused { intervalText = String(model.intervalMs) }
        }
        .onChange(of: model.intervalMs) { value in
            if Int(intervalText) != value { intervalText = String(value) }
        }
    }

    @ViewBuilder private var tabContent: some View {
        switch model.tab {
        case 1:
            PaintPickerView(store: paints)
        case 2:
            MyPaintsView(store: paints)
        default:
            clickerTab
        }
    }

    @ViewBuilder private var dialogs: some View {
        if model.showRejoinDialog {
            DialogBackdrop(onDismiss: { model.showRejoinDialog = false }) {
                RejoinDialog()
            }
        } else if model.showHelp {
            DialogBackdrop(onDismiss: { model.showHelp = false }) {
                HelpDialog()
            }
        }
    }

    // MARK: - Шапка и вкладки

    private var header: some View {
        HStack(spacing: 8) {
            AppGlyph()
                .frame(width: 34, height: 34)
            Text("AmigoCapy")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .padding(.leading, 2)
            Spacer(minLength: 4)
            StatusPill(text: status.text, color: status.color, pulsing: status.pulsing)
            HeaderIconButton(systemName: "questionmark", help: "Справка — что умеет приложение") {
                model.showRejoinDialog = false
                model.showHelp = true
            }
            HeaderIconButton(systemName: model.alwaysOnTop ? "pin.fill" : "pin",
                             active: model.alwaysOnTop,
                             help: model.alwaysOnTop ? "Окно закреплено поверх остальных"
                                                     : "Закрепить окно поверх остальных") {
                model.alwaysOnTop.toggle()
            }
        }
    }

    private var status: (text: String, color: Color, pulsing: Bool) {
        if model.isPicking { return ("Выбор точки", Palette.blueDot, false) }
        if let n = model.rejoinCountdown { return ("Перезаход через \(n)", .orange, true) }
        if let n = model.countdown { return ("Старт через \(n)", .orange, true) }
        if model.isRunning { return ("Кликает", Palette.accent, true) }
        return ("Готов", .gray, false)
    }

    private var tabBar: some View {
        HStack(spacing: 3) {
            TabButton(title: "Кликер", icon: "cursorarrow.click", selected: model.tab == 0) { model.tab = 0 }
            TabButton(title: "Подбор", icon: "paintpalette", selected: model.tab == 1) { model.tab = 1 }
            TabButton(title: "Мои краски", icon: "checkmark", selected: model.tab == 2) { model.tab = 2 }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
    }

    // MARK: - Кликер

    private var clickerTab: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 12) {
                    intervalCard
                    targetCard
                    hotKeyCard
                    GoldCard(gold: model.gold)
                    if !model.hasAccessibility {
                        accessibilityBanner
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(.bottom, 4)
            }
            startSection
        }
    }

    private var intervalCard: some View {
        Card("Интервал", icon: "timer") {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                TextField("50", text: $intervalText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 28, weight: .semibold, design: .rounded).monospacedDigit())
                    .focused($intervalFocused)
                    .onSubmit { intervalFocused = false }
                    .onChange(of: intervalText) { text in
                        let digits = String(text.filter { $0.isASCII && $0.isNumber }.prefix(6))
                        if digits != text {
                            intervalText = digits
                            return
                        }
                        if let value = Int(digits), value > 0 { model.intervalMs = value }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .frame(width: 128)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(intervalFocused ? Palette.accent : Color.clear, lineWidth: 1.5)
                    )
                Text("мс")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(rateText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                ForEach(ClickerModel.presets, id: \.self) { value in
                    PresetChip(title: value >= 1000 ? "\(value / 1000) с" : "\(value)",
                               selected: model.intervalMs == value) {
                        model.intervalMs = value
                        intervalFocused = false
                    }
                }
            }
        }
    }

    private var rateText: String {
        let ms = model.intervalMs
        if ms <= 1000 {
            let perSecond = 1000.0 / Double(ms)
            return perSecond >= 10
                ? "≈ \(Int(perSecond.rounded())) в секунду"
                : String(format: "≈ %.1f в секунду", perSecond)
        }
        return String(format: "раз в %.1f с", Double(ms) / 1000)
    }

    private var targetCard: some View {
        Card("Куда кликать", icon: "scope") {
            Picker("", selection: $model.mode) {
                Text("Под курсором").tag(TargetMode.cursor)
                Text("В выбранную точку").tag(TargetMode.point)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if model.mode == .cursor {
                Text("Кликает туда, где сейчас курсор")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                PointRow(title: "Красные", color: Palette.redDot, point: model.redPoint,
                         dimmed: model.team == 1) { model.pickLocation(1) }
                PointRow(title: "Синие", color: Palette.blueDot, point: model.bluePoint,
                         dimmed: model.team == 0) { model.pickLocation(2) }
                teamRow
            }
        }
    }

    private var teamRow: some View {
        HStack(spacing: 8) {
            Text("Заходить за")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize()
            Picker("", selection: $model.team) {
                Text("Красных").tag(0)
                Text("Синих").tag(1)
                Text("Обе").tag(2)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Button {
                model.showPoints()
            } label: {
                Label("Показать", systemImage: "eye")
            }
            .buttonStyle(SoftButtonStyle())
            .disabled(model.redPoint == nil && model.bluePoint == nil)
            .help("На 3 секунды подсветить на экране, где стоят точки")
        }
    }

    private var hotKeyCard: some View {
        Card("Горячая клавиша", icon: "keyboard") {
            HStack(spacing: 12) {
                Keycap(text: model.isRecordingHotKey ? "…" : model.hotKey.display,
                       highlighted: model.isRecordingHotKey)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.isRecordingHotKey ? "Нажми нужную клавишу" : "Старт и стоп")
                        .font(.system(size: 13, weight: .medium))
                    if model.hotKeyConflict && !model.isRecordingHotKey {
                        Text("Клавиша занята другой программой — выбери другую")
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                    } else {
                        Text(model.isRecordingHotKey ? "Esc — отмена" : "Работает, пока окно не свёрнуто")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                Button(model.isRecordingHotKey ? "Отмена" : "Изменить") {
                    model.toggleRecording()
                }
                .buttonStyle(SoftButtonStyle())
            }
            HStack(spacing: 6) {
                Text("Сигнал при старте")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                ToggleChip(title: "Звук", icon: "speaker.wave.2.fill", on: model.soundOn) {
                    model.soundOn.toggle()
                }
                .help("Короткий звук при старте и остановке кликов")
                ToggleChip(title: "Подсказка", icon: "text.bubble", on: model.toastOn) {
                    model.toastOn.toggle()
                }
                .help("Плашка «Кликер включён / выключен» сверху экрана")
            }
        }
    }

    private var accessibilityBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 15))
                .foregroundStyle(.orange)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 6) {
                Text("Нужен доступ к управлению")
                    .font(.system(size: 13, weight: .semibold))
                Text("Без него macOS не пропустит клики. Включи AmigoCapy в «Конфиденциальность и безопасность → Универсальный доступ».")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Открыть настройки") {
                    model.openAccessibilitySettings()
                }
                .buttonStyle(SoftButtonStyle(tint: .orange))
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.orange.opacity(0.12))
        )
    }

    // MARK: - Старт и перезаход

    private var startSection: some View {
        VStack(spacing: 8) {
            Button {
                intervalFocused = false
                model.startStopButton()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: buttonIcon)
                        .font(.system(size: 13, weight: .bold))
                    Text(buttonTitle)
                    Text(model.hotKey.display)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.white.opacity(0.22))
                        )
                }
            }
            .buttonStyle(GradientButtonStyle(colors: buttonColors))
            .disabled(model.isPicking)
            .opacity(model.isPicking ? 0.5 : 1)
            .animation(.easeInOut(duration: 0.2), value: model.isRunning)

            Button {
                intervalFocused = false
                model.rejoinButton()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise")
                    Text(rejoinTitle)
                    if model.rejoinCountdown == nil {
                        Text("клик → Esc → Enter → клики")
                            .font(.system(size: 11))
                            .opacity(0.75)
                    }
                }
            }
            .buttonStyle(WideSoftButtonStyle())
            .disabled(model.isPicking)
            .help("Выбор команды, отсчёт 3-2-1, клик в точку, Esc, Enter и 2 секунды кликов в «Играть»")

            HStack(spacing: 5) {
                Image(systemName: "exclamationmark.triangle.fill")
                Text(rejoinHint)
            }
            .font(.system(size: 11))
            .foregroundStyle(Palette.orange)

            Text(hintText)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 10)
    }

    private var buttonTitle: String {
        if let n = model.countdown { return "Отменить старт · \(n)" }
        return model.isRunning ? "Стоп" : "Старт"
    }

    private var buttonIcon: String {
        if model.countdown != nil { return "xmark" }
        return model.isRunning ? "stop.fill" : "play.fill"
    }

    private var buttonColors: [Color] {
        if model.countdown != nil { return Palette.wait }
        return model.isRunning ? Palette.stop : Palette.start
    }

    private var rejoinTitle: String {
        if let n = model.rejoinCountdown { return "Отменить перезаход · \(n)" }
        return "Перезаход"
    }

    private var rejoinHint: String {
        model.redPoint == nil && model.bluePoint == nil
            ? "Сначала выбери точку «Играть» · только в битве и в окне"
            : "Только в битве и в оконном режиме игры"
    }

    private var hintText: String {
        let key = model.hotKey.display
        if intervalFocused && !model.isRunning { return "Enter — применить, затем жми \(key)" }
        if model.isRunning || model.countdown != nil { return "\(key) или Esc — стоп" }
        return "\(key) — старт, пока окно открыто"
    }
}

/// Строка точки «Играть» за команду. Бледнеет только подпись — кнопка выбора всегда яркая.
private struct PointRow: View {
    let title: String
    let color: Color
    let point: CGPoint?
    let dimmed: Bool
    let pick: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 9) {
                Circle()
                    .fill(color)
                    .frame(width: 10, height: 10)
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .frame(width: 66, alignment: .leading)
                if let point {
                    Text(verbatim: "X \(Int(point.x))   Y \(Int(point.y))")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                } else {
                    Text("не выбрана")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .opacity(dimmed ? 0.45 : 1)
            Spacer(minLength: 0)
            Button(action: pick) {
                Label(point == nil ? "Выбрать" : "Заново", systemImage: "scope")
            }
            .buttonStyle(SoftButtonStyle())
        }
    }
}

/// Карточка «Таймер голда»: клавиша 7, запуск/сброс и включение.
private struct GoldCard: View {
    @EnvironmentObject private var model: ClickerModel
    @ObservedObject var gold: GoldTimer

    var body: some View {
        Card("Таймер голда", icon: "clock") {
            HStack(spacing: 12) {
                Keycap(text: "7", edge: Color(red: 0.89, green: 0.64, blue: 0.10))
                    .opacity(model.goldTimerOn ? 1 : 0.45)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Голд упадёт примерно через 45 с")
                        .font(.system(size: 13, weight: .medium))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(model.goldTimerOn && model.goldConflict ? Color.red : Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Button(gold.isRunning ? "Сбросить" : "Запустить") {
                    gold.toggle(sound: model.soundOn)
                }
                .buttonStyle(SoftButtonStyle())
                .help("То же, что нажать 7")
                ToggleChip(title: model.goldTimerOn ? "Вкл" : "Выкл", on: model.goldTimerOn) {
                    model.goldTimerOn.toggle()
                }
                .help("Включить или выключить клавишу 7")
            }
        }
    }

    private var subtitle: String {
        guard model.goldTimerOn else { return "Выключен — клавиша 7 работает как обычно" }
        if model.goldConflict {
            return model.hotKey.keyCode == ClickerModel.goldKey.keyCode && model.hotKey.modifiers == 0
                ? "Клавиша 7 уже стоит на кликере — смени её там"
                : "Клавиша 7 занята другой программой"
        }
        return "Жми 7 — сверху пойдёт отсчёт, ещё раз 7 — сброс"
    }
}
