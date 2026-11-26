import AppKit
import IOBluetooth
import GameController

// MARK: - Per-game profiles

/// Triggers to use while a given app is in front (for example a game packed by nxnative).
struct GameProfile: Codable, Identifiable, Equatable {
    var id: String { bundleID }
    var bundleID: String
    var name: String
    var left = TriggerSetting()
    var right = TriggerSetting()
}

final class GameProfiles: ObservableObject {
    static let shared = GameProfiles()
    @Published var list: [GameProfile] { didSet { save(); apply() } }
    @Published private(set) var frontApp: String?
    weak var output: DualSenseOutput?

    private init() {
        if let d = UserDefaults.standard.data(forKey: "gameProfiles"),
           let l = try? JSONDecoder().decode([GameProfile].self, from: d) { list = l } else { list = [] }
        frontApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                                          object: nil, queue: .main) { [weak self] n in
            let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard let self, let id = app?.bundleIdentifier, id != Bundle.main.bundleIdentifier else { return }
            self.frontApp = id
            self.apply()
        }
    }

    var active: GameProfile? { list.first { $0.bundleID == frontApp } }

    func apply() { output?.profile = active }

    /// Asks for an app (default folder: the nxnative builds) and adds a profile for it.
    func addFromPanel() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.applicationBundle]
        p.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("projects/nxnative-work")
        p.prompt = "Adicionar"
        NSApp.activate(ignoringOtherApps: true)
        guard p.runModal() == .OK, let url = p.url, let b = Bundle(url: url), let id = b.bundleIdentifier else { return }
        guard !list.contains(where: { $0.bundleID == id }) else { return }
        let name = (b.object(forInfoDictionaryKey: "CFBundleDisplayName") ?? b.object(forInfoDictionaryKey: "CFBundleName")) as? String
        var g = GameProfile(bundleID: id, name: name ?? url.deletingPathExtension().lastPathComponent)
        g.right.mode = .resistance; g.right.strength = 1
        list.append(g)
    }

    private func save() { if let d = try? JSONEncoder().encode(list) { UserDefaults.standard.set(d, forKey: "gameProfiles") } }
}

// MARK: - Battery colour

/// Green at full charge to red at empty, through yellow.
func batteryColor(_ level: Int?) -> (Double, Double, Double) {
    let f = Double(level ?? 100) / 100
    return f > 0.5 ? (2 * (1 - f), 1, 0.15) : (1, 2 * f, 0.1)
}

// MARK: - Power off

final class PowerManager: ObservableObject {
    static let shared = PowerManager()
    /// Minutes without input before the controller is turned off; 0 = never.
    @Published var idleMinutes: Int = UserDefaults.standard.integer(forKey: "idleMinutes") {
        didSet { UserDefaults.standard.set(idleMinutes, forKey: "idleMinutes") }
    }
    private var lastInput: [String: Date] = [:]
    private var lastKey: [String: String] = [:]
    private var timer: Timer?

    private init() {
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.tick() }
    }

    private func tick() {
        for pad in DualSenseOutput.current?.pads ?? [] {
            let s = pad.state
            let key = "\(s.pressed.sorted())\(Int(s.left.x * 10))\(Int(s.left.y * 10))\(Int(s.right.x * 10))\(Int(s.right.y * 10))\(Int(s.l2 * 10))\(Int(s.r2 * 10))\(s.touches.count)"
            if key != lastKey[pad.serial] || lastInput[pad.serial] == nil { lastKey[pad.serial] = key; lastInput[pad.serial] = Date() }
            if idleMinutes > 0, pad.bluetooth, let t = lastInput[pad.serial], Date().timeIntervalSince(t) > Double(idleMinutes * 60) {
                lastInput[pad.serial] = nil
                turnOff(serial: pad.serial)
            }
        }
    }

    /// Drops the Bluetooth link; a DualSense turns itself off when it loses its host.
    /// Returns false when no DualSense is connected over Bluetooth (a USB cable keeps it on).
    /// `serial` = the controller's HID serial, which over Bluetooth is its address; nil = the selected controller.
    @discardableResult func turnOff(serial: String? = nil) -> Bool {
        let want = (serial ?? DualSenseOutput.current?.selectedPad?.serial)?.lowercased().filter(\.isHexDigit)
        let devices = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        var done = false
        for d in devices where d.isConnected() && (d.name ?? "").localizedCaseInsensitiveContains("dualsense")
            && (want == nil || (d.addressString ?? "").lowercased().filter(\.isHexDigit) == want) {
            d.closeConnection()
            done = true
        }
        return done
    }
}

// MARK: - Open at login

/// The LaunchAgent `local.dualsense.battery` starts the app at login; this enables or disables it
/// (launchctl keeps the setting, the plist is left in place).
enum LoginItem {
    static let label = "local.dualsense.battery"

    static var plist: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var enabled: Bool {
        guard FileManager.default.fileExists(atPath: plist.path) else { return false }
        let out = run(["print-disabled", "gui/\(getuid())"])
        return !out.contains("\"\(label)\" => disabled") && !out.contains("\"\(label)\" => true")
    }

    static func set(_ on: Bool) {
        if on && !FileManager.default.fileExists(atPath: plist.path) {   // installed from the DMG: create the agent
            let agent: [String: Any] = ["Label": label, "RunAtLoad": true,
                                        "ProgramArguments": ["/usr/bin/open", "-W", Bundle.main.bundlePath]]
            try? FileManager.default.createDirectory(at: plist.deletingLastPathComponent(), withIntermediateDirectories: true)
            (agent as NSDictionary).write(to: plist, atomically: true)
            _ = run(["bootstrap", "gui/\(getuid())", plist.path])
        }
        _ = run([on ? "enable" : "disable", "gui/\(getuid())/\(label)"])
    }

    private static func run(_ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = args
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
        try? p.run(); p.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
}
