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
enum LightEffect: Int, Codable, CaseIterable { case game, fixed, rainbow }
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

final class DualSenseOutput {
    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    private var devices = Set<IOHIDDevice>()
    private var timer: Timer?
    private var seq: UInt8 = 0
    private var hue: Double = 0
    private var lastSent: DSSettings?
    /// While true nothing is sent (a firmware update owns the controller).
    var paused = false { didSet { if !paused { lastSent = nil; apply() } } }
    var settings = DSSettings.load() { didSet { settings.save(); reschedule(); apply() } }

    init() {
        let match: [[String: Any]] = [0x0CE6, 0x0DF2].map { [kIOHIDVendorIDKey: 0x054C, kIOHIDProductIDKey: $0] }
        IOHIDManagerSetDeviceMatchingMultiple(manager, match as CFArray)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { ctx, _, _, dev in
            let me = Unmanaged<DualSenseOutput>.fromOpaque(ctx!).takeUnretainedValue()
            me.devices.insert(dev); me.lastSent = nil; me.apply()
        }, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { ctx, _, _, dev in
            Unmanaged<DualSenseOutput>.fromOpaque(ctx!).takeUnretainedValue().devices.remove(dev)
        }, ctx)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        reschedule()
    }

    /// Releases everything the app controls back to the game / defaults.
    func release() {
        if paused { return }
        var r = DSSettings()
        r.left.mode = .off; r.right.mode = .off
        r.micLED = .off; r.rumbleSoft = 0; r.rumbleStrong = 0
        sendAll(r, releasing: true)
    }

    private func reschedule() {
        timer?.invalidate()
        let fast = settings.lightEffect == .rainbow
        timer = Timer.scheduledTimer(withTimeInterval: fast ? 0.05 : 1, repeats: true) { [weak self] _ in self?.apply() }
    }

    private func apply() {
        if paused { return }
        if settings.lightEffect == .rainbow { hue = (hue + 0.005).truncatingRemainder(dividingBy: 1) }
        sendAll(settings, releasing: false)
        lastSent = settings
    }

    private func payload(_ s: DSSettings, releasing: Bool) -> [UInt8] {
        var p = [UInt8](repeating: 0, count: 47)
        let rumbleChanged = lastSent.map { $0.rumbleSoft != s.rumbleSoft || $0.rumbleStrong != s.rumbleStrong } ?? true
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

    private func sendAll(_ s: DSSettings, releasing: Bool) {
        let p = payload(s, releasing: releasing)
        for d in devices {
            let transport = IOHIDDeviceGetProperty(d, kIOHIDTransportKey as CFString) as? String ?? ""
            if transport.localizedCaseInsensitiveContains("bluetooth") { sendBT(d, p) } else { sendUSB(d, p) }
        }
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
