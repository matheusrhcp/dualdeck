import SwiftUI

// Firmware update through dsmactools (Homebrew: olliejudge/tap/dsmactools), which downloads the
// official firmware from Sony, flashes it over USB and verifies it.
// While it runs, DualSenseOutput is paused so no other output reports reach the controller.

@MainActor
final class FirmwareModel: ObservableObject {
    enum Phase: Equatable { case idle, busy(String), ready, updating, done(String), failed(String) }
    @Published var phase: Phase = .idle
    @Published var current: String?
    @Published var latest: String?
    @Published var updateAvailable = false
    @Published var progress: Double = 0
    @Published var log: [String] = []
    private var path: String?
    let output: DualSenseOutput

    init(_ o: DualSenseOutput) { output = o }

    /// The copy bundled in the app first (Contents/Resources/dsmactools), then a Homebrew install.
    nonisolated static let tool: String? = [Bundle.main.path(forResource: "dsmactools", ofType: nil),
                                            "/opt/homebrew/bin/dsmactools", "/usr/local/bin/dsmactools"]
        .compactMap { $0 }.first { FileManager.default.isExecutableFile(atPath: $0) }

    nonisolated static func run(_ args: [String], onLine: (@Sendable (String) -> Void)? = nil) async -> (Int32, [String]) {
        guard let tool else { return (-1, ["O dsmactools não está instalado (brew install olliejudge/tap/dsmactools)."]) }
        return await withCheckedContinuation { cont in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: tool)
            p.arguments = args
            p.standardInput = FileHandle.nullDevice      // non-interactive mode
            let pipe = Pipe()
            p.standardOutput = pipe; p.standardError = pipe
            final class Box: @unchecked Sendable { var lines: [String] = []; var partial = "" }
            let box = Box()
            pipe.fileHandleForReading.readabilityHandler = { h in
                let d = h.availableData
                guard !d.isEmpty, let s = String(data: d, encoding: .utf8) else { return }
                box.partial += s.replacingOccurrences(of: "\r", with: "\n")
                while let r = box.partial.range(of: "\n") {
                    let line = String(box.partial[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
                    box.partial = String(box.partial[r.upperBound...])
                    if !line.isEmpty { box.lines.append(line); onLine?(line) }
                }
            }
            p.terminationHandler = { p in
                pipe.fileHandleForReading.readabilityHandler = nil
                if !box.partial.isEmpty { box.lines.append(box.partial) }
                cont.resume(returning: (p.terminationStatus, box.lines))
            }
            do { try p.run() } catch { cont.resume(returning: (-1, ["\(error.localizedDescription)"])) }
        }
    }

    func check() async {
        phase = .busy(L("Lendo o controle…"))
        current = nil; latest = nil; updateAvailable = false; path = nil
        output.paused = true
        defer { output.paused = false }
        let (st, lines) = await Self.run(["--print-firmware-info", "--json"])
        guard st == 0, let json = lines.first(where: { $0.hasPrefix("{") }),
              let obj = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let p = obj["path"] as? String else {
            phase = .failed(lines.last ?? L("Controle não encontrado. Conecte-o com um cabo USB de dados."))
            return
        }
        path = p
        current = obj["version_hex"] as? String
        phase = .busy(L("Consultando a Sony…"))
        let (_, check) = await Self.run(["--check", "--path", p])
        for l in check {
            if let r = l.range(of: #"0x[0-9A-Fa-f]+"#, options: .regularExpression), l.localizedCaseInsensitiveContains("latest") {
                latest = String(l[r])
            }
        }
        if let c = current, let l = latest {
            updateAvailable = UInt32(c.dropFirst(2), radix: 16) ?? 0 < UInt32(l.dropFirst(2), radix: 16) ?? 0
        } else {
            updateAvailable = check.contains { $0.localizedCaseInsensitiveContains("update available") }
        }
        phase = latest == nil && !updateAvailable ? .failed(L("Não foi possível consultar a Sony: ") + (check.last ?? "")) : .ready
    }

    func install() async {
        guard let p = path else { return }
        phase = .updating; progress = 0; log = []
        output.paused = true
        let act = ProcessInfo.processInfo.beginActivity(options: [.idleSystemSleepDisabled, .userInitiated],
                                                        reason: L("Atualizando firmware do DualSense"))
        let (st, lines) = await Self.run(["--update-latest", "--yes", "--path", p]) { line in
            Task { @MainActor in self.handle(line) }
        }
        ProcessInfo.processInfo.endActivity(act)
        try? await Task.sleep(for: .seconds(8))   // controller reboots after flashing
        output.paused = false
        if st == 0 {
            phase = .done(lines.last ?? L("Atualização concluída."))
            updateAvailable = false
        } else {
            phase = .failed(lines.last ?? L("Falha na atualização."))
        }
    }

    private func handle(_ line: String) {
        log.append(line)
        if let r = line.range(of: #"(\d+)/(\d+) blocks"#, options: .regularExpression) {
            let parts = line[r].split(separator: " ")[0].split(separator: "/")
            if parts.count == 2, let a = Double(parts[0]), let b = Double(parts[1]), b > 0 { progress = a / b }
        }
    }
}

struct FirmwareView: View {
    @ObservedObject var m: FirmwareModel
    @State private var confirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Atualização de firmware").font(.title2.bold())
            Text("Conecte o DualSense com um cabo USB de dados. O firmware oficial é baixado da Sony pelo dsmactools.")
                .font(.callout).foregroundStyle(.secondary)
            if FirmwareModel.tool == nil {
                Text(L("O dsmactools não está instalado.")).foregroundStyle(.red)
            }
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow { Text("Versão atual").foregroundStyle(.secondary); Text(m.current ?? "—").monospaced() }
                GridRow { Text("Versão disponível").foregroundStyle(.secondary); Text(m.latest ?? "—").monospaced() }
            }
            switch m.phase {
            case .idle: EmptyView()
            case .busy(let s): HStack { ProgressView().controlSize(.small); Text(s) }
            case .ready:
                Text(m.updateAvailable ? "Há uma atualização disponível." : "O firmware já está atualizado.")
                    .foregroundStyle(m.updateAvailable ? .orange : .green)
            case .updating:
                ProgressView(value: m.progress) { Text("Gravando firmware… não desconecte o cabo nem feche o app.") }
                Text(m.log.last ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(2)
            case .done(let s): Text(s).foregroundStyle(.green)
            case .failed(let s): Text(s).foregroundStyle(.red).textSelection(.enabled)
            }
            Spacer()
            HStack {
                Button(L("Verificar")) { Task { await m.check() } }
                    .disabled(m.phase == .updating || FirmwareModel.tool == nil)
                Spacer()
                Button("Instalar firmware mais recente") { confirm = true }
                    .buttonStyle(.borderedProminent)
                    .disabled(!(m.phase == .ready && m.updateAvailable))
            }
        }
        .padding(20)
        .frame(width: 440, height: 330)
        .confirmationDialog("Instalar o firmware \(m.latest ?? "")?", isPresented: $confirm) {
            Button(L("Instalar")) { Task { await m.install() } }
        } message: {
            Text(L("Mantenha o cabo conectado e o Mac ligado até o fim. Interromper a gravação pode deixar o controle inutilizável."))
        }
        .task { if m.phase == .idle { await m.check() } }
    }
}

@MainActor final class FirmwareWindow: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    let model: FirmwareModel
    init(_ o: DualSenseOutput) { model = FirmwareModel(o) }

    func show() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: FirmwareView(m: model)))
            w.title = "Firmware do DualSense"
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        model.phase != .updating   // never close mid-flash
    }
}
