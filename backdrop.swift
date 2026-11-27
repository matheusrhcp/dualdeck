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
    var body: some View {
        // the desktop behind, always blurred (never readable), the style, and black on top at low transparency
        ZStack {
            VisualEffect()
            Group {
                switch style {
                case .aurora: ZStack { navy; Aurora(accent: accent) }
                case .glow: Glow(accent: accent)
                case .glass: ZStack { Color.black.opacity(0.55); accent.opacity(0.08) }
                }
            }
            // 0…50 %: from solid black (like the logo) to the full style; 50…100 %: the blurred desktop shows through
            .opacity(1 - max(0, transparency - 0.5) * (style == .glass ? 1.8 : 1.5))
            Color.black.opacity(max(0, 1 - transparency * 2))
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
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .underWindowBackground
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
                .fill(Color(white: 0.12).opacity((1 - transparency) * 0.9)))   // 0 = solid card, 1 = clear glass
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(.white.opacity(0.09)))
            .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
    }
}
