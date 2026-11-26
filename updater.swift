import AppKit

// Updates from the GitHub releases of matheusrhcp/dualdeck: the latest release's tag (v1.2.0) against
// CFBundleShortVersionString; its .dmg asset is downloaded, the app inside replaces this one, and the app restarts.
// Settings live in UserDefaults, so they survive the swap.

@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()
    static let repo = "matheusrhcp/dualdeck"

    enum Phase: Equatable { case idle, checking, upToDate, available(String), installing, failed(String) }
    @Published var phase: Phase = .idle
    private var dmgURL: URL?

    var current: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0" }

    private init() {
        // a quiet check at launch and once a day
        Task { await check(quiet: true) }
        Timer.scheduledTimer(withTimeInterval: 86_400, repeats: true) { _ in Task { @MainActor in await Updater.shared.check(quiet: true) } }
    }

    static func newer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }

    func check(quiet: Bool = false) async {
        if phase == .installing { return }
        if !quiet { phase = .checking }
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("DualDeck", forHTTPHeaderField: "User-Agent")
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200,
                  let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = obj["tag_name"] as? String else { throw URLError(.badServerResponse) }
            let version = tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            let assets = obj["assets"] as? [[String: Any]] ?? []
            dmgURL = assets.compactMap { $0["browser_download_url"] as? String }.first { $0.hasSuffix(".dmg") }.flatMap(URL.init)
            if Self.newer(version, than: current), dmgURL != nil { phase = .available(version) }
            else if !quiet || phase == .checking { phase = .upToDate }
        } catch {
            if !quiet { phase = .failed(L("Não foi possível verificar: ") + error.localizedDescription) }
        }
    }

    func install() async {
        guard let url = dmgURL else { return }
        phase = .installing
        do {
            let (tmp, _) = try await URLSession.shared.download(from: url)
            let dmg = FileManager.default.temporaryDirectory.appendingPathComponent("DualDeck-update.dmg")
            try? FileManager.default.removeItem(at: dmg)
            try FileManager.default.moveItem(at: tmp, to: dmg)
            let mount = FileManager.default.temporaryDirectory.appendingPathComponent("DualDeck-mount-\(UUID().uuidString)")
            try run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-mountpoint", mount.path, dmg.path])
            defer { _ = try? run("/usr/bin/hdiutil", ["detach", "-quiet", mount.path]) }
            guard let newApp = try FileManager.default.contentsOfDirectory(at: mount, includingPropertiesForKeys: nil)
                .first(where: { $0.pathExtension == "app" }) else { throw URLError(.cannotOpenFile) }
            // copy next to the current app, then swap: the old one goes to the Trash, never deleted
            let here = URL(fileURLWithPath: Bundle.main.bundlePath)
            let staged = here.deletingLastPathComponent().appendingPathComponent(".DualDeck-new.app")
            try? FileManager.default.removeItem(at: staged)
            try run("/usr/bin/ditto", [newApp.path, staged.path])
            _ = try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", staged.path])
            try FileManager.default.trashItem(at: here, resultingItemURL: nil)
            try FileManager.default.moveItem(at: staged, to: here)
            // restart from the new copy once this one has quit
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/sh")
            p.arguments = ["-c", "sleep 1; /usr/bin/open \"\(here.path)\""]
            try p.run()
            NSApp.terminate(nil)
        } catch {
            phase = .failed(L("Falha ao instalar: ") + error.localizedDescription)
        }
    }

    @discardableResult private func run(_ tool: String, _ args: [String]) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
        try p.run(); p.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if p.terminationStatus != 0 { throw NSError(domain: tool, code: Int(p.terminationStatus), userInfo: [NSLocalizedDescriptionKey: out]) }
        return out
    }
}
