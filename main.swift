import AppKit
import GameController
import UserNotifications

// Menu bar battery level for a DualSense; visible only while one is connected.
let warnLevels: [Float] = [0.20, 0.10]


@MainActor final class App: NSObject, NSApplicationDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let info = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    var warned = Set<Float>()
    let output = DualSenseOutput()
    lazy var settingsWindow = SettingsWindow(output)
    lazy var popover = StatusPopover(model: settingsWindow.model) { [weak self] in self?.settingsWindow.show() }

    func applicationDidFinishLaunching(_ n: Notification) {
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        item.button?.image = NSImage(systemSymbolName: "gamecontroller.fill", accessibilityDescription: "DualSense")
        item.button?.imagePosition = .imageLeading
        item.isVisible = true
        GCController.shouldMonitorBackgroundEvents = true
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(refresh), name: .GCControllerDidConnect, object: nil)
        nc.addObserver(self, selector: #selector(refresh), name: .GCControllerDidDisconnect, object: nil)
        nc.addObserver(self, selector: #selector(chargeComplete), name: .dualDeckChargeComplete, object: nil)
        GCController.startWirelessControllerDiscovery(completionHandler: nil)
        Timer.scheduledTimer(timeInterval: 15, target: self, selector: #selector(refresh), userInfo: nil, repeats: true)
        refresh()
        GameProfiles.shared.output = output
        GameProfiles.shared.apply()
        _ = PowerManager.shared
        _ = Updater.shared
        // for screenshots: open --args --open-settings / --open-popover
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--open-settings") { DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.settingsWindow.show() } }
        if args.contains("--open-popover") { DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.togglePopover() } }
    }

    func applicationWillTerminate(_ n: Notification) { output.release() }

    @objc func openSettings() { settingsWindow.show() }
    @objc func togglePopover() { if let b = item.button { popover.toggle(from: b) } }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        settingsWindow.firmware.phase == .updating ? .terminateCancel : .terminateNow   // never quit mid-flash
    }

    @objc func refresh() {
        let st = StatusModel.shared
        guard let c = GCController.controllers().first(where: isDualSense) else {
            st.connected = false; st.battery = nil
            item.button?.title = ""
            info.title = L("Nenhum DualSense conectado")
            return
        }
        item.isVisible = true
        st.connected = true
        st.name = c.vendorName ?? "DualSense"
        output.publish()
        if let pad = output.selectedPad, let b = output.level(pad) {   // the same reading as the window and the popover
            st.battery = b; st.charging = pad.charging
            item.button?.title = pad.charging ? " \(b)% ⚡︎" : " \(b)%"
            info.title = "DualSense: \(b)%"
            if !pad.charging {
                for w in warnLevels where Float(b) / 100 <= w && !warned.contains(w) { warned.insert(w); notify(b) }
            } else { warned.removeAll() }
            return
        }
        st.battery = c.battery.map { Int(($0.batteryLevel * 100).rounded()) }
        st.charging = c.battery?.batteryState == .charging
        guard let b = c.battery else {
            item.button?.title = " --"
            info.title = L("DualSense: bateria indisponível")
            log("no battery object")
            return
        }
        let pct = Int((b.batteryLevel * 100).rounded())
        let state: String
        switch b.batteryState {
        case .charging: state = L("carregando")
        case .full: state = L("carga completa")
        case .discharging: state = L("em uso")
        default: state = L("estado desconhecido")
        }
        item.button?.title = b.batteryState == .charging ? " \(pct)% ⚡︎" : " \(pct)%"
        info.title = "DualSense: \(pct)%, \(state)"
        log("level \(b.batteryLevel) state \(b.batteryState.rawValue)")
        if b.batteryState == .discharging {
            for w in warnLevels where b.batteryLevel <= w && !warned.contains(w) {
                warned.insert(w)
                notify(pct)
            }
        } else if b.batteryState == .charging || b.batteryState == .full {
            warned.removeAll()
        }
    }

    func notify(_ pct: Int) {
        let c = UNMutableNotificationContent()
        c.title = L("DualSense com bateria baixa")
        c.body = String(format: L("Restam %d%%. Conecte o carregador."), pct)
        c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "low-\(pct)", content: c, trigger: nil))
    }

    @objc func chargeComplete() {
        let c = UNMutableNotificationContent()
        c.title = L("DualSense carregado")
        c.body = L("A bateria está cheia: pode desconectar do carregador.")
        c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "full-\(Date().timeIntervalSince1970)", content: c, trigger: nil))
    }

    func log(_ s: String) { FileHandle.standardError.write(Data((s + "\n").utf8)) }
}

extension App: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ c: UNUserNotificationCenter, willPresent n: UNNotification,
                                withCompletionHandler h: @escaping (UNNotificationPresentationOptions) -> Void) { h([.banner, .sound]) }
}

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { App() }
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
