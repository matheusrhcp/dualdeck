import SwiftUI
import AppKit

// Window backgrounds. All follow the chosen light-bar colour (`accent`).
enum BackdropStyle: String, CaseIterable {
    case aurora, glow, glass
    static let key = "backdrop"
    /// 0 = solid, 1 = fully see-through (cards, and the window in Glass)
    static let transparencyKey = "glassTransparency"
    var title: String {
        switch self { case .aurora: return L("Aurora"); case .glow: return L("Brilho suave"); case .glass: return L("Vidro") }
    }
}

private let navy = Color(red: 0.055, green: 0.094, blue: 0.165)     // DualDeck Deep Navy #0E182A
private let violet = Color(red: 0.54, green: 0.17, blue: 0.89)      // DualDeck Violet Glow #8A2BE2

struct AppBackdrop: View {
    @AppStorage(BackdropStyle.transparencyKey) private var transparency = 0.5
    let style: BackdropStyle
    let accent: Color
    /// light appearance once the frosted white dominates, so text stays readable
    static func isLight(_ t: Double) -> Bool { t > 0.6 }
    var body: some View {
        let t = transparency
        // 0…50 %: the style solid (Aurora starts from black); 50…100 %: frosted white glass
        ZStack {
            VisualEffect(light: true)
            Color.white.opacity(0.18 + 0.22 * t)
            Group {
                switch style {
                case .aurora: ZStack { navy; Aurora(accent: accent) }.saturation(0.35)   // no pink cast
                case .glow: Glow(accent: accent)
                case .glass: ZStack { VisualEffect(); accent.opacity(0.06) }           // the real dark glass
                }
            }
            .opacity(1 - max(0, t - 0.5) * 2)                   // every style fades to frosted white above 50 %
            if style == .aurora {
                Color.black.opacity(max(0, 1 - t * 2))          // Aurora only: solid black at 0 %
            }
        }
    }
}

/// Slowly drifting mesh gradient: navy, the accent and violet.
private struct Aurora: View {
    let accent: Color
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate / 9
            let w = { (a: Double, b: Double) -> Float in Float(0.5 + 0.18 * sin(t * a + b)) }
            MeshGradient(width: 3, height: 3, points: [
                [0, 0], [w(0.9, 0), 0], [1, 0],
                [0, w(0.7, 1)], [w(1.1, 2), w(0.8, 3)], [1, w(0.6, 4)],
                [0, 1], [w(0.5, 5), 1], [1, 1],
            ], colors: [
                navy, accent.opacity(0.55), navy,
                violet.opacity(0.45), navy, accent.opacity(0.35),
                navy, violet.opacity(0.35), navy,
            ])
            .overlay(Color.black.opacity(0.35))
        }
    }
}

/// Dark backdrop, a glow of the accent from the top centre (behind the controller) and a faint grid.
private struct Glow: View {
    let accent: Color
    var body: some View {
        ZStack {
            Color(red: 0.07, green: 0.07, blue: 0.09)
            RadialGradient(colors: [accent.opacity(0.42), accent.opacity(0.08), .clear],
                           center: UnitPoint(x: 0.5, y: 0.32), startRadius: 0, endRadius: 620)
            Canvas { ctx, size in
                var p = Path()
                stride(from: 0, through: size.width, by: 36).forEach { x in p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height)) }
                stride(from: 0, through: size.height, by: 36).forEach { y in p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y)) }
                ctx.stroke(p, with: .color(.white.opacity(0.035)), lineWidth: 1)
            }
        }
    }
}

/// The desktop behind the window, blurred.
private struct VisualEffect: NSViewRepresentable {
    var light = false
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        if light { v.appearance = NSAppearance(named: .aqua) }
        v.material = light ? .fullScreenUI : .underWindowBackground
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}

/// Frosted card background used everywhere.
struct CardBackground: View {
    @AppStorage(BackdropStyle.transparencyKey) private var transparency = 0.5
    var radius: CGFloat = 18
    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill((AppBackdrop.isLight(transparency) ? Color.white : Color(white: 0.12))
                    .opacity(AppBackdrop.isLight(transparency) ? 0.35 : 0.9 - transparency * 0.8)))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(.white.opacity(0.09)))
            .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
    }
}
