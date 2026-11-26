import AppKit
import IOKit.hid

// DualSense settings sent straight to the controller as HID output reports, independent of the game.
// Only the parts the user chose to control have their "valid" flags set, so everything else
// (for example the game's rumble when vibration is not set here) is left alone.
// The state is resent regularly because games and macOS may reset it.

enum TriggerMode: Int, Codable, CaseIterable {
    case off, resistance, section, vibration
    var title: String {
        switch self {
        case .off: return "Desativado"
        case .resistance: return "Resistência contínua"
        case .section: return "Gatilho de arma (seção)"
        case .vibration: return "Vibração"
        }
    }
}

struct TriggerSetting: Codable, Equatable {
    var mode: TriggerMode = .off
    var start: Double = 0.15      // 0...1, where the effect begins
    var strength: Double = 0.6    // 0...1

    func effect() -> [UInt8] {
        var e = [UInt8](repeating: 0, count: 11)
        let s = UInt8(max(0, min(255, start * 255)))
        let f = UInt8(max(1, min(255, strength * 255)))
        switch mode {
        case .off: break
        case .resistance: e[0] = 0x01; e[1] = s; e[2] = f
        case .section: e[0] = 0x02; e[1] = s; e[2] = UInt8(min(255, Int(s) + 100)); e[3] = f
        case .vibration: e[0] = 0x06; e[1] = 40; e[2] = f; e[3] = s
        }
        return e
    }
}

enum MicLED: Int, Codable, CaseIterable { case game, off, on, pulse }
enum LightEffect: Int, Codable, CaseIterable { case game, fixed, rainbow, battery }
enum Brightness: Int, Codable, CaseIterable { case high, medium, low }

struct DSSettings: Codable, Equatable {
    var micLED: MicLED = .game
    var lightEffect: LightEffect = .game
    var red: Double = 0.4, green: Double = 1.0, blue: Double = 0.3
    var playerLEDs: Int = -1          // -1 = game, 0 = off, 1...4, 5 = all
    var brightness: Brightness = .high
    var rumbleStrong: Double = 0      // 0...1, test rumble while above 0
    var rumbleSoft: Double = 0
    var left = TriggerSetting()
    var right = TriggerSetting()
    var speakerVolume: Double = -1    // -1 = game, else 0...1
    var headphoneVolume: Double = -1

    static func load() -> DSSettings {
        guard let d = UserDefaults.standard.data(forKey: "dsSettings"),
              let s = try? JSONDecoder().decode(DSSettings.self, from: d) else {
            var s = DSSettings()
            let old = UserDefaults.standard.integer(forKey: "r2Strength")   // earlier R2 menu
            if old > 0 { s.right.mode = .resistance; s.right.strength = Double(old) / 255 }
            return s
        }
        return s
    }
    func save() { if let d = try? JSONEncoder().encode(self) { UserDefaults.standard.set(d, forKey: "dsSettings") } }
}

/// One connected DualSense: its HID device, identity, and what its input reports say.
final class Pad {
    let dev: IOHIDDevice
    let serial: String
    let bluetooth: Bool
    var state = InputSnapshot()
    var battery: Int?
    var charging = false
    var lastReport = Date.distantPast
    var lastSent: DSSettings?
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 128)
    init(dev: IOHIDDevice, serial: String, bluetooth: Bool) { self.dev = dev; self.serial = serial; self.bluetooth = bluetooth }
    deinit { buffer.deallocate() }
}

/// The list the selector shows.
final class PadsModel: ObservableObject {
    static let shared = PadsModel()
    struct Info: Identifiable, Equatable { let id: String; let number: Int; let bluetooth: Bool; let battery: Int? }
    @Published var list: [Info] = []
    @Published var selected: String?
}

final class DualSenseOutput {
    static weak var current: DualSenseOutput?
    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    private(set) var pads: [Pad] = []          // in connection order
    private var timer: Timer?
    private var seq: UInt8 = 0
    private var hue: Double = 0
    /// Settings of each controller, by serial; `template` is what a controller seen for the first time starts with.
    private var bySerial: [String: DSSettings] = {
        guard let d = UserDefaults.standard.data(forKey: "dsSettingsBySerial"),
              let m = try? JSONDecoder().decode([String: DSSettings].self, from: d) else { return [:] }
        return m
    }()
    private var template = DSSettings.load()
    /// Triggers of the game in front, if it has a profile (GameProfiles).
    var profile: GameProfile? { didSet { if profile != oldValue { apply() } } }
    /// While true nothing is sent (a firmware update owns the controller).
    var paused = false { didSet { if !paused { pads.forEach { $0.lastSent = nil }; apply() } } }

    var selectedSerial: String? { didSet { publish() } }
    var selectedPad: Pad? { pads.first { $0.serial == selectedSerial } ?? pads.first }

    /// The selected controller's settings (the template when none is connected).
    var settings: DSSettings {
        get { selectedPad.map { bySerial[$0.serial] ?? template } ?? template }
        set {
            if let p = selectedPad { bySerial[p.serial] = newValue } else { template = newValue }
            template = newValue; template.save()
            if let d = try? JSONEncoder().encode(bySerial) { UserDefaults.standard.set(d, forKey: "dsSettingsBySerial") }
            reschedule(); apply()
        }
    }

    init() {
        let match: [[String: Any]] = [0x0CE6, 0x0DF2].map { [kIOHIDVendorIDKey: 0x054C, kIOHIDProductIDKey: $0] }
        IOHIDManagerSetDeviceMatchingMultiple(manager, match as CFArray)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { ctx, _, _, dev in
            Unmanaged<DualSenseOutput>.fromOpaque(ctx!).takeUnretainedValue().added(dev)
        }, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { ctx, _, _, dev in
            let me = Unmanaged<DualSenseOutput>.fromOpaque(ctx!).takeUnretainedValue()
            me.pads.removeAll { CFEqual($0.dev, dev) }
            me.publish()
        }, ctx)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        DualSenseOutput.current = self
        reschedule()
    }

    private func added(_ dev: IOHIDDevice) {
        guard !pads.contains(where: { CFEqual($0.dev, dev) }) else { return }
        let transport = IOHIDDeviceGetProperty(dev, kIOHIDTransportKey as CFString) as? String ?? ""
        let serial = (IOHIDDeviceGetProperty(dev, kIOHIDSerialNumberKey as CFString) as? String)
            ?? "\((IOHIDDeviceGetProperty(dev, kIOHIDLocationIDKey as CFString) as? Int) ?? 0)"
        let pad = Pad(dev: dev, serial: serial, bluetooth: transport.localizedCaseInsensitiveContains("bluetooth"))
        pads.append(pad)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(dev, pad.buffer, 128, { ctx, _, sender, _, id, report, len in
            guard let ctx, let sender else { return }
            let me = Unmanaged<DualSenseOutput>.fromOpaque(ctx).takeUnretainedValue()
            let dev = Unmanaged<IOHIDDevice>.fromOpaque(sender).takeUnretainedValue()
            guard let pad = me.pads.first(where: { CFEqual($0.dev, dev) }) else { return }
            me.parse(pad, id: id, Array(UnsafeBufferPointer(start: report, count: len)))
        }, ctx)
        apply(); publish()
    }

    /// Input report 0x01 (USB) or 0x31 (Bluetooth): sticks, triggers, buttons, touchpad, battery.
    private func parse(_ pad: Pad, id: UInt32, _ r: [UInt8]) {
        let o: Int
        if id == 0x01 && r.count >= 54 && r.first == 0x01 { o = 1 }
        else if id == 0x01 && r.count >= 53 { o = 0 }
        else if id == 0x31 && r.count >= 55 { o = r.first == 0x31 ? 2 : 1 }
        else { return }
        var s = InputSnapshot()
        let axis: (Int) -> Double = { (Double(r[o + $0]) - 127.5) / 127.5 }
        s.left = CGPoint(x: axis(0), y: -axis(1)); s.right = CGPoint(x: axis(2), y: -axis(3))
        s.l2 = Double(r[o + 4]) / 255; s.r2 = Double(r[o + 5]) / 255
        let b0 = r[o + 7], b1 = r[o + 8], b2 = r[o + 9]
        let hat = Int(b0 & 0x0F)
        if [7, 0, 1].contains(hat) { s.pressed.insert("up") }
        if [1, 2, 3].contains(hat) { s.pressed.insert("right") }
        if [3, 4, 5].contains(hat) { s.pressed.insert("down") }
        if [5, 6, 7].contains(hat) { s.pressed.insert("left") }
        for (bit, n) in [(0x10, "square"), (0x20, "cross"), (0x40, "circle"), (0x80, "triangle")] where b0 & UInt8(bit) != 0 { s.pressed.insert(n) }
        for (bit, n) in [(0x01, "l1"), (0x02, "r1"), (0x10, "create"), (0x20, "options"), (0x40, "l3"), (0x80, "r3")] where b1 & UInt8(bit) != 0 { s.pressed.insert(n) }
        if b2 & 0x01 != 0 { s.pressed.insert("ps") }
        if b2 & 0x02 != 0 { s.pressed.insert("touchpad") }
        for t in 0..<2 {
            let i = o + 32 + t * 4
            guard r[i] & 0x80 == 0 else { continue }
            let x = Int(r[i + 1]) | Int(r[i + 2] & 0x0F) << 8, y = Int(r[i + 2] >> 4) | Int(r[i + 3]) << 4
            s.touches.append(CGPoint(x: Double(x) / 960 - 1, y: 1 - Double(y) / 540))
        }
        pad.state = s
        pad.lastReport = Date()
        let st = r[o + 52]
        let level = min(100, Int(st & 0x0F) * 10 + 5), charging = (st >> 4) == 1
        if level != pad.battery || charging != pad.charging {
            pad.battery = level; pad.charging = charging
            publish()
        }
    }

    /// Selector list, and the selected controller's battery in the status model.
    func publish() {
        let m = PadsModel.shared
        let list = pads.enumerated().map { PadsModel.Info(id: $1.serial, number: $0 + 1, bluetooth: $1.bluetooth, battery: $1.battery) }
        if m.list != list { m.list = list }
        let sel = selectedPad?.serial
        if m.selected != sel { m.selected = sel }
        if let p = selectedPad, let b = p.battery {
            StatusModel.shared.battery = b; StatusModel.shared.charging = p.charging
        }
    }

    /// Releases everything the app controls back to the game / defaults.
    func release() {
        if paused { return }
        var r = DSSettings()
        r.left.mode = .off; r.right.mode = .off
        r.micLED = .off; r.rumbleSoft = 0; r.rumbleStrong = 0
        for pad in pads { send(pad, payload(r, last: pad.lastSent, releasing: true)) }
    }

    /// A short rumble on one controller, to tell which one is selected.
    func identify(_ serial: String) {
        guard let pad = pads.first(where: { $0.serial == serial }) else { return }
        var p = [UInt8](repeating: 0, count: 47)
        p[0] = 0x03; p[2] = 200; p[3] = 200
        send(pad, p)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            var q = [UInt8](repeating: 0, count: 47); q[0] = 0x03
            self?.send(pad, q)
        }
    }

    private func reschedule() {
        timer?.invalidate()
        let fast = pads.contains { (bySerial[$0.serial] ?? template).lightEffect == .rainbow } || template.lightEffect == .rainbow
        timer = Timer.scheduledTimer(withTimeInterval: fast ? 0.05 : 1, repeats: true) { [weak self] _ in self?.apply() }
    }

    /// What one controller is actually sent: its settings, the game profile's triggers, the battery colour resolved.
    func effective(_ pad: Pad?) -> DSSettings {
        var s = pad.map { bySerial[$0.serial] ?? template } ?? template
        if let p = profile { s.left = p.left; s.right = p.right }
        if s.lightEffect == .battery {
            let c = batteryColor(pad?.battery ?? StatusModel.shared.battery)
            s.lightEffect = .fixed; s.red = c.0; s.green = c.1; s.blue = c.2
        }
        return s
    }
    var effective: DSSettings { effective(selectedPad) }

    func apply() {
        if paused { return }
        hue = (hue + 0.005).truncatingRemainder(dividingBy: 1)
        for pad in pads {
            let s = effective(pad)
            send(pad, payload(s, last: pad.lastSent, releasing: false))
            pad.lastSent = s
        }
    }

    private func payload(_ s: DSSettings, last: DSSettings?, releasing: Bool) -> [UInt8] {
        var p = [UInt8](repeating: 0, count: 47)
        let rumbleChanged = last.map { $0.rumbleSoft != s.rumbleSoft || $0.rumbleStrong != s.rumbleStrong } ?? true
        if s.rumbleSoft > 0 || s.rumbleStrong > 0 || rumbleChanged || releasing {
            p[0] |= 0x03
            p[2] = UInt8(s.rumbleSoft * 255); p[3] = UInt8(s.rumbleStrong * 255)
        }
        p[0] |= 0x04 | 0x08                                  // both triggers
        let r = s.right.effect(), l = s.left.effect()
        for i in 0..<11 { p[10 + i] = r[i]; p[21 + i] = l[i] }
        if s.headphoneVolume >= 0 { p[0] |= 0x10; p[4] = UInt8(s.headphoneVolume * 0x7F) }
        if s.speakerVolume >= 0 { p[0] |= 0x20; p[5] = UInt8(0x3D + s.speakerVolume * (0x64 - 0x3D)) }
        if s.micLED != .game || releasing {
            p[1] |= 0x01
            p[8] = s.micLED == .on ? 1 : s.micLED == .pulse ? 2 : 0
        }
        if s.lightEffect != .game {
            p[1] |= 0x04
            var rgb = (s.red, s.green, s.blue)
            if s.lightEffect == .rainbow {
                let c = NSColor(hue: hue, saturation: 1, brightness: 1, alpha: 1)
                rgb = (Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent))
            }
            p[44] = UInt8(rgb.0 * 255); p[45] = UInt8(rgb.1 * 255); p[46] = UInt8(rgb.2 * 255)
            p[38] |= 0x02; p[41] = 0x02                       // lightbar setup: light on
        }
        if s.playerLEDs >= 0 {
            p[1] |= 0x10
            p[43] = [0x00, 0x04, 0x0A, 0x15, 0x1B, 0x1F][min(5, s.playerLEDs)]
        }
        if s.playerLEDs >= 0 || s.lightEffect != .game {
            p[38] |= 0x01; p[42] = UInt8(s.brightness.rawValue)
        }
        return p
    }

    private func send(_ pad: Pad, _ p: [UInt8]) {
        if pad.bluetooth { sendBT(pad.dev, p) } else { sendUSB(pad.dev, p) }
    }

    private func sendUSB(_ d: IOHIDDevice, _ p: [UInt8]) {
        let r = [UInt8(0x02)] + p
        r.withUnsafeBufferPointer { _ = IOHIDDeviceSetReport(d, kIOHIDReportTypeOutput, 0x02, $0.baseAddress!, r.count) }
    }

    private func sendBT(_ d: IOHIDDevice, _ p: [UInt8]) {
        var r = [UInt8](repeating: 0, count: 78)
        r[0] = 0x31
        r[1] = seq << 4; seq = (seq + 1) & 0x0F
        r[2] = 0x10
        for i in 0..<p.count { r[3 + i] = p[i] }
        let crc = crc32([0xA2] + r[0..<74])
        for i in 0..<4 { r[74 + i] = UInt8((crc >> (8 * UInt32(i))) & 0xFF) }
        r.withUnsafeBufferPointer { _ = IOHIDDeviceSetReport(d, kIOHIDReportTypeOutput, 0x31, $0.baseAddress!, r.count) }
    }

    private func crc32<S: Sequence>(_ bytes: S) -> UInt32 where S.Element == UInt8 {
        var c: UInt32 = 0xFFFFFFFF
        for b in bytes {
            c ^= UInt32(b)
            for _ in 0..<8 { c = (c >> 1) ^ (0xEDB88320 & (0 &- (c & 1))) }
        }
        return ~c
    }
}
