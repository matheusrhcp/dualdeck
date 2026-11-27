import Foundation

// Interface language. The texts are written in Portuguese in the code; L() returns the English one when
// English is chosen (Settings → System → Language), or when "Automatic" and the Mac is not in Portuguese.

enum AppLanguage: String, CaseIterable {
    case automatic, pt, en
    static let key = "language"
    static var current: AppLanguage { AppLanguage(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .automatic }
    static var isEnglish: Bool {
        switch current {
        case .pt: return false
        case .en: return true
        case .automatic: return !(Locale.preferredLanguages.first ?? "en").hasPrefix("pt")
        }
    }
}

func L(_ pt: String) -> String { AppLanguage.isEnglish ? (english[pt] ?? pt) : pt }

private let english: [String: String] = [
    // dashboard
    "Seu DualSense no Mac: luzes, gatilhos, testes e firmware": "Your DualSense on the Mac: lights, triggers, tests and firmware",
    "Restaurar padrão": "Restore defaults",
    "Restaurar": "Reset",
    "Visão geral": "Overview",
    "Seu controle agora": "Your controller now",
    "Testar controle": "Test controller",
    "Aperte os botões, mexa os analógicos e toque no touchpad.": "Press the buttons, move the sticks and touch the touchpad.",
    "As mudanças valem na hora, inclusive dentro dos jogos.": "Changes apply at once, inside games too.",
    "Escolha o controle a configurar; ele vibra para você saber qual é.": "Pick the controller to set up; it rumbles so you know which one it is.",
    "Controle": "Controller",
    // lights
    "Luzes": "Lights",
    "Barra de luz e jogador": "Light bar and player",
    "Barra de luz": "Light bar",
    "Do jogo": "From game",
    "Cor fixa": "Fixed colour",
    "Arco-íris": "Rainbow",
    "Bateria": "Battery",
    "Cor": "Colour",
    "Cor pela bateria": "Colour by battery",
    "Controlada pelo jogo": "Controlled by the game",
    "Luz do jogador": "Player light",
    "Desligada": "Off",
    "Ligada": "On",
    "Piscando": "Blinking",
    "Todas": "All",
    "Brilho": "Brightness",
    "Alto": "High",
    "Médio": "Medium",
    "Baixo": "Low",
    "Microfone": "Microphone",
    "Luz de status": "Status light",
    "Luz do microfone": "Mic light",
    "Padrão": "Default",
    // triggers and rumble
    "Gatilhos adaptativos e vibração": "Adaptive triggers and rumble",
    "Sinta a resistência": "Feel the resistance",
    "Gatilhos": "Triggers",
    "Desativado": "Off",
    "Resistência contínua": "Continuous resistance",
    "Gatilho de arma (seção)": "Weapon trigger (section)",
    "Vibração": "Vibration",
    "Início": "Start",
    "Força": "Strength",
    "Vibração forte": "Strong rumble",
    "Vibração suave": "Soft rumble",
    "Parar vibração": "Stop rumble",
    "Off": "Off",
    "Leve": "Light",
    "Forte": "Strong",
    // drift
    "Esquerdo": "Left",
    "Direito": "Right",
    "Possível drift": "Possible drift",
    // status
    "Nenhum DualSense conectado": "No DualSense connected",
    "Nenhum controle conectado": "No controller connected",
    "Carregando": "Charging",
    "carregando": "charging",
    "Em uso": "In use",
    "em uso": "in use",
    "Desconectado": "Disconnected",
    "carga completa": "fully charged",
    "estado desconhecido": "unknown state",
    "DualSense: bateria indisponível": "DualSense: battery unavailable",
    "DualSense com bateria baixa": "DualSense battery low",
    "DualSense carregado": "DualSense charged",
    "A bateria está cheia: pode desconectar do carregador.": "The battery is full: you can unplug the charger.",
    "Restam %d%%. Conecte o carregador.": "%d%% left. Plug in the charger.",
    // firmware
    "Atualização pelo cabo USB": "Update over USB cable",
    "Atual": "Current",
    "Disponível": "Available",
    "Conecte o controle com um cabo de dados e verifique.": "Connect the controller with a data cable and check.",
    "Atualização disponível.": "Update available.",
    "Firmware atualizado.": "Firmware up to date.",
    "Gravando… não desconecte o cabo.": "Writing… do not unplug the cable.",
    "Verificar": "Check",
    "Instalar": "Install",
    "Mantenha o cabo conectado e o Mac ligado até o fim. Interromper a gravação pode deixar o controle inutilizável.":
        "Keep the cable connected and the Mac on until it finishes. Interrupting the write can leave the controller unusable.",
    "Lendo o controle…": "Reading the controller…",
    "Consultando a Sony…": "Asking Sony…",
    "Controle não encontrado. Conecte-o com um cabo USB de dados.": "Controller not found. Connect it with a USB data cable.",
    "Não foi possível consultar a Sony: ": "Could not reach Sony: ",
    "Atualização concluída.": "Update complete.",
    "Falha na atualização.": "Update failed.",
    "O dsmactools não está instalado.": "dsmactools is not installed.",
    "Atualizando firmware do DualSense": "Updating DualSense firmware",
    // audio
    "Áudio": "Audio",
    "Alto-falante e fone do controle": "Controller speaker and headphones",
    "Volume do alto-falante": "Speaker volume",
    "Volume do fone": "Headphone volume",
    // profiles
    "Perfis por jogo": "Per-game profiles",
    "Gatilhos automáticos": "Automatic triggers",
    "Adicione um jogo: os gatilhos dele valem sempre que ele estiver na frente.": "Add a game: its triggers apply whenever it is in front.",
    "Adicionar jogo…": "Add game…",
    "Adicionar": "Add",
    // system
    "Sistema": "System",
    "Energia e inicialização": "Power and startup",
    "Desligar se parado": "Turn off when idle",
    "Nunca": "Never",
    "Abrir ao iniciar o Mac": "Open at login",
    "Desligar controle": "Turn off controller",
    "Só desliga por Bluetooth.": "Only works over Bluetooth.",
    "Desligar": "Turn off",
    "Sair do app": "Quit app",
    "Idioma": "Language",
    "Automático": "Automatic",
    // updates
    "Versão": "Version",
    "Verificar atualizações": "Check for updates",
    "Você está na versão mais recente.": "You are on the latest version.",
    "Baixando e instalando… o app reabre sozinho.": "Downloading and installing… the app reopens by itself.",
    "Não foi possível verificar: ": "Could not check: ",
    "Falha ao instalar: ": "Install failed: ",
    "disponível": "available",
    "Atualizar": "Update",
    "Atualizando…": "Updating…",
    // popover
    "Abrir configurações": "Open settings",
    "Resistência L2 e R2": "L2 and R2 resistance",
    // redesign
    "Gatilhos adaptativos": "Adaptive triggers",
    "Sem resistência: o gatilho fica como o jogo deixar.": "No resistance: the trigger stays as the game sets it.",
    "solto": "released",
    "apertado": "pressed",
    "Áudio do controle": "Controller audio",
    "Alto-falante": "Speaker",
    "Fone": "Headphones",
    "No começo da barra, o jogo decide.": "At the start of the bar, the game decides.",
    "Pelo cabo USB de dados.": "Over a USB data cable.",
    "Fundo": "Background",
    "Aurora": "Aurora",
    "Brilho suave": "Glow",
    "Transparência": "Transparency",
    "Carga completa": "Fully charged",
    "Ícone sempre visível": "Always show icon",
    "Notificações bloqueadas": "Notifications blocked",
    "Notificações": "Notifications",
    "Ativar": "Turn on",
    "Testar": "Test",
    "As notificações estão funcionando.": "Notifications are working.",
    "Vidro": "Glass",
    // app menu
    "Ocultar DualDeck": "Hide DualDeck",
    "Sair do DualDeck": "Quit DualDeck",
    "Editar": "Edit",
    "Colar": "Paste",
    "Selecionar tudo": "Select All",
    "Janela": "Window",
    "Minimizar": "Minimize",
    "Zoom": "Zoom",
    "Fechar": "Close",
    // donate
    "Apoiar": "Support",
    "Apoie o DualDeck": "Support DualDeck",
    "O DualDeck é gratuito e open source. Se ele te ajudou, considere uma doação.": "DualDeck is free and open source. If it helped you, consider a donation.",
    "Chave Pix": "Pix key (Brazil)",
    "Copiar": "Copy",
    "Copiado!": "Copied!",
    "Doar com PayPal": "Donate with PayPal",
]
