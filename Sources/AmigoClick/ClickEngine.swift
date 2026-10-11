import CoreGraphics
import Foundation

/// Шлёт системные клики левой кнопкой по таймеру на отдельной очереди,
/// чтобы интерфейс не влиял на ритм кликов.
final class ClickEngine: @unchecked Sendable {
    private let queue = DispatchQueue(label: "app.amigoclick.engine", qos: .userInteractive)
    private let lock = NSLock()
    private var timer: DispatchSourceTimer?
    private var clickCount = 0

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return clickCount
    }

    func resetCount() {
        lock.lock()
        clickCount = 0
        lock.unlock()
    }

    /// `target == nil` — кликать туда, где сейчас курсор.
    /// Координаты в системе CoreGraphics: (0, 0) — левый верхний угол главного экрана.
    func start(intervalMs: Int, target: CGPoint?) {
        stop()
        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(max(1, intervalMs)), leeway: .nanoseconds(0))
        timer.setEventHandler { [weak self] in
            self?.click(at: target)
        }
        self.timer = timer
        timer.resume()
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func click(at target: CGPoint?) {
        let location = target ?? CGEvent(source: nil)?.location ?? .zero
        let source = CGEventSource(stateID: .hidSystemState)
        guard
            let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown,
                               mouseCursorPosition: location, mouseButton: .left),
            let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp,
                             mouseCursorPosition: location, mouseButton: .left)
        else { return }

        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)

        lock.lock()
        clickCount += 1
        lock.unlock()
    }
}
