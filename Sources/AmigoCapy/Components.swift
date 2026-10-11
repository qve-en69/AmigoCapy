import SwiftUI

enum Palette {
    static let accent = Color(red: 0.10, green: 0.68, blue: 0.58)
    static let start = [Color(red: 0.16, green: 0.80, blue: 0.62), Color(red: 0.15, green: 0.52, blue: 0.95)]
    static let stop = [Color(red: 1.00, green: 0.48, blue: 0.40), Color(red: 0.92, green: 0.26, blue: 0.50)]
    static let wait = [Color(red: 1.00, green: 0.74, blue: 0.30), Color(red: 0.98, green: 0.50, blue: 0.30)]
    static let red = [Color(red: 0.95, green: 0.40, blue: 0.42), Color(red: 0.85, green: 0.23, blue: 0.25)]
    static let blue = [Color(red: 0.36, green: 0.61, blue: 0.98), Color(red: 0.18, green: 0.44, blue: 0.88)]
    static let gold = [Color(red: 1.00, green: 0.89, blue: 0.48), Color(red: 0.96, green: 0.72, blue: 0.18),
                       Color(red: 0.89, green: 0.61, blue: 0.07)]
    static let redDot = Color(red: 0.90, green: 0.28, blue: 0.30)
    static let blueDot = Color(red: 0.23, green: 0.51, blue: 0.96)
    static let orange = Color(red: 0.94, green: 0.54, blue: 0.14)
}

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

/// Переключатель-«пилюля»: подсвечен градиентом, когда включён.
struct ToggleChip: View {
    let title: String
    var icon: String? = nil
    let on: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 10, weight: .bold))
                }
                Text(title)
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(on ? Color.white : Color.primary.opacity(0.8))
            .padding(.horizontal, 11)
            .frame(height: 26)
            .background(
                Capsule().fill(
                    on
                        ? AnyShapeStyle(LinearGradient(colors: Palette.start, startPoint: .leading, endPoint: .trailing))
                        : AnyShapeStyle(Color.primary.opacity(hovering ? 0.11 : 0.06))
                )
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct TabButton: View {
    let title: String
    let icon: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
            }
            .foregroundStyle(selected ? Color.primary : Color.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(selected ? Color(nsColor: .controlBackgroundColor) : Color.clear)
                    .shadow(color: .black.opacity(selected ? 0.12 : 0), radius: 2, y: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct HeaderIconButton: View {
    let systemName: String
    var active = false
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(active ? Palette.accent : Color.secondary)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.primary.opacity(0.06)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

struct Keycap: View {
    let text: String
    var highlighted = false
    var edge: Color? = nil

    var body: some View {
        Text(text)
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .padding(.horizontal, 10)
            .frame(minWidth: 40, minHeight: 40)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .shadow(color: (edge ?? .black).opacity(edge == nil ? 0.18 : 0.8), radius: 0, x: 0, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(highlighted ? Palette.accent : (edge ?? Color.primary.opacity(0.12)),
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
                .lineLimit(1)
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

/// Оранжевый блок-предупреждение со значком, заголовком и пояснением.
struct WarningBox: View {
    let icon: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.orange)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundStyle(Palette.orange)
                Text(text)
                    .font(.system(size: 12))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Palette.orange.opacity(0.13))
        )
    }
}

struct GradientButtonStyle: ButtonStyle {
    let colors: [Color]
    var height: CGFloat = 50

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: height)
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

/// Широкая мягкая кнопка (например, «Перезаход»).
struct WideSoftButtonStyle: ButtonStyle {
    var tint: Color = Palette.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13.5, weight: .semibold))
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(tint.opacity(configuration.isPressed ? 0.24 : 0.13))
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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

/// Затемнение поверх окна с карточкой-диалогом по центру; клик мимо карточки закрывает.
struct DialogBackdrop<Content: View>: View {
    let onDismiss: () -> Void
    let content: Content

    init(onDismiss: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.onDismiss = onDismiss
        self.content = content()
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)
            content
                .padding(18)
                .frame(maxWidth: 420)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(nsColor: .windowBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
                )
                .contentShape(Rectangle())
                .onTapGesture {}
                .shadow(color: .black.opacity(0.3), radius: 20, y: 6)
                .padding(20)
        }
    }
}
