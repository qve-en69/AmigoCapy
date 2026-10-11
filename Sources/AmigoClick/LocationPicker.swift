import AppKit

/// Полупрозрачный слой поверх всех экранов: клик выбирает точку, Esc или правый клик — отмена.
/// Отдаёт точку в координатах CoreGraphics (0, 0 — левый верхний угол главного экрана).
@MainActor
final class LocationPicker {
    private var windows: [NSWindow] = []
    private var keyMonitor: Any?
    private var completion: ((CGPoint?) -> Void)?

    func begin(completion: @escaping (CGPoint?) -> Void) {
        guard self.completion == nil else { return }
        self.completion = completion

        let mouse = NSEvent.mouseLocation
        var windowUnderMouse: NSWindow?

        for screen in NSScreen.screens {
            let window = PickerWindow(contentRect: screen.frame, styleMask: [.borderless],
                                      backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.level = .screenSaver
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.ignoresMouseEvents = false
            window.acceptsMouseMovedEvents = true
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

            let view = PickerView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.onFinish = { [weak self] point in
                self?.finish(point)
            }
            window.contentView = view
            window.setFrame(screen.frame, display: false)

            if screen.frame.contains(mouse) {
                view.mouse = NSPoint(x: mouse.x - screen.frame.minX, y: mouse.y - screen.frame.minY)
                windowUnderMouse = window
            }
            window.orderFrontRegardless()
            windows.append(window)
        }

        NSApp.activate(ignoringOtherApps: true)
        (windowUnderMouse ?? windows.first)?.makeKey()
        NSCursor.crosshair.set()

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53, let self else { return event } // Esc
            Task { @MainActor in self.finish(nil) }
            return nil
        }
    }

    private func finish(_ point: CGPoint?) {
        guard let completion else { return }
        self.completion = nil

        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil

        // Окна закрываем, но отпускаем только на следующем витке цикла:
        // finish может вызываться прямо из обработчика клика внутри этих окон.
        let closing = windows
        windows = []
        closing.forEach { $0.orderOut(nil) }
        DispatchQueue.main.async {
            withExtendedLifetime(closing) {}
        }

        NSCursor.arrow.set()
        completion(point)
    }
}

private final class PickerWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class PickerView: NSView {
    var onFinish: ((CGPoint?) -> Void)?
    var mouse: NSPoint? {
        didSet { needsDisplay = true }
    }

    private var trackingArea: NSTrackingArea?
    private let accent = NSColor(srgbRed: 0.16, green: 0.80, blue: 0.62, alpha: 1)

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .cursorUpdate, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.crosshair.set()
    }

    override func mouseEntered(with event: NSEvent) {
        mouse = convert(event.locationInWindow, from: nil)
        NSCursor.crosshair.set()
    }

    override func mouseMoved(with event: NSEvent) {
        mouse = convert(event.locationInWindow, from: nil)
        NSCursor.crosshair.set()
    }

    override func mouseExited(with event: NSEvent) {
        mouse = nil
    }

    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        onFinish?(globalPoint(for: local))
    }

    override func rightMouseUp(with event: NSEvent) {
        onFinish?(nil)
    }

    /// Локальная точка вида → координаты CoreGraphics.
    private func globalPoint(for local: NSPoint) -> CGPoint? {
        guard let window else { return nil }
        let onScreen = window.convertPoint(toScreen: convert(local, to: nil))
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? 0
        return CGPoint(x: onScreen.x.rounded(), y: (primaryHeight - onScreen.y).rounded())
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.32).setFill()
        bounds.fill()
        drawHint()

        guard let mouse else { return }

        let lines = NSBezierPath()
        lines.move(to: NSPoint(x: bounds.minX, y: mouse.y))
        lines.line(to: NSPoint(x: bounds.maxX, y: mouse.y))
        lines.move(to: NSPoint(x: mouse.x, y: bounds.minY))
        lines.line(to: NSPoint(x: mouse.x, y: bounds.maxY))
        lines.lineWidth = 1
        NSColor.white.withAlphaComponent(0.35).setStroke()
        lines.stroke()

        // «Окошко» вокруг курсора без затемнения, чтобы было видно, во что целишься.
        // Альфа не нулевая — иначе клик провалится сквозь окно.
        let ringRect = NSRect(x: mouse.x - 16, y: mouse.y - 16, width: 32, height: 32)
        let ring = NSBezierPath(ovalIn: ringRect)
        NSGraphicsContext.current?.compositingOperation = .copy
        NSColor.white.withAlphaComponent(0.02).setFill()
        ring.fill()
        NSGraphicsContext.current?.compositingOperation = .sourceOver
        ring.lineWidth = 2.5
        accent.setStroke()
        ring.stroke()

        let dot = NSBezierPath(ovalIn: NSRect(x: mouse.x - 2, y: mouse.y - 2, width: 4, height: 4))
        accent.setFill()
        dot.fill()

        if let point = globalPoint(for: mouse) {
            drawCoordinates(point, near: mouse)
        }
    }

    private func drawCoordinates(_ point: CGPoint, near mouse: NSPoint) {
        let label = "X \(Int(point.x))   Y \(Int(point.y))" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let size = label.size(withAttributes: attrs)
        var box = NSRect(x: mouse.x + 22, y: mouse.y - 22 - size.height - 10,
                         width: size.width + 20, height: size.height + 10)
        if box.maxX > bounds.maxX - 8 { box.origin.x = mouse.x - 22 - box.width }
        if box.minY < bounds.minY + 8 { box.origin.y = mouse.y + 22 }

        NSColor(srgbRed: 0.07, green: 0.50, blue: 0.47, alpha: 0.95).setFill()
        NSBezierPath(roundedRect: box, xRadius: 7, yRadius: 7).fill()
        label.draw(at: NSPoint(x: box.minX + 10, y: box.minY + 5), withAttributes: attrs)
    }

    private func drawHint() {
        let text = "Кликни в нужное место   ·   Esc — отмена" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = text.size(withAttributes: attrs)
        let box = NSRect(x: bounds.midX - size.width / 2 - 18, y: bounds.maxY - 100,
                         width: size.width + 36, height: size.height + 18)
        NSColor.black.withAlphaComponent(0.6).setFill()
        NSBezierPath(roundedRect: box, xRadius: box.height / 2, yRadius: box.height / 2).fill()
        text.draw(at: NSPoint(x: box.minX + 18, y: box.minY + 9), withAttributes: attrs)
    }
}
