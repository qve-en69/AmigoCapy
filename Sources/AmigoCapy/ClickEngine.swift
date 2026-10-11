import CoreGraphics
import Foundation

/// Системные клики и нажатия клавиш через CGEvent (нужен «Универсальный доступ»).
enum Input {
    /// `point == nil` — кликнуть там, где сейчас курсор.
    /// Координаты CoreGraphics: (0, 0) — левый верхний угол главного экрана.
    static func click(at point: CGPoint?) {
        let location = point ?? CGEvent(source: nil)?.location ?? .zero
        let source = CGEventSource(stateID: .hidSystemState)
        guard
            let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown,
                               mouseCursorPosition: location, mouseButton: .left),
            let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp,
                             mouseCursorPosition: location, mouseButton: .left)
        else { return }

        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    /// Нажать и отпустить клавишу в активном приложении.
    static func pressKey(_ keyCode: CGKeyCode) {
        let source = CGEventSource(stateID: .hidSystemState)
        CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)?.post(tap: .cghidEventTap)
        CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)?.post(tap: .cghidEventTap)
    }
}

/// Шлёт системные клики левой кнопкой по таймеру на отдельной очереди,
/// чтобы интерфейс не влиял на ритм кликов.
final class ClickEngine: @unchecked Sendable {
    private let queue = DispatchQueue(label: "app.amigocapy.engine", qos: .userInteractive)
    private var timer: DispatchSourceTimer?

    /// Пустой `targets` — кликать туда, где сейчас курсор; иначе по очереди в эти точки.
    func start(intervalMs: Int, targets: [CGPoint]) {
        stop()
        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(max(1, intervalMs)), leeway: .nanoseconds(0))
        timer.setEventHandler {
            if targets.isEmpty {
                Input.click(at: nil)
                return
            }
            for (index, point) in targets.enumerated() {
                // Небольшая пауза между точками, чтобы игра успела принять оба клика.
                if index > 0 { usleep(15_000) }
                Input.click(at: point)
            }
        }
        self.timer = timer
        timer.resume()
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }
}
