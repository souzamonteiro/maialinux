# MaiaLinux for Anbernic RG353V

![MaiaLinux at Neon Twilight](images/MaiaLinux_at_Neon_Twilight_640x480.png)

**MaiaLinux** é uma distribuição/camada de ambiente desktop e desenvolvimento reprodutível baseada no **ArkOS (Ubuntu 19.10 Eoan ARM64)** para o console portátil **Anbernic RG353V (Rockchip RK3566)**.

Transforma o RG353V em um **pocket computer Linux completo** com **LXQt**, **Teclado Virtual (Touchscreen + Gamepad)**, **Geany IDE**, **QTerminal** e **toolchains completas de C/C++, Python 3, SDL2, GTK3 e Qt5**, mantendo **100% de compatibilidade com o EmulationStation, RetroArch e aceleração GPU Mali Bifrost G52**.

---

## Principais Recursos

- **Dual-Mode (Jogos + Desenvolvimento)**:
  - Inicia no **EmulationStation** normalmente e permite abrir o desktop **LXQt** a qualquer momento em `Options -> Tools -> Launch-MaiaLinux-LXQt`.
  - Inclui utilitário `Switch-Boot-Mode.sh` (no menu `Tools` ou via terminal) para alternar entre boot no EmulationStation (`es`) ou boot direto no LXQt (`desktop`).
- **Interface Otimizada para Tela 640x480 (3.5" IPS)**:
  - Wallpaper oficial **MaiaLinux at Neon Twilight** em `640x480` + Boot Splash U-Boot (`logo.bmp`).
  - Painel LXQt compacto de `24px`, fontes `8pt/9pt` de alto contraste, tema escuro Catppuccin/Fusion e janelas maximizadas sem desperdício de espaço.
- **Teclado Virtual + Touchscreen + Controles Físicos (`gptokeyb`)**:
  - **Touchscreen**: Funciona nativamente via `libinput` (toque para clicar e digitar no teclado virtual).
  - **Teclado Virtual (`matchbox-keyboard` / `onboard`)**: Posicionado e ancorado na base da tela (`640x160`, `y=296`) sem barra de título; pode ser exibido/ocultado pelo ícone no painel ou pelos botões **Select** / **Y** (`F12`).
  - **Gamepad no Desktop**:
    - **Analógico Esquerdo**: Cursor do Mouse
    - **L1 / Botão A**: Clique Esquerdo
    - **R1 / Botão B**: Clique Direito
    - **Select / Botão Y**: Mostrar/Esconder Teclado Virtual (`F12`)
    - **R3 (Clique Analógico Dir.)**: Abrir Terminal (`F10`)
    - **D-Pad / Analógico Direito**: Setas direcionais (navegar no código/menus)
    - **Start**: Enter | **X**: Backspace | **L3**: Esc | **L2/R2**: PageUp/PageDown
- **Preservação Cirúrgica da GPU Mali (`libmali-bifrost-g52-g2p0-gbm.so`) + Wayland-EGL GTK3 Fix**:
  - Resolve automaticamente o conflito histórico do ArkOS entre `libmali-rk-bifrost-g31-rxp0-wayland-gbm` e `libwayland-egl1`, mantendo `libMali.so`/`libEGL.so.1`/`libGLESv2.so.2`/`libgbm.so.1` na GPU Mali G52 para o EmulationStation e `libwayland-egl.so.1` oficial do Mesa para aplicativos GTK3 (`Geany`, `Onboard`).
  - Restaura os cabeçalhos `/usr/include` removidos na imagem base do ArkOS para permitir compilação nativa C/C++/SDL2 no console.
- **Ambiente de Desenvolvimento Completo Pré-Instalado**:
  - **C/C++ & Sistema**: `gcc`, `g++`, `make`, `cmake`, `gdb`, `git`, `pkg-config`, `tmux`, `htop`, `openssh-server`
  - **Python 3**: `python3`, `pip`, `venv`, `tkinter`, `pygame`, `evdev`
  - **Bibliotecas Gráficas/Jogos**: `libsdl2-dev` (`image`, `mixer`, `ttf`, `gfx`), `libgtk-3-dev`, `qtbase5-dev`, `mesa-utils`
  - **IDEs e Editores**: `Geany` (pré-configurado para 640x480), `FeatherPad`, `Vim`, `Nano`
  - **Exemplos Prontos em `~/projects`**: `hello-c`, `hello-sdl2`, `hello-python-tk`, `hello-pygame`

---

## Estrutura do Projeto

```text
maialinux/
├── Makefile                        # Automação: install-sdcard, healthcheck, test-qemu, build-image
├── install-on-device.sh            # Instalador idempotente executado dentro do rootfs ARM64
├── images/                         # Wallpapers e artes oficiais MaiaLinux (640x480 e 1920x1080)
├── config/
│   ├── xorg/                       # Rockchip DRM modesetting (sem Glamor), Touchscreen e Xwrapper
│   ├── lxqt/                       # Perfil LXQt + Openbox + PCManFM-Qt ajustado para 640x480
│   ├── keyboard/                   # Script de toggle do teclado virtual (F12 / Select / Y)
│   ├── controls/                   # Perfil gptokeyb (desktop.gptk) para o gamepad do RG353V
│   ├── geany/                      # Configuração da IDE Geany para 640x480
│   ├── desktop-entries/            # Atalhos da Área de Trabalho e Painel
│   └── systemd/                    # Serviço systemd maialinux-desktop.service
├── scripts/
│   ├── host/                       # Scripts para PC Linux (chroot QEMU, SD card, imagem .img.xz, simulador 640x480)
│   └── target/                     # Scripts instalados no RG353V (/usr/local/bin e /roms/tools)
└── examples/                       # Projetos de exemplo (C, SDL2, Python Tkinter, Pygame)
```

---

## Como Instalar e Testar

### Opção 1: Instalar Diretamente no SD Card Montado no PC (Recomendado — Rápido via QEMU User-Mode)

Com o cartão SD do ArkOS montado em `/media/roberto/root` e `/media/roberto/BOOT`:

```bash
cd /home/roberto/projects/maialinux
make install-sdcard SDCARD_ROOT=/media/roberto/root
```

O script usa `qemu-aarch64-static` + `chroot` para instalar e compilar todos os pacotes na velocidade da CPU/rede do seu PC, sem precisar fazer download lento pelo Wi-Fi do console.

### Opção 2: Simular o Desktop ARM64 em 640x480 no PC (Rootless via Bubblewrap + QEMU + Xephyr)

Você pode testar a sessão real ARM64 do LXQt na resolução exata `640x480` do RG353V sem precisar de `sudo`:

```bash
# Modo interativo (abre janela 640x480 com o LXQt ARM64 rodando via QEMU):
./scripts/host/test-qemu-desktop.sh /media/roberto/root --interactive

# Modo captura de tela (salva screenshot em /tmp/maialinux-qemu-640x480.png):
./scripts/host/test-qemu-desktop.sh /media/roberto/root --screenshot-only
```

### Opção 3: Gerar uma Imagem `.img.xz` Reprodutível a partir do `.img` Original do ArkOS

```bash
make build-image BASE_IMG=/home/roberto/projects/Anbernic/RG353V/ArkOS_RG353V_v2.0_02092025.img
```

### Opção 4: Instalar Diretamente no Console RG353V via SSH

```bash
scp -r /home/roberto/projects/maialinux ark@<IP_DO_RG353V>:/tmp/maialinux
ssh ark@<IP_DO_RG353V> "sudo /tmp/maialinux/install-on-device.sh"
```

---

## Uso no Console (Anbernic RG353V)

1. **Iniciar o Desktop LXQt**:
   - No EmulationStation, acesse **Options** -> **Tools** -> **Launch-MaiaLinux-LXQt**.
2. **Alternar Modo de Boot (EmulationStation vs. Desktop Direto)**:
   - Em **Options** -> **Tools** -> **Switch-Boot-Mode**, ou no terminal:
     ```bash
     sudo switch-boot-mode.sh desktop   # Inicia direto no LXQt ao ligar o console
     sudo switch-boot-mode.sh es        # Inicia no EmulationStation (Dual-Mode)
     ```
3. **Voltar para os Jogos (EmulationStation)**:
   - Clique duas vezes no ícone **Voltar aos Jogos (ES)** na área de trabalho, ou no menu `Maia -> Leave -> Logout`.
4. **Verificar Saúde do Sistema**:
   ```bash
   maialinux-healthcheck.sh
   ```

---

## Licença

Distribuído sob a licença MIT. Veja `LICENSE` para mais detalhes.
