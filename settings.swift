import SwiftUI

// Main window: a dashboard of cards around a live drawing of the controller.

final class SettingsModel: ObservableObject {
    let output: DualSenseOutput
    private var loading = false
    @Published var s: DSSettings { didSet { if !loading { output.settings = s } } }
    init(_ o: DualSenseOutput) { output = o; s = o.settings }

    /// Selects a controller and shows its settings.
    func select(_ serial: String) {
        output.selectedSerial = serial
        loading = true; s = output.settings; loading = false
        output.identify(serial)
    }
}

/// "Controle 1 · 65%" picker, shown when more than one DualSense is connected.
struct PadPicker: View {
    @AppStorage(AppLanguage.key) private var language = AppLanguage.automatic.rawValue
    @ObservedObject var pads = PadsModel.shared
    let m: SettingsModel
    var body: some View {
        if pads.list.count > 1 {
            Picker("", selection: Binding(get: { pads.selected ?? pads.list.first?.id ?? "" }, set: { m.select($0) })) {
                ForEach(pads.list) { p in
                    Text(L("Controle") + " \(p.number)" + (p.battery.map { " · \($0)%" } ?? "") + (p.bluetooth ? "" : " · USB")).tag(p.id)
                }
            }
            .labelsHidden().pickerStyle(.segmented).fixedSize()
            .help(L("Escolha o controle a configurar; ele vibra para você saber qual é."))
        }
    }
}

/// Connection and battery, fed by App.refresh().
final class StatusModel: ObservableObject {
    static let shared = StatusModel()
    @Published var connected = false
    @Published var name = "DualSense"
    @Published var battery: Int?
    @Published var charging = false
}

// MARK: - Building blocks

private let defaultAccent = Color(red: 0, green: 0.4, blue: 1.0)   // DualDeck Electric Blue #0066FF

private struct ThemeKey: EnvironmentKey { static let defaultValue = defaultAccent }
extension EnvironmentValues {
    var theme: Color { get { self[ThemeKey.self] } set { self[ThemeKey.self] = newValue } }
}

/// Controller image (1200x809) and masks of its parts, exported from Piero Unisono's DualSense mockup PSD.
enum PhotoMasks {
    static let photo: NSImage? = Bundle.main.image(forResource: "controller")
    static let lightbar: NSImage? = Bundle.main.image(forResource: "mask_led")
    /// The bumpers' own light and shade (grey, alpha = bumper), to be multiplied by a colour.
    static let leftTrigger: NSImage? = Bundle.main.image(forResource: "shade_l2")
    static let rightTrigger: NSImage? = Bundle.main.image(forResource: "shade_r2")
}

struct Card<Content: View>: View {
    @AppStorage(AppLanguage.key) private var language = AppLanguage.automatic.rawValue
    @Environment(\.theme) private var accent
    let kicker: String
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(kicker.uppercased()).font(.system(size: 10.5, weight: .bold)).tracking(1.4).foregroundStyle(accent)
                Text(title).font(.system(size: 13, weight: .semibold))
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.background.opacity(0.55)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.primary.opacity(0.07)))
    }
}

struct ValueSlider: View {
    @AppStorage(AppLanguage.key) private var language = AppLanguage.automatic.rawValue
    @Environment(\.theme) private var accent
    let icon: String, label: String
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: icon).foregroundStyle(accent).frame(width: 16)
                Text(label).font(.callout)
                Spacer()
                Text("\(Int(((value - range.lowerBound) / (range.upperBound - range.lowerBound) * 100).rounded()))%")
                    .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range).tint(accent)
        }
    }
}

struct Row<C: View>: View {
    @AppStorage(AppLanguage.key) private var language = AppLanguage.automatic.rawValue
    @Environment(\.theme) private var accent
    let icon: String, label: String
    @ViewBuilder var control: C
    var body: some View {
        HStack {
            Image(systemName: icon).foregroundStyle(accent).frame(width: 16)
            Text(label).font(.callout).lineLimit(1).fixedSize()
            Spacer(minLength: 6)
            control
        }
    }
}

// MARK: - Controller drawing

/// Image of a DualSense (Resources/controller.png, 1200x809) with the parts the app controls drawn on top.
struct ControllerArt: View {
    @AppStorage(AppLanguage.key) private var language = AppLanguage.automatic.rawValue
    @Environment(\.theme) private var accent
    let s: DSSettings
    var testing = false
    @State private var phase = 0.0
    private let timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    private var lightColor: Color {
        switch s.lightEffect {
        case .game: return Color(red: 0.2, green: 0.35, blue: 1)
        case .fixed: return Color(red: s.red, green: s.green, blue: s.blue)
        case .rainbow: return Color(hue: phase, saturation: 1, brightness: 1)
        case .battery: let c = batteryColor(StatusModel.shared.battery); return Color(red: c.0, green: c.1, blue: c.2)
        }
    }
    private var glow: Double { [1.0, 0.65, 0.35][s.brightness.rawValue] }

    var body: some View {
        GeometryReader { g in
            let k = g.size.width / 1200   // image pixels to points
            ZStack(alignment: .topLeading) {
                if let img = PhotoMasks.photo {
                    Image(nsImage: img).resizable().interpolation(.high)
                        .frame(width: g.size.width, height: 809 * k)
                        .shadow(color: .black.opacity(0.35), radius: 18, y: 12)
                }
                // triggers and lightbar: the photo's own pixels, recoloured
                if s.left.mode != .off { tinted(PhotoMasks.leftTrigger, k: k) }
                if s.right.mode != .off { tinted(PhotoMasks.rightTrigger, k: k) }
                masked(PhotoMasks.lightbar, lightColor, glow: glow, k: k)
                // player LEDs under the touchpad
                HStack(spacing: 9 * k) {
                    ForEach(0..<5) { i in
                        Capsule().fill(playerOn(i) ? Color.white : .clear)
                            .shadow(color: playerOn(i) ? .white : .clear, radius: 4 * k)
                            .frame(width: 14 * k, height: 5 * k)
                    }
                }.position(x: 597 * k, y: 289 * k)
                if testing { TesterOverlay(k: k, accent: accent) }
                // mute LED
                Capsule().fill(micColor).frame(width: 52 * k, height: 11 * k)
                    .shadow(color: micColor == .clear ? .clear : .orange, radius: 6 * k)
                    .position(x: 601 * k, y: 469 * k)
            }
        }
        .aspectRatio(1200 / 809, contentMode: .fit)
        .frame(minWidth: 320, maxWidth: 820)
        .padding(.vertical, 14)
        .onReceive(timer) { _ in phase = (phase + 0.005).truncatingRemainder(dividingBy: 1) }
    }

    /// An altered trigger shows white; light grey when the chosen colour is itself white.
    private var triggerColor: Color {
        let white = s.lightEffect == .fixed && min(s.red, s.green, s.blue) > 0.85
        return white ? Color(white: 0.7) : .white
    }

    /// Recolours a part: its grey shading multiplied by the theme colour, so the relief stays.
    private func tinted(_ shade: NSImage?, k: CGFloat) -> some View {
        Group {
            if let shade {
                Image(nsImage: shade).resizable().interpolation(.high)
                    .frame(width: 1200 * k, height: 809 * k)
                    .colorMultiply(triggerColor)
            }
        }
    }

    private func masked(_ mask: NSImage?, _ color: Color, glow: Double, k: CGFloat) -> some View {
        Group {
            if let mask {
                Rectangle().fill(color)
                    .frame(width: 1200 * k, height: 809 * k)
                    .mask(Image(nsImage: mask).resizable().interpolation(.high))
                    .shadow(color: color.opacity(glow * 0.7), radius: 5 * k)
                    .shadow(color: color.opacity(glow * 0.35), radius: 14 * k)
            }
        }
    }

    private var micColor: Color {
        switch s.micLED {
        case .on: return .orange
        case .pulse: return .orange.opacity(abs(sin(phase * 60)))
        default: return .clear
        }
    }
    private func playerOn(_ i: Int) -> Bool {
        let masks = [0x00, 0x04, 0x0A, 0x15, 0x1B, 0x1F]
        guard s.playerLEDs >= 0 else { return i == 2 }
        return masks[min(5, s.playerLEDs)] & (1 << i) != 0
    }
}

// MARK: - Cards

struct TriggerCard: View {
    @AppStorage(AppLanguage.key) private var language = AppLanguage.automatic.rawValue
    @Environment(\.theme) private var accent
    let title: String
    @Binding var t: TriggerSetting
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Row(icon: title == "L2" ? "l2.rectangle.roundedtop" : "r2.rectangle.roundedtop", label: title) {
                Picker("", selection: $t.mode) {
                    ForEach(TriggerMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }.labelsHidden().frame(maxWidth: 190)
            }
            if t.mode != .off {
                ValueSlider(icon: "arrow.down.to.line", label: L("Início"), value: $t.start, range: 0...0.9)
                ValueSlider(icon: "bolt.fill", label: L("Força"), value: $t.strength, range: 0.05...1)
            }
        }
    }
}

struct StatusCard: View {
    @AppStorage(AppLanguage.key) private var language = AppLanguage.automatic.rawValue
    @ObservedObject var st = StatusModel.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle().fill(st.connected ? .green : .gray).frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 1) {
                    Text(st.connected ? st.name : L("Nenhum DualSense conectado")).font(.system(size: 13, weight: .semibold))
                    if let b = st.battery {
                        Text(L("Bateria") + " \(b)%" + (st.charging ? " · " + L("carregando") : "")).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if let b = st.battery {
                ProgressView(value: Double(b), total: 100).tint(b <= 20 ? .red : .green)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.background.opacity(0.55)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.primary.opacity(0.07)))
    }
}

struct FirmwareCard: View {
    @AppStorage(AppLanguage.key) private var language = AppLanguage.automatic.rawValue
    @Environment(\.theme) private var accent
    @ObservedObject var m: FirmwareModel
    @State private var confirm = false
    var body: some View {
        Card(kicker: "Firmware", title: L("Atualização pelo cabo USB")) {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                GridRow { Text(L("Atual")).foregroundStyle(.secondary); Text(m.current ?? "—").monospaced() }
                GridRow { Text(L("Disponível")).foregroundStyle(.secondary); Text(m.latest ?? "—").monospaced() }
            }.font(.callout)
            Group {
                switch m.phase {
                case .idle: Text(L("Conecte o controle com um cabo de dados e verifique.")).foregroundStyle(.secondary)
                case .busy(let s): HStack { ProgressView().controlSize(.small); Text(s) }
                case .ready: Text(m.updateAvailable ? "Atualização disponível." : L("Firmware atualizado."))
                        .foregroundStyle(m.updateAvailable ? .orange : .green)
                case .updating:
                    ProgressView(value: m.progress) { Text(L("Gravando… não desconecte o cabo.")) }
                case .done(let s): Text(s).foregroundStyle(.green)
                case .failed(let s): Text(s).foregroundStyle(.red).lineLimit(3).textSelection(.enabled)
                }
            }.font(.caption)
            HStack {
                Button(L("Verificar")) { Task { await m.check() } }
                    .disabled(m.phase == .updating || FirmwareModel.tool == nil)
                Spacer()
                Button(L("Instalar")) { confirm = true }
                    .buttonStyle(.borderedProminent).tint(accent)
                    .disabled(!(m.phase == .ready && m.updateAvailable))
            }
        }
        .confirmationDialog("Instalar o firmware \(m.latest ?? "")?", isPresented: $confirm) {
            Button(L("Instalar")) { Task { await m.install() } }
        } message: {
            Text(L("Mantenha o cabo conectado e o Mac ligado até o fim. Interromper a gravação pode deixar o controle inutilizável."))
        }
    }
}

// MARK: - Window content

struct SettingsView: View {
    @AppStorage(AppLanguage.key) private var language = AppLanguage.automatic.rawValue
    @State private var testing = false
    private var accent: Color {
        switch m.s.lightEffect {
        case .fixed: return Color(red: m.s.red, green: m.s.green, blue: m.s.blue)
        default: return defaultAccent
        }
    }
    @ObservedObject var m: SettingsModel
    @ObservedObject var fw: FirmwareModel

    private var color: Binding<Color> {
        Binding(get: { Color(red: m.s.red, green: m.s.green, blue: m.s.blue) },
                set: { c in
                    let n = NSColor(c).usingColorSpace(.deviceRGB) ?? .white
                    m.s.red = Double(n.redComponent); m.s.green = Double(n.greenComponent); m.s.blue = Double(n.blueComponent)
                })
    }
    private func volumeOn(_ k: WritableKeyPath<DSSettings, Double>) -> Binding<Bool> {
        Binding(get: { m.s[keyPath: k] >= 0 }, set: { m.s[keyPath: k] = $0 ? 0.5 : -1 })
    }

    var body: some View {
        // scrolls when the window is smaller than the layout (small screens, resized window)
        GeometryReader { g in
            ScrollView(.vertical) {
                // exactly the window's width (columns stretch or shrink), at least its height; scrolls when shorter
                content.frame(width: g.size.width).frame(minHeight: max(940, g.size.height), alignment: .top)
            }
        }
        .frame(minWidth: 1100, idealWidth: 1180, maxWidth: .infinity, minHeight: 480, idealHeight: 940, maxHeight: .infinity)
        .background(
            LinearGradient(colors: [Color(nsColor: .windowBackgroundColor), Color(nsColor: .underPageBackgroundColor)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            HStack(alignment: .top, spacing: 18) {
                VStack(spacing: 14) { lightsCard; micCard; ProfilesCard() }.frame(minWidth: 230, maxWidth: 380)
                VStack(spacing: 14) { centre; triggersCard }.frame(maxWidth: .infinity)
                VStack(spacing: 14) { StatusCard(); FirmwareCard(m: fw); audioCard; SystemCard() }.frame(minWidth: 230, maxWidth: 380)
            }
        }
        .padding(.horizontal, 26).padding(.top, 34).padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.theme, accent)
        .tint(accent)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: Bundle.main.image(forResource: "AppIconImage") ?? NSImage()).resizable().frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 1) {
                Text("DualDeck").font(.system(size: 22, weight: .bold))
                Text(L("Seu DualSense no Mac: luzes, gatilhos, testes e firmware")).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            PadPicker(m: m)
            Spacer()
            Button { DonateWindow.show() } label: { Label(L("Apoiar"), systemImage: "heart.fill") }
                .tint(.pink)
            Button(L("Restaurar padrão")) { m.s = DSSettings() }
        }
    }

    private var centre: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Visão geral").uppercased()).font(.system(size: 10.5, weight: .bold)).tracking(1.4).foregroundStyle(accent)
                Text(L("Seu controle agora")).font(.system(size: 13, weight: .semibold))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .trailing) {
                Toggle(L("Testar controle"), isOn: $testing).toggleStyle(.switch).controlSize(.small)
            }
            ControllerArt(s: m.s, testing: testing || ProcessInfo.processInfo.environment["DS_TESTER_PREVIEW"] != nil).frame(maxWidth: .infinity)
            if testing || ProcessInfo.processInfo.environment["DS_TESTER_PREVIEW"] != nil { DriftView().frame(maxWidth: .infinity).padding(.bottom, 8) }
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                Text(testing ? "Aperte os botões, mexa os analógicos e toque no touchpad." : L("As mudanças valem na hora, inclusive dentro dos jogos."))
            }.font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.background.opacity(0.55)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.primary.opacity(0.07)))
    }

    private var lightsCard: some View {
        Card(kicker: L("Luzes"), title: L("Barra de luz e jogador")) {
            Row(icon: "light.max", label: L("Barra de luz")) {
                Picker("", selection: $m.s.lightEffect) {
                    Text(L("Do jogo")).tag(LightEffect.game)
                    Text(L("Cor fixa")).tag(LightEffect.fixed)
                    Text(L("Arco-íris")).tag(LightEffect.rainbow)
                    Text(L("Bateria")).tag(LightEffect.battery)
                }.labelsHidden().frame(width: 120)
            }
            if m.s.lightEffect == .fixed {
                Row(icon: "paintpalette", label: L("Cor")) { ColorPicker("", selection: color, supportsOpacity: false).labelsHidden() }
                HStack(spacing: 8) {
                    ForEach(Array([(0, 0.4, 1.0), (1.0, 0.2, 0.25), (0.3, 1.0, 0.35), (1.0, 0.75, 0.1), (0.75, 0.3, 1.0), (1.0, 1.0, 1.0)].enumerated()), id: \.offset) { _, c in
                        Circle().fill(Color(red: c.0, green: c.1, blue: c.2)).frame(width: 22, height: 22)
                            .overlay(Circle().strokeBorder(.primary.opacity(0.15)))
                            .onTapGesture { m.s.red = c.0; m.s.green = c.1; m.s.blue = c.2 }
                    }
                }.padding(.leading, 24)
            }
            Divider()
            Row(icon: "person.fill", label: L("Luz do jogador")) {
                Picker("", selection: $m.s.playerLEDs) {
                    Text(L("Do jogo")).tag(-1); Text(L("Desligada")).tag(0)
                    ForEach(1...4, id: \.self) { Text("\($0)").tag($0) }
                    Text(L("Todas")).tag(5)
                }.labelsHidden().frame(width: 120)
            }
            Row(icon: "sun.max", label: L("Brilho")) {
                Picker("", selection: $m.s.brightness) {
                    Text(L("Alto")).tag(Brightness.high); Text(L("Médio")).tag(Brightness.medium); Text(L("Baixo")).tag(Brightness.low)
                }.labelsHidden().pickerStyle(.segmented).controlSize(.small).fixedSize()
            }
        }
    }

    private var micCard: some View {
        Card(kicker: L("Microfone"), title: L("Luz de status")) {
            Row(icon: "mic.fill", label: L("Luz do microfone")) {
                Picker("", selection: $m.s.micLED) {
                    Text(L("Padrão")).tag(MicLED.game); Text(L("Desligada")).tag(MicLED.off)
                    Text(L("Ligada")).tag(MicLED.on); Text(L("Piscando")).tag(MicLED.pulse)
                }.labelsHidden().frame(width: 120)
            }
        }
    }

    private var triggersCard: some View {
        Card(kicker: L("Gatilhos adaptativos e vibração"), title: L("Sinta a resistência")) {
            HStack(alignment: .top, spacing: 18) {
                TriggerCard(title: "L2", t: $m.s.left)
                Divider()
                TriggerCard(title: "R2", t: $m.s.right)
            }
            Divider()
            HStack(alignment: .bottom, spacing: 18) {
                ValueSlider(icon: "waveform.path", label: L("Vibração forte"), value: $m.s.rumbleStrong)
                ValueSlider(icon: "waveform", label: L("Vibração suave"), value: $m.s.rumbleSoft)
                Button { m.s.rumbleStrong = 0; m.s.rumbleSoft = 0 } label: { Image(systemName: "stop.fill") }
                    .help(L("Parar vibração"))
            }
        }
    }

    private var audioCard: some View {
        Card(kicker: L("Áudio"), title: L("Alto-falante e fone do controle")) {
            Toggle(isOn: volumeOn(\.speakerVolume)) { Label(L("Volume do alto-falante"), systemImage: "speaker.wave.2") }
                .toggleStyle(.switch).tint(accent)
            if m.s.speakerVolume >= 0 { Slider(value: $m.s.speakerVolume, in: 0...1).tint(accent) }
            Toggle(isOn: volumeOn(\.headphoneVolume)) { Label(L("Volume do fone"), systemImage: "headphones") }
                .toggleStyle(.switch).tint(accent)
            if m.s.headphoneVolume >= 0 { Slider(value: $m.s.headphoneVolume, in: 0...1).tint(accent) }
        }
    }
}

@MainActor final class SettingsWindow: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    let model: SettingsModel
    let firmware: FirmwareModel
    init(_ o: DualSenseOutput) { model = SettingsModel(o); firmware = FirmwareModel(o) }

    func show() {
        if window == nil {
            let host = NSHostingController(rootView: SettingsView(m: model, fw: firmware))
            host.sizingOptions = []   // the window, not the layout, decides the size
            let w = NSWindow(contentViewController: host)
            w.title = "DualDeck"
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            w.contentMinSize = NSSize(width: 1100, height: 480)
            // the full layout when it fits, else the visible screen minus a margin; centred
            let screen = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            w.setContentSize(NSSize(width: min(1180, screen.width - 40), height: min(940, screen.height - 40)))
            w.titleVisibility = .hidden
            w.titlebarAppearsTransparent = true
            w.isMovableByWindowBackground = true
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            window = w
        }
        // a regular app while the window is open: own menu bar ("DualDeck") and Dock icon
        NSApp.setActivationPolicy(.regular)
        AppMenu.install()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool { firmware.phase != .updating }   // never close mid-flash

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)   // back to a menu bar app
    }
}


// MARK: - Game profiles, system

struct ProfilesCard: View {
    @AppStorage(AppLanguage.key) private var language = AppLanguage.automatic.rawValue
    @Environment(\.theme) private var accent
    @ObservedObject var g = GameProfiles.shared
    private let levels: [(String, Double)] = [(L("Off"), 0), (L("Leve"), 0.3), (L("Médio"), 0.6), (L("Forte"), 1)]

    private func menu(_ t: Binding<TriggerSetting>) -> some View {
        let cur = t.wrappedValue.mode == .off ? 0 : t.wrappedValue.strength
        return Menu(levels.min(by: { abs($0.1 - cur) < abs($1.1 - cur) })?.0 ?? L("Off")) {
            ForEach(levels, id: \.0) { l in
                Button(l.0) { t.wrappedValue.mode = l.1 == 0 ? .off : .resistance; if l.1 > 0 { t.wrappedValue.strength = l.1 } }
            }
        }.menuStyle(.borderlessButton).fixedSize()
    }

    var body: some View {
        Card(kicker: L("Perfis por jogo"), title: L("Gatilhos automáticos")) {
            if g.list.isEmpty {
                Text(L("Adicione um jogo: os gatilhos dele valem sempre que ele estiver na frente."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach($g.list) { $p in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Circle().fill(g.frontApp == p.bundleID ? Color.green : .clear).frame(width: 6, height: 6)
                        Text(p.name).font(.callout.weight(.medium)).lineLimit(1)
                        Spacer()
                        Button { g.list.removeAll { $0.bundleID == p.bundleID } } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 6) {
                        Text("L2").font(.caption).foregroundStyle(.secondary); menu($p.left)
                        Spacer()
                        Text("R2").font(.caption).foregroundStyle(.secondary); menu($p.right)
                    }
                }
            }
            Button { g.addFromPanel() } label: { Label(L("Adicionar jogo…"), systemImage: "plus") }
        }
    }
}

struct SystemCard: View {
    @AppStorage(AppLanguage.key) private var language = AppLanguage.automatic.rawValue
    @Environment(\.theme) private var accent
    @ObservedObject var power = PowerManager.shared
    @State private var login = LoginItem.enabled
    @State private var note: String?

    var body: some View {
        Card(kicker: L("Sistema"), title: L("Energia e inicialização")) {
            Row(icon: "moon.zzz", label: L("Desligar se parado")) {
                Picker("", selection: $power.idleMinutes) {
                    Text(L("Nunca")).tag(0); Text("5 min").tag(5); Text("10 min").tag(10); Text("15 min").tag(15); Text("30 min").tag(30)
                }.labelsHidden().frame(width: 100)
            }
            Toggle(isOn: Binding(get: { login }, set: { LoginItem.set($0); login = LoginItem.enabled })) {
                Label(L("Abrir ao iniciar o Mac"), systemImage: "power.circle")
            }.toggleStyle(.switch)
            HStack {
                Button { note = PowerManager.shared.turnOff() ? nil : L("Só desliga por Bluetooth.") } label: {
                    Label(L("Desligar controle"), systemImage: "power")
                }
                if let note { Text(note).font(.caption).foregroundStyle(.secondary) }
            }
            Row(icon: "globe", label: L("Idioma")) {
                Picker("", selection: $language) {
                    Text(L("Automático")).tag(AppLanguage.automatic.rawValue)
                    Text("Português").tag(AppLanguage.pt.rawValue)
                    Text("English").tag(AppLanguage.en.rawValue)
                }.labelsHidden().frame(width: 120)
            }
            Divider()
            UpdateRow()
        }
    }
}

/// Stick drift check: each stick's position at rest against the dead zone.
struct DriftView: View {
    @AppStorage(AppLanguage.key) private var language = AppLanguage.automatic.rawValue
    @Environment(\.theme) private var accent
    private let deadZone = 0.08

    var body: some View {
        TimelineView(.animation) { _ in
            let s = InputSnapshot.read() ?? InputSnapshot()
            HStack(spacing: 28) { pad(L("Esquerdo"), s.left); pad(L("Direito"), s.right) }
        }
    }

    private func pad(_ name: String, _ v: CGPoint) -> some View {
        let r = hypot(v.x, v.y)
        let drift = r > deadZone && r < 0.3
        return VStack(spacing: 4) {
            ZStack {
                Circle().strokeBorder(.primary.opacity(0.2))
                Circle().fill(.primary.opacity(0.08)).frame(width: 64 * deadZone * 2 + 6, height: 64 * deadZone * 2 + 6)
                Path { p in p.move(to: CGPoint(x: 32, y: 0)); p.addLine(to: CGPoint(x: 32, y: 64)); p.move(to: CGPoint(x: 0, y: 32)); p.addLine(to: CGPoint(x: 64, y: 32)) }
                    .stroke(.primary.opacity(0.12))
                Circle().fill(accent).frame(width: 8, height: 8).offset(x: v.x * 28, y: -v.y * 28)
            }.frame(width: 64, height: 64)
            Text(name).font(.caption2.bold())
            Text(String(format: "x %+.2f  y %+.2f", v.x, v.y)).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
            Text(drift ? "Possível drift" : "OK").font(.caption2).foregroundStyle(drift ? .orange : .green)
        }
    }
}


struct UpdateRow: View {
    @AppStorage(AppLanguage.key) private var language = AppLanguage.automatic.rawValue
    @ObservedObject var u = Updater.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(L("Versão") + " \(u.current)", systemImage: "arrow.triangle.2.circlepath").font(.callout)
                Spacer()
                switch u.phase {
                case .available(let v):
                    Button(L("Instalar") + " \(v)") { Task { await u.install() } }.buttonStyle(.borderedProminent)
                case .checking, .installing:
                    ProgressView().controlSize(.small)
                default:
                    Button(L("Verificar atualizações")) { Task { await u.check() } }
                }
            }
            switch u.phase {
            case .upToDate: Text(L("Você está na versão mais recente.")).font(.caption).foregroundStyle(.green)
            case .installing: Text(L("Baixando e instalando… o app reabre sozinho.")).font(.caption).foregroundStyle(.secondary)
            case .failed(let e): Text(e).font(.caption).foregroundStyle(.red).lineLimit(2)
            default: EmptyView()
            }
        }
    }
}


/// The menu bar shown while the settings window is open.
@MainActor enum AppMenu {
    static func install() {
        guard NSApp.mainMenu?.items.first?.submenu?.title != "DualDeck" else { return }
        let main = NSMenu()
        let app = NSMenu(title: "DualDeck")
        app.addItem(withTitle: L("Apoiar") + "…", action: #selector(AppMenuTarget.donate), keyEquivalent: "").target = AppMenuTarget.shared
        app.addItem(withTitle: L("Verificar atualizações"), action: #selector(AppMenuTarget.update), keyEquivalent: "").target = AppMenuTarget.shared
        app.addItem(.separator())
        app.addItem(withTitle: L("Ocultar DualDeck"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(.separator())
        app.addItem(withTitle: L("Sair do DualDeck"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem(); appItem.submenu = app; main.addItem(appItem)
        let edit = NSMenu(title: L("Editar"))
        edit.addItem(withTitle: L("Copiar"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: L("Colar"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: L("Selecionar tudo"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem(); editItem.submenu = edit; main.addItem(editItem)
        let win = NSMenu(title: L("Janela"))
        win.addItem(withTitle: L("Minimizar"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        win.addItem(withTitle: L("Zoom"), action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        win.addItem(withTitle: L("Fechar"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let winItem = NSMenuItem(); winItem.submenu = win; main.addItem(winItem)
        NSApp.mainMenu = main
        NSApp.windowsMenu = win
    }
}

@MainActor final class AppMenuTarget: NSObject {
    static let shared = AppMenuTarget()
    @objc func donate() { DonateWindow.show() }
    @objc func update() { Task { await Updater.shared.check() } }
}
