import SwiftUI
import GameController


func isDualSense(_ c: GCController) -> Bool {
    let n = (c.vendorName ?? "") + " " + c.productCategory
    return n.localizedCaseInsensitiveContains("dualsense")
}

// Live input test: what is pressed on the first DualSense, drawn over the controller image (1200x809 coordinates).
struct InputSnapshot {
    var pressed: Set<String> = []
    var left = CGPoint.zero, right = CGPoint.zero      // sticks, -1...1
    var l2: Double = 0, r2: Double = 0
    var touches: [CGPoint] = []                        // touchpad, -1...1

    static func read() -> InputSnapshot? {
        if let p = DualSenseOutput.current?.selectedPad, Date().timeIntervalSince(p.lastReport) < 1 { return p.state }
        guard let c = GCController.controllers().first(where: isDualSense), let g = c.extendedGamepad else { return nil }
        var s = InputSnapshot()
        let buttons: [(String, GCControllerButtonInput?)] = [
            ("cross", g.buttonA), ("circle", g.buttonB), ("square", g.buttonX), ("triangle", g.buttonY),
            ("l1", g.leftShoulder), ("r1", g.rightShoulder), ("l3", g.leftThumbstickButton), ("r3", g.rightThumbstickButton),
            ("options", g.buttonMenu), ("create", g.buttonOptions), ("ps", g.buttonHome),
            ("up", g.dpad.up), ("down", g.dpad.down), ("left", g.dpad.left), ("right", g.dpad.right),
        ]
        for (n, b) in buttons where b?.isPressed == true { s.pressed.insert(n) }
        s.left = CGPoint(x: Double(g.leftThumbstick.xAxis.value), y: Double(g.leftThumbstick.yAxis.value))
        s.right = CGPoint(x: Double(g.rightThumbstick.xAxis.value), y: Double(g.rightThumbstick.yAxis.value))
        s.l2 = Double(g.leftTrigger.value); s.r2 = Double(g.rightTrigger.value)
        if let d = g as? GCDualSenseGamepad {
            if d.touchpadButton.isPressed { s.pressed.insert("touchpad") }
            for t in [d.touchpadPrimary, d.touchpadSecondary] where t.xAxis.value != 0 || t.yAxis.value != 0 {
                s.touches.append(CGPoint(x: Double(t.xAxis.value), y: Double(t.yAxis.value)))
            }
        }
        return s
    }
}

/// Per-button images from the mockup (grey light and shade, alpha = the button), placed by Resources/buttons.tsv.
enum ButtonArt {
    static let boxes: [String: CGRect] = {
        guard let url = Bundle.main.url(forResource: "buttons", withExtension: "tsv"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        var d: [String: CGRect] = [:]
        for line in text.split(separator: "\n") {
            let f = line.split(separator: "\t")
            guard f.count == 5, let a = Double(f[1]), let b = Double(f[2]), let c = Double(f[3]), let e = Double(f[4]) else { continue }
            d[String(f[0])] = CGRect(x: a, y: b, width: c - a, height: e - b)
        }
        return d
    }()
    static var images: [String: NSImage] = [:]
    static func image(_ n: String) -> NSImage? {
        if let i = images[n] { return i }
        let i = Bundle.main.image(forResource: "btn_" + n); images[n] = i; return i
    }
}

struct TesterOverlay: View {
    let k: CGFloat
    let accent: Color

    /// Everything pressed, for checking positions (DS_TESTER_PREVIEW=1).
    static let preview: InputSnapshot? = ProcessInfo.processInfo.environment["DS_TESTER_PREVIEW"] == nil ? nil : {
        var s = InputSnapshot()
        s.pressed = ["triangle", "cross", "up", "right", "options", "ps", "l1", "r3", "touchpad"]
        s.left = CGPoint(x: -0.7, y: 0.5); s.l2 = 0.4; s.r2 = 1; s.touches = [CGPoint(x: -0.5, y: 0.3)]
        return s
    }()

    private static let plain = ["triangle", "circle", "cross", "square", "up", "down", "left", "right",
                                "options", "create", "ps", "l1", "r1", "touchpad"]

    var body: some View {
        TimelineView(.animation) { _ in
            let s = InputSnapshot.read() ?? Self.preview ?? InputSnapshot()
            ZStack(alignment: .topLeading) {
                ForEach(Self.plain, id: \.self) { n in
                    if s.pressed.contains(n) { part(n, color: accent) }
                }
                stick("l3", s.left, pressed: s.pressed.contains("l3"))
                stick("r3", s.right, pressed: s.pressed.contains("r3"))
                ForEach(Array(s.touches.enumerated()), id: \.offset) { _, t in
                    Circle().fill(.white).shadow(color: accent, radius: 6 * k)
                        .frame(width: 22 * k, height: 22 * k)
                        .position(x: (600 + t.x * 230) * k, y: (152 - t.y * 110) * k)
                }
                gauge(s.l2, label: "L2").position(x: 470 * k, y: 760 * k)
                gauge(s.r2, label: "R2").position(x: 730 * k, y: 760 * k)
            }
        }
        .allowsHitTesting(false)
    }

    /// The button's own image, recoloured, at its place; `dx`/`dy` move it (sticks).
    @ViewBuilder private func part(_ n: String, color: Color, dx: CGFloat = 0, dy: CGFloat = 0) -> some View {
        if let r = ButtonArt.boxes[n], let img = ButtonArt.image(n) {
            Image(nsImage: img).resizable().interpolation(.high)
                .colorMultiply(color)
                .frame(width: r.width * k, height: r.height * k)
                .position(x: (r.midX + dx) * k, y: (r.midY + dy) * k)
        }
    }

    @ViewBuilder private func stick(_ n: String, _ v: CGPoint, pressed: Bool) -> some View {
        let moved = abs(v.x) > 0.08 || abs(v.y) > 0.08
        if moved || pressed {
            part(n, color: pressed ? accent : accent.opacity(0.9).mix(with: .white, by: 0.35), dx: v.x * 30, dy: -v.y * 30)
        }
    }

    private func gauge(_ v: Double, label: String) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.12))
                Capsule().fill(accent).frame(width: 60 * v)
            }.frame(width: 60, height: 5)
        }
    }
}
