import AppKit
import ApplicationServices
import Carbon.HIToolbox
import SwiftUI

enum TargetMode: String {
    case cursor
    case point
}

/// Номера системных горячих клавиш.
private enum HotKeyID {
    static let clicker: UInt32 = 1
    static let gold: UInt32 = 2
    static let escape: UInt32 = 3
}

@MainActor
final class ClickerModel: ObservableObject {
    static let intervalRange = 1...600_000
    static let presets = [10, 50, 100, 250, 500, 1000]
    /// Клавиша таймера голда — цифра 7.
    static let goldKey = HotKey(keyCode: UInt32(kVK_ANSI_7), modifiers: 0, name: "7")
    /// Сколько секунд кликать в «Играть» после перезахода, потом кликер выключается сам.
    static let rejoinClickSeconds: UInt64 = 2

    @Published var intervalMs = 50 {
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
            pickMissingPointIfNeeded()
            if isRunning { restartEngine() }
        }
    }

    /// За кого заходить в режиме точки: 0 — красные, 1 — синие, 2 — обе по очереди.
    @Published var team = 0 {
        didSet {
            defaults.set(team, forKey: Keys.team)
            pickMissingPointIfNeeded()
            if isRunning { restartEngine() }
        }
    }

    @Published var alwaysOnTop = false {
        didSet {
            defaults.set(alwaysOnTop, forKey: Keys.onTop)
            applyWindowLevel()
        }
    }

    /// 0 — кликер, 1 — подбор краски, 2 — мои краски.
    @Published var tab = 0 {
        didSet { defaults.set(tab, forKey: Keys.tab) }
    }

    @Published var soundOn = true {
        didSet {
            defaults.set(soundOn, forKey: Keys.sound)
            if soundOn { Sounds.play(true) }
        }
    }

    @Published var toastOn = true {
        didSet {
            defaults.set(toastOn, forKey: Keys.toast)
            if toastOn { Toast.show(started: true, hint: "так выглядит подсказка") }
        }
    }

    @Published var goldTimerOn = true {
        didSet {
            defaults.set(goldTimerOn, forKey: Keys.gold)
            if !goldTimerOn { gold.close() }
            updateHotKeyRegistration()
        }
    }

    /// Кнопка «Играть» за красных (точка 1) и за синих (точка 2), координаты CoreGraphics.
    @Published private(set) var redPoint: CGPoint? = nil {
        didSet { savePoint(redPoint, has: Keys.hasPoint, x: Keys.pointX, y: Keys.pointY) }
    }

    @Published private(set) var bluePoint: CGPoint? = nil {
        didSet { savePoint(bluePoint, has: Keys.hasPoint2, x: Keys.point2X, y: Keys.point2Y) }
    }

    @Published private(set) var hotKey = HotKey.default
    @Published private(set) var hotKeyConflict = false
    @Published private(set) var goldConflict = false
    @Published private(set) var isRunning = false
    @Published private(set) var countdown: Int? = nil
    @Published private(set) var rejoinCountdown: Int? = nil
    @Published private(set) var isRecordingHotKey = false
    @Published private(set) var isPicking = false
    @Published private(set) var hasAccessibility = AXIsProcessTrusted()
    @Published var showRejoinDialog = false
    @Published var showHelp = false

    let gold: GoldTimer

    private let engine = ClickEngine()
    private lazy var picker = LocationPicker()
    private var defaults: UserDefaults { .standard }
    private weak var window: NSWindow?
    private var trustTimer: Timer?
    private var countdownTask: Task<Void, Never>?
    private var rejoinTask: Task<Void, Never>?
    private var rejoinBanner: CountdownBanner?
    private var rejoinRun = 0
    private var rejoinAfterPick = false
    private var recordMonitor: Any?
    private var observers: [NSObjectProtocol] = []
    private var editingInterval = false
    private var appActive = true
    private var minimized = false
    /// Пока true, смена режима или команды не открывает выбор точки сама.
    private var quiet = false
    /// Последнее чужое активное приложение (обычно игра) — для перезахода.
    private var lastExternalApp: NSRunningApplication?

    private enum Keys {
        static let interval = "intervalMs"
        static let mode = "targetMode"
        static let onTop = "alwaysOnTop"
        static let hasPoint = "hasPoint"
        static let pointX = "pointX"
        static let pointY = "pointY"
        static let hasPoint2 = "hasPoint2"
        static let point2X = "point2X"
        static let point2Y = "point2Y"
        static let team = "team"
        static let tab = "tab"
        static let sound = "soundOn"
        static let toast = "toastOn"
        static let gold = "goldTimerOn"
        static let hotKeyCode = "hotKeyCode"
        static let hotKeyModifiers = "hotKeyModifiers"
        static let hotKeyName = "hotKeyName"
        static let migrated = "migratedFromAmigoClick"
    }

    init() {
        gold = GoldTimer.shared
        let d = UserDefaults.standard
        Self.migrateFromAmigoClick(d)

        _intervalMs = Published(initialValue: (d.object(forKey: Keys.interval) as? Int) ?? 50)
        _mode = Published(initialValue: TargetMode(rawValue: d.string(forKey: Keys.mode) ?? "") ?? .cursor)
        _team = Published(initialValue: min(max(d.integer(forKey: Keys.team), 0), 2))
        _alwaysOnTop = Published(initialValue: d.bool(forKey: Keys.onTop))
        _tab = Published(initialValue: min(max(d.integer(forKey: Keys.tab), 0), 2))
        _soundOn = Published(initialValue: (d.object(forKey: Keys.sound) as? Bool) ?? true)
        _toastOn = Published(initialValue: (d.object(forKey: Keys.toast) as? Bool) ?? true)
        _goldTimerOn = Published(initialValue: (d.object(forKey: Keys.gold) as? Bool) ?? true)
        if d.bool(forKey: Keys.hasPoint) {
            _redPoint = Published(initialValue: CGPoint(x: d.double(forKey: Keys.pointX), y: d.double(forKey: Keys.pointY)))
        }
        if d.bool(forKey: Keys.hasPoint2) {
            _bluePoint = Published(initialValue: CGPoint(x: d.double(forKey: Keys.point2X), y: d.double(forKey: Keys.point2Y)))
        }
        if d.object(forKey: Keys.hotKeyCode) != nil, let name = d.string(forKey: Keys.hotKeyName) {
            _hotKey = Published(initialValue: HotKey(keyCode: UInt32(d.integer(forKey: Keys.hotKeyCode)),
                                                     modifiers: UInt32(d.integer(forKey: Keys.hotKeyModifiers)),
                                                     name: name))
        }
        if mode == .point && redPoint == nil && bluePoint == nil {
            _mode = Published(initialValue: .cursor)
        }

        HotKeyCenter.shared.handlers[HotKeyID.clicker] = { [weak self] in
            guard let self else { return }
            Task { @MainActor in self.toggle() }
        }
        HotKeyCenter.shared.handlers[HotKeyID.escape] = { [weak self] in
            guard let self else { return }
            Task { @MainActor in self.stop(reason: "нажат Esc") }
        }
        HotKeyCenter.shared.handlers[HotKeyID.gold] = { [weak self] in
            guard let self else { return }
            Task { @MainActor in self.gold.toggle(sound: self.soundOn) }
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

    /// Один раз переносим настройки, оставшиеся от старого названия AmigoClick.
    private static func migrateFromAmigoClick(_ d: UserDefaults) {
        guard !d.bool(forKey: Keys.migrated) else { return }
        d.set(true, forKey: Keys.migrated)
        guard let old = UserDefaults(suiteName: "app.amigoclick.AmigoClick") else { return }
        let keys = [Keys.interval, Keys.mode, Keys.onTop, Keys.hasPoint, Keys.pointX, Keys.pointY,
                    Keys.hotKeyCode, Keys.hotKeyModifiers, Keys.hotKeyName]
        for key in keys where d.object(forKey: key) == nil {
            if let value = old.object(forKey: key) { d.set(value, forKey: key) }
        }
    }

    // MARK: - Старт / стоп

    /// Горячая клавиша: мгновенный старт или стоп.
    func toggle() {
        if isPicking || isRecordingHotKey { return }
        showRejoinDialog = false
        if isRunning || countdown != nil || rejoinCountdown != nil {
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
        if mode == .point && !pointsReady {
            pickLocation(missingPoint)
            return
        }
        refreshTrust()
        engine.start(intervalMs: intervalMs, targets: currentTargets)
        isRunning = true
        signal(started: true)
        updateHotKeyRegistration()
    }

    /// - Parameter reason: почему остановились (для плашки), если стоп не от кнопки или клавиши.
    func stop(reason: String? = nil) {
        countdownTask?.cancel()
        countdownTask = nil
        countdown = nil
        cancelRejoin()
        if isRunning {
            engine.stop()
            isRunning = false
            signal(started: false, reason: reason)
        }
        updateHotKeyRegistration()
    }

    /// Звук и плашка сверху экрана, чтобы было понятно, что кликер включился или выключился.
    private func signal(started: Bool, reason: String? = nil) {
        if soundOn { Sounds.play(started) }
        if toastOn { Toast.show(started: started, hint: started ? "\(hotKey.display) или Esc — стоп" : reason) }
    }

    /// Пусто — кликать под курсором; иначе в точки выбранной команды.
    private var currentTargets: [CGPoint] {
        guard mode == .point else { return [] }
        var result: [CGPoint] = []
        if team != 1, let redPoint { result.append(redPoint) }
        if team != 0, let bluePoint { result.append(bluePoint) }
        return result
    }

    /// Выбраны ли точки, нужные для текущего «Заходить за».
    var pointsReady: Bool {
        (team == 1 || redPoint != nil) && (team == 0 || bluePoint != nil)
    }

    /// Какой точки не хватает: 1 — красные, 2 — синие.
    private var missingPoint: Int {
        team != 1 && redPoint == nil ? 1 : 2
    }

    private func pickMissingPointIfNeeded() {
        guard !quiet, mode == .point, !pointsReady, !isPicking else { return }
        Task { @MainActor in self.pickLocation(self.missingPoint) }
    }

    private func quietly(_ change: () -> Void) {
        quiet = true
        change()
        quiet = false
    }

    private func restartEngine() {
        engine.start(intervalMs: intervalMs, targets: currentTargets)
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

    // MARK: - Перезаход

    /// Кнопка «Перезаход»: открывает окошко с предупреждениями и выбором команды
    /// (а во время отсчёта — отменяет перезаход).
    func rejoinButton() {
        if rejoinCountdown != nil {
            stop()
            return
        }
        stop()
        showHelp = false
        showRejoinDialog = true
    }

    /// Выбрать точку прямо из окошка перезахода, а затем вернуться к нему.
    func pickForRejoin(_ which: Int) {
        showRejoinDialog = false
        rejoinAfterPick = true
        pickLocation(which)
    }

    /// - Parameter team: 0 — за красных, 1 — за синих. Выбор запоминается в «Заходить за».
    func beginRejoin(team: Int) {
        showRejoinDialog = false
        quietly { self.team = team }
        guard pointsReady else { return }
        stop()

        rejoinRun += 1
        let run = rejoinRun
        rejoinCountdown = 3
        rejoinBanner = CountdownBanner(text: team == 0 ? "Перезаход за красных через" : "Перезаход за синих через",
                                       value: 3, colors: team == 0 ? Palette.red : Palette.blue)
        if soundOn { Sounds.tick() }
        updateHotKeyRegistration()

        rejoinTask = Task { @MainActor [weak self] in
            for n in [2, 1] {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, run == self.rejoinRun else { return }
                self.rejoinCountdown = n
                self.rejoinBanner?.value = n
                if self.soundOn { Sounds.tick() }
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard let self, run == self.rejoinRun else { return }
            self.rejoinCountdown = nil
            self.rejoinBanner?.close()
            self.rejoinBanner = nil
            // Esc больше не перехватываем — сейчас его нажмём сами.
            self.updateHotKeyRegistration()
            await self.performRejoin(run)
        }
    }

    /// Клик в точку (окно игры станет активным) → Esc → Enter → клики в «Играть» 2 секунды — и стоп.
    private func performRejoin(_ run: Int) async {
        if mode != .point {
            quietly { self.mode = .point }
        }
        if NSApp.isActive, let app = lastExternalApp {
            app.activate(options: [])
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard run == rejoinRun else { return }
        }
        if let first = currentTargets.first {
            Input.click(at: first)
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard run == rejoinRun else { return }
        }
        Input.pressKey(CGKeyCode(kVK_Escape))
        try? await Task.sleep(nanoseconds: 150_000_000)
        guard run == rejoinRun else { return }
        Input.pressKey(CGKeyCode(kVK_Return))
        try? await Task.sleep(nanoseconds: 120_000_000)
        guard run == rejoinRun else { return }

        start()

        // Ручной стоп или новый перезаход меняют rejoinRun — тогда чужой запуск не трогаем.
        try? await Task.sleep(nanoseconds: Self.rejoinClickSeconds * 1_000_000_000)
        if run == rejoinRun && isRunning { stop(reason: "перезаход выполнен") }
    }

    private func cancelRejoin() {
        rejoinRun += 1
        rejoinTask?.cancel()
        rejoinTask = nil
        rejoinCountdown = nil
        rejoinBanner?.close()
        rejoinBanner = nil
    }

    // MARK: - Выбор точки

    /// - Parameter which: 1 — «Играть» за красных, 2 — за синих.
    func pickLocation(_ which: Int) {
        guard !isPicking else { return }
        stop()
        showRejoinDialog = false
        isPicking = true
        window?.orderOut(nil)

        let hint = which == 1 ? "Кликни на кнопку «Играть» за КРАСНЫХ" : "Кликни на кнопку «Играть» за СИНИХ"
        picker.begin(hint: hint) { [weak self] picked in
            guard let self else { return }
            self.isPicking = false
            if let picked {
                if which == 2 {
                    self.bluePoint = picked
                } else {
                    self.redPoint = picked
                }
                if self.mode != .point { self.quietly { self.mode = .point } }
            } else if self.redPoint == nil && self.bluePoint == nil {
                self.quietly { self.mode = .cursor }
            }
            NSApp.activate(ignoringOtherApps: true)
            self.window?.makeKeyAndOrderFront(nil)
            if self.rejoinAfterPick {
                self.rejoinAfterPick = false
                if picked != nil { self.showRejoinDialog = true }
            }
        }
    }

    /// «Показать»: подсветить на экране, где стоят точки.
    func showPoints() {
        var markers: [(point: CGPoint, label: String, color: Color)] = []
        if let redPoint { markers.append((point: redPoint, label: "Красные", color: Palette.redDot)) }
        if let bluePoint { markers.append((point: bluePoint, label: "Синие", color: Palette.blueDot)) }
        PointMarkers.show(markers)
    }

    // MARK: - Горячие клавиши

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

    /// Пока в поле интервала печатают, клавиши 6 и 7 нужны для ввода цифр — отпускаем их.
    func setEditingInterval(_ editing: Bool) {
        editingInterval = editing
        updateHotKeyRegistration()
    }

    /// Клавиша старта работает, пока окно не свёрнуто. Во время кликов она и Esc работают всегда,
    /// чтобы кликер точно можно было остановить.
    private func updateHotKeyRegistration() {
        let center = HotKeyCenter.shared
        let busy = isRunning || countdown != nil || rejoinCountdown != nil
        let suspended = isRecordingHotKey || minimized || (!busy && editingInterval && appActive)
        if suspended {
            center.unregister(id: HotKeyID.clicker)
            hotKeyConflict = false
        } else {
            hotKeyConflict = !center.register(id: HotKeyID.clicker, keyCode: hotKey.keyCode, modifiers: hotKey.modifiers)
        }

        // Esc — аварийный стоп, только пока кликер занят.
        let escapeIsHotKey = hotKey.keyCode == UInt32(kVK_Escape) && hotKey.modifiers == 0
        if busy && !escapeIsHotKey {
            center.register(id: HotKeyID.escape, keyCode: UInt32(kVK_Escape), modifiers: 0)
        } else {
            center.unregister(id: HotKeyID.escape)
        }

        let goldSuspended = !goldTimerOn || isRecordingHotKey || minimized || (editingInterval && appActive)
        if goldSuspended {
            center.unregister(id: HotKeyID.gold)
            goldConflict = false
        } else {
            goldConflict = !center.register(id: HotKeyID.gold, keyCode: Self.goldKey.keyCode, modifiers: 0)
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
        // Запоминаем последнее чужое приложение, чтобы при перезаходе вернуть фокус игре.
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                               object: nil, queue: .main) { [weak self] note in
            guard
                let self,
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                app.processIdentifier != ProcessInfo.processInfo.processIdentifier
            else { return }
            Task { @MainActor in self.lastExternalApp = app }
        })
    }

    // MARK: - Две копии

    /// Две копии мешают друг другу: клавиша старта достаётся только одной. Предлагаем закрыть старую.
    func checkOtherCopies() {
        let me = ProcessInfo.processInfo.processIdentifier
        var ids = ["app.amigoclick.AmigoClick"]
        if let mine = Bundle.main.bundleIdentifier { ids.append(mine) }
        let others = ids
            .flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0) }
            .filter { $0.processIdentifier != me }
        guard !others.isEmpty else { return }

        let alert = NSAlert()
        alert.messageText = "AmigoCapy уже запущен"
        alert.informativeText = "Уже открыта другая копия кликера. Две копии мешают друг другу: "
            + "клавиша старта работает только в одной из них, и кликер может не остановиться.\n\n"
            + "Закрыть старую копию и продолжить?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Закрыть старую")
        alert.addButton(withTitle: "Выйти")
        guard alert.runModal() == .alertFirstButtonReturn else {
            NSApp.terminate(nil)
            return
        }
        others.forEach { $0.terminate() }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            self.updateHotKeyRegistration()
        }
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
        window.collectionBehavior.insert(.fullScreenNone)
        applyWindowLevel()

        // Кликер работает, только пока окно открыто: при сворачивании останавливаемся
        // и отпускаем клавиши, чтобы они снова печатались в других программах.
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSWindow.didMiniaturizeNotification,
                                            object: window, queue: .main) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.minimized = true
                self.showRejoinDialog = false
                self.stop()
            }
        })
        observers.append(center.addObserver(forName: NSWindow.didDeminiaturizeNotification,
                                            object: window, queue: .main) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.minimized = false
                self.updateHotKeyRegistration()
            }
        })
    }

    private func applyWindowLevel() {
        window?.level = alwaysOnTop ? .floating : .normal
    }

    private func savePoint(_ point: CGPoint?, has: String, x: String, y: String) {
        defaults.set(point != nil, forKey: has)
        defaults.set(Double(point?.x ?? 0), forKey: x)
        defaults.set(Double(point?.y ?? 0), forKey: y)
    }
}
