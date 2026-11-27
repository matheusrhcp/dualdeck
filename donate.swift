import SwiftUI
import AppKit

// Support the project: Pix key and PayPal, both on the same e-mail.
enum Donate {
    static let email = "matheusmore@gmail.com"
    static let paypal = URL(string: "https://www.paypal.com/donate/?business=matheusmore%40gmail.com&no_recurring=0&item_name=DualDeck")!
}

struct DonateView: View {
    @AppStorage(AppLanguage.key) private var language = AppLanguage.automatic.rawValue
    @Environment(\.theme) private var accent
    @State private var copied = false
    var body: some View {
        let _ = language
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "heart.fill").foregroundStyle(.pink)
                Text(L("Apoie o DualDeck")).font(.title3.bold())
            }
            Text(L("O DualDeck é gratuito e open source. Se ele te ajudou, considere uma doação."))
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                Text(L("Chave Pix")).font(.caption.bold()).foregroundStyle(.secondary)
                HStack {
                    Text(Donate.email).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                    Spacer()
                    Button(copied ? L("Copiado!") : L("Copiar")) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(Donate.email, forType: .string)
                        copied = true
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(.primary.opacity(0.06)))
            }
            Button { NSWorkspace.shared.open(Donate.paypal) } label: {
                Label(L("Doar com PayPal"), systemImage: "creditcard").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
        }
        .padding(20)
        .frame(width: 360)
    }
}

@MainActor enum DonateWindow {
    private static var window: NSWindow?
    static func show() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: DonateView()))
            w.title = L("Apoiar")
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
