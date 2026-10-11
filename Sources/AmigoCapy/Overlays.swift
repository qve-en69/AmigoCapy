import AppKit
import SwiftUI

/// Короткие системные звуки старта, остановки и отсчёта.
@MainActor
enum Sounds {
    static func play(_ started: Bool) {
        NSSound(named: started ? "Pop" : "Bottle")?.play()
    }

    static func tick() {
        NSSound(named: "Tink")?.play()
    }

    static func finish() {
        NSSound(named: "Glass")?.play()
    }
}

/// Прозрачные окна поверх всего (в том числе поверх игры), которые не забирают фокус
/// и пропускают клики сквозь себя.
@MainActor
enum Overlay {
    static func makePanel<Content: View>(_ content: Content) -> NSPanel {
        let hosting = NSHostingView(rootView: content)
        let size = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: size)
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .screenSaver
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = hosting
        return panel
    }

    static func screenUnderMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main
    }

    /// По центру сверху экрана, под строкой меню.
    static func placeAtTop(_ panel: NSWindow, screen: NSScreen?) {
        guard let screen else { return }
        let size = panel.frame.size
        let area = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: area.midX - size.width / 2, y: area.maxY - 8 - size.height))
    }

    /// Точка CoreGraphics (0, 0 — левый верхний угол главного экрана) → координаты AppKit.
    static func appKitPoint(_ point: CGPoint) -> NSPoint {
        let height = NSScreen.screens.first?.frame.maxY ?? 0
        return NSPoint(x: point.x, y: height - point.y)
    }

    /// Плавно меняет прозрачность окон.
    static func fade(_ windows: [NSWindow], to target: CGFloat, duration: Double) async {
        let steps = 12
        let starts = windows.map { $0.alphaValue }
        for step in 1...steps {
            try? await Task.sleep(nanoseconds: UInt64(duration / Double(steps) * 1_000_000_000))
            let t = CGFloat(step) / CGFloat(steps)
            for (index, window) in windows.enumerated() {
                window.alphaValue = starts[index] + (target - starts[index]) * t
            }
        }
    }
}

// MARK: - Плашка «Кликер включён / выключен»

@MainActor
enum Toast {
    private static var panel: NSPanel?
    private static var generation = 0

    static func show(started: Bool, hint: String?) {
        panel?.orderOut(nil)
        generation += 1
        let current = generation
        let window = Overlay.makePanel(ToastView(started: started, hint: hint))
        Overlay.placeAtTop(window, screen: Overlay.screenUnderMouse())
        window.alphaValue = 0
        window.orderFrontRegardless()
        panel = window

        Task { @MainActor in
            await Overlay.fade([window], to: 1, duration: 0.12)
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard current == generation else { return }
            await Overlay.fade([window], to: 0, duration: 0.4)
            guard current == generation else { return }
            window.orderOut(nil)
            panel = nil
        }
    }
}

private struct ToastView: View {
    let started: Bool
    let hint: String?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: started ? "play.fill" : "stop.fill")
                .font(.system(size: 13, weight: .bold))
            Text(started ? "Кликер включён" : "Кликер выключен")
                .font(.system(size: 15, weight: .semibold))
            if let hint {
                Text(hint)
                    .font(.system(size: 12.5))
                    .opacity(0.85)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(
            Capsule().fill(LinearGradient(colors: started ? Palette.start : Palette.stop,
                                          startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
        .padding(16)
        .fixedSize()
    }
}

// MARK: - Отсчёт перезахода

/// Плашка «Перезаход за синих через 3» сверху экрана; висит, пока её не закроют.
@MainActor
final class CountdownBanner: ObservableObject {
    @Published var value: Int
    let text: String
    let colors: [Color]
    private var panel: NSPanel?

    init(text: String, value: Int, colors: [Color]) {
        _value = Published(initialValue: value)
        self.text = text
        self.colors = colors
        let window = Overlay.makePanel(CountdownBannerView(banner: self))
        Overlay.placeAtTop(window, screen: Overlay.screenUnderMouse())
        window.orderFrontRegardless()
        panel = window
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
    }
}

private struct CountdownBannerView: View {
    @ObservedObject var banner: CountdownBanner

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 16, weight: .bold))
            Text(banner.text)
                .font(.system(size: 17, weight: .semibold))
            Text("\(banner.value)")
                .font(.system(size: 26, weight: .bold, design: .rounded).monospacedDigit())
                .frame(minWidth: 20)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(
            Capsule().fill(LinearGradient(colors: banner.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .shadow(color: .black.opacity(0.35), radius: 10, y: 3)
        .padding(16)
        .fixedSize()
    }
}

// MARK: - Таймер голда

/// Клавиша 7: табличка «Голд упадёт примерно через 45 с», в конце — «Удачи, маленький амигос!!».
@MainActor
final class GoldTimer: ObservableObject {
    static let shared = GoldTimer()
    static let seconds = 45

    /// Идёт ли отсчёт (табличка «удачи» уже не считается).
    @Published private(set) var isRunning = false
    @Published private(set) var finished = false
    @Published private(set) var whole = 45
    @Published private(set) var progress = 1.0

    private var panel: NSPanel?
    private var timer: Timer?
    private var startedAt = Date()
    private var sound = true
    private var run = 0

    /// Запустить таймер, а если он уже идёт — сбросить.
    func toggle(sound: Bool) {
        let wasRunning = isRunning
        close()
        if !wasRunning { begin(sound: sound) }
        if sound { Sounds.play(!wasRunning) }
    }

    func close() {
        run += 1
        timer?.invalidate()
        timer = nil
        panel?.orderOut(nil)
        panel = nil
        isRunning = false
        finished = false
    }

    private func begin(sound: Bool) {
        self.sound = sound
        startedAt = Date()
        whole = Self.seconds
        progress = 1
        finished = false
        isRunning = true

        let window = Overlay.makePanel(GoldBannerView(timer: self))
        Overlay.placeAtTop(window, screen: Overlay.screenUnderMouse())
        window.orderFrontRegardless()
        panel = window

        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.update() }
        }
    }

    private func update() {
        guard isRunning else { return }
        let left = Double(Self.seconds) - Date().timeIntervalSince(startedAt)
        if left <= 0 {
            finish()
            return
        }
        progress = left / Double(Self.seconds)
        let value = Int(left.rounded(.up))
        if value != whole {
            whole = value
            if value <= 3 && sound { Sounds.tick() }
        }
    }

    private func finish() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        finished = true
        progress = 0
        if sound { Sounds.finish() }

        let current = run
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 7_000_000_000)
            guard let self, self.run == current, let panel = self.panel else { return }
            await Overlay.fade([panel], to: 0, duration: 0.6)
            if self.run == current { self.close() }
        }
    }
}

private struct GoldBannerView: View {
    @ObservedObject var timer: GoldTimer

    private let ink = Color(red: 0.23, green: 0.15, blue: 0.0)
    private let hurry = Color(red: 0.70, green: 0.15, blue: 0.12)

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                coin
                if timer.finished {
                    Text("Удачи, маленький амигос!!")
                        .font(.system(size: 19, weight: .bold))
                } else {
                    Text("Голд упадёт примерно через")
                        .font(.system(size: 17, weight: .semibold))
                    Text("\(timer.whole)")
                        .font(.system(size: 28, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(timer.whole <= 10 ? hurry : ink)
                    Text("с")
                        .font(.system(size: 17, weight: .semibold))
                }
            }
            progressBar
                .opacity(timer.finished ? 0 : 1)
        }
        .foregroundStyle(ink)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .frame(width: 420)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: Palette.gold, startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.4), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 10, y: 3)
        .padding(16)
    }

    private var coin: some View {
        ZStack {
            Circle().fill(Color(red: 1.0, green: 0.98, blue: 0.92))
            Circle().strokeBorder(Color(red: 0.60, green: 0.40, blue: 0.0), lineWidth: 2)
            Text("G")
                .font(.system(size: 15, weight: .black))
                .foregroundStyle(Color(red: 0.85, green: 0.56, blue: 0.02))
        }
        .frame(width: 28, height: 28)
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(ink.opacity(0.2))
                Capsule().fill(ink).frame(width: geo.size.width * CGFloat(timer.progress))
            }
        }
        .frame(height: 5)
    }
}

// MARK: - Подсветка точек

/// «Показать»: на 3 секунды кольцо и подпись ровно на каждой выбранной точке.
@MainActor
enum PointMarkers {
    private static var panels: [NSPanel] = []
    private static var generation = 0

    static func show(_ markers: [(point: CGPoint, label: String, color: Color)]) {
        panels.forEach { $0.orderOut(nil) }
        panels = []
        generation += 1
        let current = generation

        for marker in markers {
            let text = "\(marker.label)  ·  \(Int(marker.point.x)), \(Int(marker.point.y))"
            let window = Overlay.makePanel(MarkerView(label: text, color: marker.color))
            let center = Overlay.appKitPoint(marker.point)
            window.setFrameOrigin(NSPoint(x: center.x - MarkerView.width / 2,
                                          y: center.y + MarkerView.ringCenterFromTop - MarkerView.height))
            window.orderFrontRegardless()
            panels.append(window)
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            guard current == generation else { return }
            let closing = panels
            await Overlay.fade(closing, to: 0, duration: 0.5)
            guard current == generation else { return }
            closing.forEach { $0.orderOut(nil) }
            panels = []
        }
    }
}

private struct MarkerView: View {
    static let width: CGFloat = 180
    static let height: CGFloat = 100
    static let ringSize: CGFloat = 40
    static let ringTop: CGFloat = 6
    static var ringCenterFromTop: CGFloat { ringTop + ringSize / 2 }

    let label: String
    let color: Color
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.25))
                    .overlay(Circle().stroke(color, lineWidth: 3.5))
                    .scaleEffect(pulse ? 1.35 : 1)
                    .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: pulse)
                Circle()
                    .fill(Color.white)
                    .overlay(Circle().stroke(color, lineWidth: 1.5))
                    .frame(width: 6, height: 6)
            }
            .frame(width: Self.ringSize, height: Self.ringSize)
            Text(label)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(color))
        }
        .padding(.top, Self.ringTop)
        .frame(width: Self.width, height: Self.height, alignment: .top)
        .onAppear { pulse = true }
    }
}
