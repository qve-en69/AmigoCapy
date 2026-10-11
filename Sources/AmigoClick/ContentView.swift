import SwiftUI

enum Palette {
    static let accent = Color(red: 0.10, green: 0.68, blue: 0.58)
    static let start = [Color(red: 0.16, green: 0.80, blue: 0.62), Color(red: 0.15, green: 0.52, blue: 0.95)]
    static let stop = [Color(red: 1.00, green: 0.48, blue: 0.40), Color(red: 0.92, green: 0.26, blue: 0.50)]
    static let wait = [Color(red: 1.00, green: 0.74, blue: 0.30), Color(red: 0.98, green: 0.50, blue: 0.30)]
}

struct ContentView: View {
    @EnvironmentObject private var model: ClickerModel
    @FocusState private var intervalFocused: Bool
    @State private var intervalText = ""

    var body: some View {
        VStack(spacing: 12) {
            header
            intervalCard
            targetCard
            hotKeyCard
            if !model.hasAccessibility {
                accessibilityBanner
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            startSection
        }
        .padding(.horizontal, 18)
        .padding(.top, 4)
        .padding(.bottom, 18)
        .frame(width: 384)
        .fixedSize()
        .background(Backdrop().ignoresSafeArea())
        .background(WindowAccessor { model.attach(window: $0) })
        .animation(.easeInOut(duration: 0.2), value: model.hasAccessibility)
        .onAppear { intervalText = String(model.intervalMs) }
        .onChange(of: intervalFocused) { focused in
            model.setEditingInterval(focused)
            if !focused { intervalText = String(model.intervalMs) }
        }
        .onChange(of: model.intervalMs) { value in
            if Int(intervalText) != value { intervalText = String(value) }
        }
    }

    // MARK: - Шапка

    private var header: some View {
        HStack(spacing: 10) {
            AppGlyph()
                .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 0) {
                Text("AmigoClick")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                Text("автокликер")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            StatusPill(text: status.text, color: status.color, pulsing: status.pulsing)
            Button {
                model.alwaysOnTop.toggle()
            } label: {
                Image(systemName: model.alwaysOnTop ? "pin.fill" : "pin")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(model.alwaysOnTop ? Palette.accent : Color.secondary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.primary.opacity(0.06)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(model.alwaysOnTop ? "Окно закреплено поверх остальных" : "Закрепить окно поверх остальных")
        }
    }

    private var status: (text: String, color: Color, pulsing: Bool) {
        if model.isPicking { return ("Выбор точки", Color(red: 0.15, green: 0.52, blue: 0.95), false) }
        if let n = model.countdown { return ("Старт через \(n)", .orange, true) }
        if model.isRunning { return ("Кликает", Palette.accent, true) }
        return ("Готов", .gray, false)
    }

    // MARK: - Интервал

    private var intervalCard: some View {
        Card("Интервал", icon: "timer") {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                TextField("100", text: $intervalText)
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

    // MARK: - Куда кликать

    private var targetCard: some View {
        Card("Куда кликать", icon: "scope") {
            Picker("", selection: $model.mode) {
                Text("Под курсором").tag(TargetMode.cursor)
                Text("В выбранную точку").tag(TargetMode.point)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack(spacing: 8) {
                if model.mode == .point, let point = model.point {
                    Image(systemName: "mappin.and.ellipse")
                        .foregroundStyle(Palette.accent)
                    Text(verbatim: "X \(Int(point.x))   Y \(Int(point.y))")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                } else if model.mode == .point {
                    Text("Точка ещё не выбрана")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else {
                    Text("Кликает туда, где сейчас курсор")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    model.pickLocation()
                } label: {
                    Label(model.point == nil ? "Выбрать точку" : "Выбрать заново", systemImage: "scope")
                }
                .buttonStyle(SoftButtonStyle())
            }
        }
    }

    // MARK: - Горячая клавиша

    private var hotKeyCard: some View {
        Card("Горячая клавиша", icon: "keyboard") {
            HStack(spacing: 12) {
                Keycap(text: model.isRecordingHotKey ? "…" : model.hotKey.display,
                       highlighted: model.isRecordingHotKey)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.isRecordingHotKey ? "Нажми нужную клавишу" : "Старт и стоп из любого окна")
                        .font(.system(size: 13, weight: .medium))
                    if model.hotKeyConflict {
                        Text("Клавиша занята другой программой — выбери другую")
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                    } else {
                        Text(model.isRecordingHotKey ? "Esc — отмена" : "Работает, даже когда окно свёрнуто")
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
        }
    }

    // MARK: - Доступ

    private var accessibilityBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 15))
                .foregroundStyle(.orange)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 6) {
                Text("Нужен доступ к управлению")
                    .font(.system(size: 13, weight: .semibold))
                Text("Без него macOS не пропустит клики. Включи AmigoClick в «Конфиденциальность и безопасность → Универсальный доступ».")
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

    // MARK: - Старт

    private var startSection: some View {
        VStack(spacing: 10) {
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

            HStack {
                Label {
                    Text("Кликов: \(model.clicks)")
                } icon: {
                    Image(systemName: "cursorarrow.click")
                }
                Spacer()
                Text(hintText)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
        }
        .padding(.top, 4)
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

    private var hintText: String {
        let key = model.hotKey.display
        if intervalFocused && !model.isRunning { return "Enter — применить, затем жми \(key)" }
        if model.isRunning || model.countdown != nil { return "\(key) — остановить" }
        return "\(key) — старт из любого окна"
    }
}

// MARK: - Компоненты

struct Card<Content: View>: View {
    private let title: String
    private let icon: String
    private let content: Content

    init(_ title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(title.uppercased())
                    .tracking(0.8)
            }
            .font(.system(size: 10.5, weight: .bold))
            .foregroundStyle(.secondary)
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

struct PresetChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(selected ? Color.white : Color.primary.opacity(0.8))
                .frame(maxWidth: .infinity)
                .frame(height: 26)
                .background(
                    Capsule().fill(
                        selected
                            ? AnyShapeStyle(LinearGradient(colors: Palette.start, startPoint: .leading, endPoint: .trailing))
                            : AnyShapeStyle(Color.primary.opacity(hovering ? 0.11 : 0.06))
                    )
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: selected)
    }
}

struct Keycap: View {
    let text: String
    var highlighted = false

    var body: some View {
        Text(text)
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .padding(.horizontal, 10)
            .frame(minWidth: 40, minHeight: 40)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .shadow(color: .black.opacity(0.18), radius: 0, x: 0, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(highlighted ? Palette.accent : Color.primary.opacity(0.12),
                                  lineWidth: highlighted ? 2 : 1)
            )
    }
}

struct StatusPill: View {
    let text: String
    let color: Color
    let pulsing: Bool

    var body: some View {
        HStack(spacing: 6) {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !pulsing)) { context in
                let phase = pulsing
                    ? context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.2) / 1.2
                    : 1
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                    .overlay(
                        Circle()
                            .stroke(color, lineWidth: 1.5)
                            .scaleEffect(1 + phase * 1.6)
                            .opacity(pulsing ? 1 - phase : 0)
                    )
            }
            .frame(width: 12, height: 12)
            Text(text)
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(color.opacity(0.14)))
    }
}

struct AppGlyph: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(LinearGradient(colors: Palette.start, startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(
                Image(systemName: "cursorarrow.click.2")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
            )
            .shadow(color: Palette.start[1].opacity(0.35), radius: 6, y: 2)
    }
}

struct GradientButtonStyle: ButtonStyle {
    let colors: [Color]

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .shadow(color: (colors.last ?? .clear).opacity(0.35), radius: 10, y: 4)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct SoftButtonStyle: ButtonStyle {
    var tint: Color = Palette.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(Capsule().fill(tint.opacity(configuration.isPressed ? 0.26 : 0.14)))
            .contentShape(Capsule())
    }
}

struct Backdrop: View {
    var body: some View {
        ZStack {
            VisualEffectBackground()
            LinearGradient(colors: [Palette.start[0].opacity(0.12), .clear],
                           startPoint: .top, endPoint: .center)
        }
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// Даёт модели доступ к NSWindow, чтобы закреплять окно поверх остальных и прятать его при выборе точки.
struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = AccessorView()
        view.onWindow = onWindow
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class AccessorView: NSView {
        var onWindow: ((NSWindow) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { onWindow?(window) }
        }
    }
}
