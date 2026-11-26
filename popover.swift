import SwiftUI

// Menu bar popover: controller summary, quick actions, and the way into the full settings window.

struct PopoverView: View {
    @ObservedObject var m: SettingsModel
    @ObservedObject var st = StatusModel.shared
    let openSettings: () -> Void
    let quit: () -> Void

    private var accent: Color {
        m.s.lightEffect == .fixed ? Color(red: m.s.red, green: m.s.green, blue: m.s.blue) : Color(red: 0, green: 0.4, blue: 1.0)
    }
    private static let swatches: [(Double, Double, Double)] = [
        (0, 0.4, 1.0), (1.0, 0.2, 0.25), (0.3, 1.0, 0.35), (1.0, 0.75, 0.1), (0.75, 0.3, 1.0), (1.0, 1.0, 1.0),
    ]

    var body: some View {
        VStack(spacing: 12) {
            header
            PadPicker(m: m)
            HStack(spacing: 12) { batteryTile; triggerTile }
            lightTile
            HStack(spacing: 12) { playerTile; micTile }
            footer
        }
        .padding(16)
        .frame(width: 340)
        .background(
            LinearGradient(colors: [accent.opacity(0.35), Color(white: 0.08).opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .tint(accent)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("DualDeck").font(.system(size: 20, weight: .bold))
                    Circle().fill(st.connected ? .green : .gray).frame(width: 8, height: 8)
                }
                Text(st.connected ? st.name : "Nenhum controle conectado")
                    .font(.callout).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if let img = PhotoMasks.photo {
                ZStack {
                    Image(nsImage: img).resizable().interpolation(.high)
                    if m.s.lightEffect != .game, let led = PhotoMasks.lightbar {
                        Rectangle().fill(m.s.lightEffect == .rainbow
                                         ? AnyShapeStyle(AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red], center: .top))
                                         : AnyShapeStyle(accent))
                            .mask(Image(nsImage: led).resizable().interpolation(.high))
                    }
                }
                .frame(width: 92, height: 92 * 809 / 1200)
                .shadow(color: accent.opacity(0.6), radius: 10)
            }
        }
    }

    private func tile<C: View>(_ icon: String, _ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon).font(.system(size: 13, weight: .semibold)).labelStyle(.titleAndIcon)
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.08)))
    }

    private var batteryTile: some View {
        tile("battery.75percent", "Bateria") {
            if let b = st.battery {
                Text("\(b)%").font(.system(size: 22, weight: .bold)).foregroundStyle(b <= 20 ? .red : .primary)
                Text(st.charging ? "Carregando" : "Em uso").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("—").font(.system(size: 22, weight: .bold))
                Text("Desconectado").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private static let levels: [(String, Double)] = [("Off", 0), ("Leve", 0.3), ("Médio", 0.6), ("Forte", 1)]

    private func levelMenu(_ t: WritableKeyPath<DSSettings, TriggerSetting>) -> some View {
        let cur = m.s[keyPath: t].mode == .off ? 0 : m.s[keyPath: t].strength
        let name = Self.levels.min(by: { abs($0.1 - cur) < abs($1.1 - cur) })?.0 ?? "Off"
        return Menu(name) {
            ForEach(Self.levels, id: \.0) { l in
                Button(l.0) {
                    m.s[keyPath: t].mode = l.1 == 0 ? .off : .resistance
                    if l.1 > 0 { m.s[keyPath: t].strength = l.1 }
                }
            }
        }
        .menuStyle(.borderlessButton).fixedSize()
    }

    private var triggerTile: some View {
        tile("slider.horizontal.3", "Gatilhos") {
            HStack {
                Image(systemName: "l2.rectangle.roundedtop").foregroundStyle(.secondary)
                Spacer(minLength: 4)
                levelMenu(\.left)
            }
            HStack {
                Image(systemName: "r2.rectangle.roundedtop").foregroundStyle(.secondary)
                Spacer(minLength: 4)
                levelMenu(\.right)
            }
        }
    }

    private var lightTile: some View {
        tile("light.max", "Barra de luz") {
            HStack(spacing: 8) {
                ForEach(Array(Self.swatches.enumerated()), id: \.offset) { _, c in
                    let on = m.s.lightEffect == .fixed && abs(m.s.red - c.0) < 0.02 && abs(m.s.green - c.1) < 0.02 && abs(m.s.blue - c.2) < 0.02
                    Circle().fill(Color(red: c.0, green: c.1, blue: c.2))
                        .frame(width: 24, height: 24)
                        .overlay(Circle().strokeBorder(.white, lineWidth: on ? 2.5 : 0))
                        .onTapGesture { m.s.lightEffect = .fixed; m.s.red = c.0; m.s.green = c.1; m.s.blue = c.2 }
                }
                Circle().fill(AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red], center: .center))
                    .frame(width: 24, height: 24)
                    .overlay(Circle().strokeBorder(.white, lineWidth: m.s.lightEffect == .rainbow ? 2.5 : 0))
                    .onTapGesture { m.s.lightEffect = .rainbow }
                    .help("Arco-íris")
                Image(systemName: "battery.75percent").font(.system(size: 13))
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(LinearGradient(colors: [.green, .yellow, .red], startPoint: .top, endPoint: .bottom)))
                    .overlay(Circle().strokeBorder(.white, lineWidth: m.s.lightEffect == .battery ? 2.5 : 0))
                    .onTapGesture { m.s.lightEffect = .battery }
                    .help("Cor pela bateria")
                Spacer(minLength: 0)
                Button { m.s.lightEffect = .game } label: { Image(systemName: "gamecontroller") }
                    .buttonStyle(.borderless).help("Controlada pelo jogo")
                    .foregroundStyle(m.s.lightEffect == .game ? accent : .secondary)
            }
        }
    }

    private var playerTile: some View {
        tile("person.fill", "Luz do jogador") {
            Picker("", selection: $m.s.playerLEDs) {
                Text("Do jogo").tag(-1); Text("Desligada").tag(0)
                ForEach(1...4, id: \.self) { Text("\($0)").tag($0) }
                Text("Todas").tag(5)
            }.labelsHidden()
        }
    }

    private var micTile: some View {
        tile("mic.fill", "Luz do microfone") {
            Picker("", selection: $m.s.micLED) {
                Text("Padrão").tag(MicLED.game); Text("Desligada").tag(MicLED.off)
                Text("Ligada").tag(MicLED.on); Text("Piscando").tag(MicLED.pulse)
            }.labelsHidden()
        }
    }

    private var footer: some View {
        HStack {
            Menu {
                Button("Desligar controle") { PowerManager.shared.turnOff() }
                Button("Sair do app") { quit() }
            } label: { Image(systemName: "power") }
            .menuStyle(.borderlessButton).fixedSize().help("Desligar")
            Spacer()
            Button(action: openSettings) {
                Label("Abrir configurações", systemImage: "gearshape.fill").padding(.horizontal, 6)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            Spacer()
            Button("Restaurar") { m.s = DSSettings() }.buttonStyle(.borderless).font(.caption)
        }
        .padding(.top, 4)
    }
}

@MainActor final class StatusPopover: NSObject {
    private let popover = NSPopover()
    private var monitor: Any?

    init(model: SettingsModel, openSettings: @escaping () -> Void) {
        super.init()
        popover.behavior = .transient
        popover.animates = true
        let host = NSHostingController(rootView: PopoverView(
            m: model,
            openSettings: { [weak self] in self?.popover.performClose(nil); openSettings() },
            quit: { NSApp.terminate(nil) }))
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
    }

    func toggle(from button: NSStatusBarButton) {
        if popover.isShown { popover.performClose(nil); return }
        if let v = popover.contentViewController?.view {
            v.layoutSubtreeIfNeeded()
            popover.contentSize = v.fittingSize   // size known before showing, so it opens below the menu bar
        }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }
}
