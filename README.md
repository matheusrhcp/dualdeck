# DualDeck

Seu DualSense no Mac: luzes, gatilhos adaptativos, testes e firmware, direto da barra de menus.

![Ícone](Resources/AppIconImage.png)

## O que faz

- **Barra de luz**: cor fixa, arco-íris, cor pela bateria ou a do jogo; brilho; luz do jogador; luz do microfone.
- **Gatilhos adaptativos** (L2/R2): resistência contínua, gatilho de arma ou vibração, com início e força ajustáveis. Funciona dentro dos jogos.
- **Perfis por jogo**: gatilhos próprios para cada app, aplicados quando ele está em primeiro plano.
- **Testador**: cada botão apertado acende na imagem do controle; analógicos, gatilhos, touchpad e teste de drift.
- **Firmware**: verifica e instala o firmware oficial da Sony pelo cabo USB, via [dsmactools](https://github.com/olliejudge/dsmactools).
- **Energia**: bateria na barra de menus, aviso de bateria baixa, desligar o controle e desligamento automático quando parado.
- **Vários controles**: cada DualSense com suas próprias configurações.
- **Atualizações**: o app verifica e instala novas versões publicadas nas Releases.

## Instalação

Baixe o `.dmg` em [Releases](../../releases/latest), arraste o DualDeck para Aplicativos e abra.

O app não é assinado por um desenvolvedor Apple. Na primeira abertura o macOS bloqueia: vá em
**Ajustes do Sistema → Privacidade e Segurança** e clique em **Abrir Mesmo Assim**.

Requer macOS 15 (Sequoia) ou posterior e Mac com Apple Silicon.

## Compilar

```sh
./build.sh          # compila, instala em ~/Applications/DualDeck.app e reinicia
./make_dmg.sh       # gera dist/DualDeck-<versão>.dmg
```

## Créditos e licenças

- Código do DualDeck: licença MIT (`LICENSE`).
- [dsmactools](https://github.com/olliejudge/dsmactools), embutido para o firmware: MIT (`Vendor/DSMACTOOLS-LICENSE.txt`).
- Imagem do controle e máscaras dos botões: exportadas do *PlayStation 5 Controller Mockup* de Piero Unisono,
  licença Creative Commons Atribuição-NãoComercial (`Resources/CONTROLLER-IMAGE-LICENSE.txt`). Por isso este
  projeto não pode ser vendido com essas imagens.

PlayStation, PS5 e DualSense são marcas registradas da Sony Interactive Entertainment. Projeto independente,
sem afiliação com a Sony.
