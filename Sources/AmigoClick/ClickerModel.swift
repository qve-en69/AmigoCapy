import AppKit
import ApplicationServices
import Carbon.HIToolbox

enum TargetMode: String {
    case cursor
    case point
}

@MainActor
final class ClickerModel: ObservableObject {
    static let intervalRange = 1...600_000
    static let presets = [10, 50, 100, 250, 500, 1000]

    @Published var intervalMs = 100 {
        didSet {
            let clamped = min(max(intervalMs, Self.intervalRange.lowerBound), Self.intervalRange.upperBound)
            if clamped != intervalMs { intervalMs = clamped }
            defaults.set(intervalMs, forKey: Keys.interval)
            if isRunning { restartEngine() }
        }
    }

    @Published var mode = TargetMode.cursor {
        didSet {
            defaults.set(mode.rawValue, forKey: Keys.mode)
            if mode == .point && point == nil && !isPicking {
                Task { @MainActor in self.pickLocation() }
            }
            if isRunning { restartEngine() }
        }
    }

    @Published var alwaysOnTop = false {
        didSet {
            defaults.set(alwaysOnTop, forKey: Keys.onTop)
            applyWindowLevel()
        }
    }

    @Published private(set) var point: CGPoint? = nil {
        didSet {
            defaults.set(point != nil, forKey: Keys.hasPoint)
            defaults.set(Double(point?.x ?? 0), forKey: Keys.pointX)
            defaults.set(Double(point?.y ?? 0), forKey: Keys.pointY)
        }
    }

    @Published private(set) var hotKey = HotKey.default
    @Published private(set) var hotKeyConflict = false
    @Published private(set) var isRunning = false
    @Published private(set) var countdown: Int? = nil
    @Published private(set) var clicks = 0
    @Published private(set) var isRecordingHotKey = false
    @Published private(set) var isPicking = false
    @Published private(set) var hasAccessibility = AXIsProcessTrusted()

    private let engine = ClickEngine()
    private lazy var picker = LocationPicker()
    private var defaults: UserDefaults { .standard }
    private weak var window: NSWindow?
    private var counterTimer: Timer?
    private var trustTimer: Timer?
    private var countdownTask: Task<Void, Never>?
    private var recordMonitor: Any?
    private var observers: [NSObjectProtocol] = []
    private var editingInterval = false
    private var appActive = true

    private enum Keys {
        static let interval = "intervalMs"
        static let mode = "targetMode"
        static let onTop = "alwaysOnTop"
        static let hasPoint = "hasPoint"
        static let pointX = "pointX"
        static let pointY = "pointY"
        static let hotKeyCode = "hotKeyCode"
        static let hotKeyModifiers = "hotKeyModifiers"
        static let hotKeyName = "hotKeyName"
    }

    init() {
        let d = UserDefaults.standard
        _intervalMs = Published(initialValue: (d.object(forKey: Keys.interval) as? Int) ?? 100)
        _mode = Published(initialValue: TargetMode(rawValue: d.string(forKey: Keys.mode) ?? "") ?? .cursor)
        _alwaysOnTop = Published(initialValue: d.bool(forKey: Keys.onTop))
        if d.bool(forKey: Keys.hasPoint) {
            _point = Published(initialValue: CGPoint(x: d.double(forKey: Keys.pointX),
                                                     y: d.double(forKey: Keys.pointY)))
        }
        if d.object(forKey: Keys.hotKeyCode) != nil, let name = d.string(forKey: Keys.hotKeyName) {
            _hotKey = Published(initialValue: HotKey(keyCode: UInt32(d.integer(forKey: Keys.hotKeyCode)),
                                                     modifiers: UInt32(d.integer(forKey: Keys.hotKeyModifiers)),
                                                     name: name))
        }
        if mode == .point && point == nil {
            _mode = Published(initialValue: .cursor)
        }

        HotKeyCenter.shared.onPress = { [weak self] in
            guard let self else { return }
            Task { @MainActor in self.toggle() }
        }
        updateHotKeyRegistration()
        observeAppActivity()
        startTrustPolling()

        if !hasAccessibility {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 700_000_000)
                self.requestAccessibility()
            }
        }
    }

    // MARK: - Старт / стоп

    /// Горячая клавиша: мгновенный старт или стоп.
    func toggle() {
        if isPicking || isRecordingHotKey { return }
        if isRunning || countdown != nil {
            stop()
        } else {
            start()
        }
    }

    /// Кнопка в окне. В режиме «под курсором» даёт 3 секунды, чтобы увести мышь
    /// с кнопки, иначе первый же клик попал бы в «Стоп».
    func startStopButton() {
        if isRunning || countdown != nil {
            stop()
        } else if mode == .cursor {
            beginCountdown()
        } else {
            start()
        }
    }

    func start() {
        guard !isRunning else { return }
        if mode == .point && point == nil {
            pickLocation()
            return
        }
        refreshTrust()
        clicks = 0
        engine.resetCount()
        engine.start(intervalMs: intervalMs, target: currentTarget)
        isRunning = true
        updateHotKeyRegistration()

        counterTimer?.invalidate()
        counterTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.syncClicks() }
        }
    }

    func stop() {
        countdownTask?.cancel()
        countdownTask = nil
        countdown = nil
        if isRunning {
            engine.stop()
            counterTimer?.invalidate()
            counterTimer = nil
            syncClicks()
            isRunning = false
        }
        updateHotKeyRegistration()
    }

    private var currentTarget: CGPoint? {
        mode == .point ? point : nil
    }

    private func restartEngine() {
        engine.start(intervalMs: intervalMs, target: currentTarget)
    }

    private func syncClicks() {
        let value = engine.count
        if value != clicks { clicks = value }
    }

    private func beginCountdown() {
        countdownTask = Task { @MainActor [weak self] in
            for n in [3, 2, 1] {
                guard let self, !Task.isCancelled else { return }
                self.countdown = n
                self.updateHotKeyRegistration()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            guard let self, !Task.isCancelled else { return }
            self.countdown = nil
            self.countdownTask = nil
            self.start()
        }
    }

    // MARK: - Выбор точки

    func pickLocation() {
        guard !isPicking else { return }
        stop()
        isPicking = true
        window?.orderOut(nil)

        picker.begin { [weak self] picked in
            guard let self else { return }
            self.isPicking = false
            if let picked {
                self.point = picked
                self.mode = .point
            } else if self.point == nil {
                self.mode = .cursor
            }
            NSApp.activate(ignoringOtherApps: true)
            self.window?.makeKeyAndOrderFront(nil)
        }
    }

    // MARK: - Горячая клавиша

    func toggleRecording() {
        if isRecordingHotKey {
            cancelRecording()
        } else {
            beginRecording()
        }
    }

    private func beginRecording() {
        stop()
        isRecordingHotKey = true
        updateHotKeyRegistration()
        recordMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let code = event.keyCode
            let modifiers = HotKey.carbonModifiers(from: event.modifierFlags)
            let name = HotKey.keyName(keyCode: code, characters: event.charactersIgnoringModifiers)
            guard let self else { return nil }
            Task { @MainActor in
                self.finishRecording(code: code, modifiers: modifiers, name: name)
            }
            return nil
        }
    }

    private func finishRecording(code: UInt16, modifiers: UInt32, name: String?) {
        guard isRecordingHotKey else { return }
        if Int(code) == kVK_Escape {
            cancelRecording()
            return
        }
        guard let name else { return } // клавишу не распознали — ждём следующую
        hotKey = HotKey(keyCode: UInt32(code), modifiers: modifiers, name: name)
        defaults.set(Int(hotKey.keyCode), forKey: Keys.hotKeyCode)
        defaults.set(Int(hotKey.modifiers), forKey: Keys.hotKeyModifiers)
        defaults.set(hotKey.name, forKey: Keys.hotKeyName)
        cancelRecording()
    }

    private func cancelRecording() {
        if let recordMonitor {
            NSEvent.removeMonitor(recordMonitor)
        }
        recordMonitor = nil
        isRecordingHotKey = false
        updateHotKeyRegistration()
    }

    /// Пока в поле интервала печатают, клавиша (например, «6») нужна для ввода цифр,
    /// поэтому на это время её отпускаем. Во время кликов клавиша работает всегда,
    /// чтобы кликер можно было остановить.
    func setEditingInterval(_ editing: Bool) {
        editingInterval = editing
        updateHotKeyRegistration()
    }

    private func updateHotKeyRegistration() {
        let busy = isRunning || countdown != nil
        let suspended = isRecordingHotKey || (!busy && editingInterval && appActive)
        if suspended {
            HotKeyCenter.shared.unregister()
            hotKeyConflict = false
        } else {
            hotKeyConflict = !HotKeyCenter.shared.register(keyCode: hotKey.keyCode, modifiers: hotKey.modifiers)
        }
    }

    private func observeAppActivity() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.appActive = true
                self.updateHotKeyRegistration()
                self.refreshTrust()
            }
        })
        observers.append(center.addObserver(forName: NSApplication.didResignActiveNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.appActive = false
                self.updateHotKeyRegistration()
            }
        })
    }

    // MARK: - Универсальный доступ

    private func startTrustPolling() {
        trustTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.refreshTrust() }
        }
    }

    func refreshTrust() {
        let trusted = AXIsProcessTrusted()
        if trusted != hasAccessibility { hasAccessibility = trusted }
    }

    /// Системный запрос доступа; заодно добавляет приложение в список «Универсального доступа».
    func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func openAccessibilitySettings() {
        let link = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        if let url = URL(string: link) {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Окно

    func attach(window: NSWindow) {
        guard self.window !== window else { return }
        self.window = window
        window.isMovableByWindowBackground = true
        window.styleMask.remove(.resizable)
        window.collectionBehavior.insert(.fullScreenNone)
        applyWindowLevel()
    }

    private func applyWindowLevel() {
        window?.level = alwaysOnTop ? .floating : .normal
    }
}
