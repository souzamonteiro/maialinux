# MaiaLinux 2.0.0: Arquitetura, Boot Chain e Guia de Customização

Este documento descreve detalhadamente a arquitetura interna, o esquema de particionamento, a cadeia de inicialização (Boot Chain), a técnica de injeção de logo offline no Kernel 5.10 e as integrações de interface (EmulationStation, LXQt, Teclado Virtual e Modo Silencioso) do **MaiaLinux 2.0.0** para o portátil **Anbernic RG353V (Rockchip RK3566)**.

---

## 1. Visão Geral da Plataforma

* **Dispositivo**: Anbernic RG353V
* **SoC**: Rockchip RK3566 (Quad-Core Cortex-A55 @ 1.8 GHz, GPU Mali Bifrost G52-2EE)
* **Tela**: IPS 3.5" (Resolução nativa: 640×480, formato 4:3) + Saída Mini-HDMI (até 1920×1080 @ 60Hz)
* **Entradas**: Tela sensível ao toque capacitiva (Multi-touch), D-Pad, dois analógicos clicáveis (L3/R3), botões frontais (A, B, X, Y, Select, Start, Function), botões de ombro (L1, L2, R1, R2) e botão de Power físico lateral.
* **Sistema Base**: dArkOS v08272026 (Debian 13 "Trixie" aarch64)
* **Kernel**: Linux 5.10.226 Rockchip RK356x SMP PREEMPT
* **Ambiente Gráfico**: LXQt + Openbox + Xorg (Display `:1`, `vt1`) + EmulationStation (KMS/DRM direto)

---

## 2. Esquema de Partições do Cartão SD (MicroSD TF1/INT)

O cartão SD de boot do RG353V segue a seguinte estrutura de setores e partições:

| Partição | Dispositivo | Tipo / FS | Tamanho Aprox. | Rótulo / Ponto de Montagem | Conteúdo e Função |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Setores 0-64M** | Raw Block | - | ~32 MB | (U-Boot / SPL) | Armazena o `idbloader.img`, `trust.img` e `uboot.img` nos offsets fixos do SoC RK3566. |
| **Partição 1** | `/dev/mmcblk1p1` | Raw / Ext2 | 4 MB | `misc` | Parâmetros de recuperação / fastboot do Android/Rockchip. |
| **Partição 2** | `/dev/mmcblk1p2` | Raw / Ext2 | 4 MB | `resource` | **CRÍTICA:** Contém os DTBs e recursos de inicialização do U-Boot (`resource.img`). **NUNCA DEVE SER SOBRESCRITA** com ferramentas legadas de kernel 4.19, sob risco de tela preta irreversível no display LCD. |
| **Partição 3** | `/dev/mmcblk1p3` | FAT32 (vfat) | ~98 MB | `BOOT` (antigo `dArkOS_Fat`) | Partição de boot contendo o kernel Linux (`Image`, ~32MB), árvore de dispositivos (`rk3566-353v.dtb`), initramfs (`uInitrd`) e arquivo de configuração do bootloader (`extlinux/extlinux.conf`). |
| **Partição 4** | `/dev/mmcblk1p4` | BTRFS / Ext4 | ~8-16 GB | `ROOTFS` | Sistema operacional raiz completo (Debian 13 Trixie), binários, bibliotecas e ambiente desktop LXQt. |
| **Partição 5** | `/dev/mmcblk1p5` | exFAT | Restante SD | `EASYROMS` (`/roms`) | Jogos, temas do EmulationStation e lançadores do MaiaLinux (`/roms/maialinux/`). |

> [!CAUTION]
> **Atenção ao limite de 98 MB da Partição 3 (`BOOT`):**
> Como o kernel unificado `Image` possui cerca de 32 a 34 MB, manter arquivos de backup duplicados (como `Image.bak`) esgota completamente o espaço da partição. Ao copiar um novo kernel sem espaço livre prévio, a cópia será truncada silenciosamente, causando falha no boot (tela preta). Mantenha sempre pelo menos 40 MB livres antes de sobrescrever o arquivo `Image`.

---

## 3. Cadeia de Inicialização (Boot Chain) e Boot Logo do Kernel

### 3.1 Por que o arquivo `logo.pbm` na partição FAT não funciona?
No kernel Rockchip 5.10 (diferente de implementações antigas do U-Boot), o DRM/KMS do kernel não busca imagens soltas no sistema de arquivos durante a fase de inicialização imediata. O logotipo de boot é **compilado estaticamente dentro da imagem do kernel** (`Image`), utilizando o subsistema de framebuffer logo do Linux:
- Arquivo de destino no código-fonte: `drivers/video/logo/logo_linux_clut224.ppm`
- Formato: PPM (Portable Pixmap) em modo texto ASCII bruto, limitado estritamente a **224 cores indexadas (CLUT)**.

### 3.2 Gerador Offline de Imagem do Kernel (`generate-custom-kernel-image.py`)
Para atualizar o logotipo do kernel sem depender de pipelines online no GitHub Actions ou scripts quebrados, foi desenvolvido o script:
`/home/roberto/projects/maialinux/scripts/host/generate-custom-kernel-image.py`

#### Como funciona o script:
1. **Toolchain Linaro ARM64**: Utiliza o compilador Linaro GCC 6.3.1 (`aarch64-linux-gnu-gcc`) em cache local.
2. **Árvore do Kernel Rockchip 5.10.226**: Utiliza a base oficial em `.cache/upstream/sources/linux-rk356x-5.10/`.
3. **Conversão da Imagem PNG**:
   - Redimensiona o wallpaper/logo do MaiaLinux para `640×480` (resolução nativa do LCD).
   - Converte para PPM com paleta quantizada de 224 cores:
     ```bash
     ppmquant 224 input.ppm > temp.ppm
     pnmnoraw temp.ppm > logo_linux_clut224.ppm
     ```
4. **Substituição e Compilação**:
   - Sobrescreve `drivers/video/logo/logo_linux_clut224.ppm`.
   - Executa a compilação paralela:
     ```bash
     make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc) Image
     ```
   - Grava o kernel resultante em `output/Image` em cerca de 15 segundos (graças ao cache de compilação).

### 3.3 Inicialização do Kernel e Exibição do Logo (DRM fbcon)
A configuração de boot em `/media/roberto/BOOT/extlinux/extlinux.conf` utiliza:

```text
LABEL MaiaLinux
  LINUX /Image
  FDT /rk3566-353v.dtb
  APPEND root=/dev/mmcblk1p4 initrd=/uInitrd rootwait rw fsck.repair=yes quiet splash plymouth.ignore-udev vt.global_cursor_default=0 net.ifnames=0 console=tty1 plymouth.ignore-serial-consoles consoleblank=0 loglevel=5 video=HDMI-A-1:1280x720@60
```

> [!IMPORTANT]
> **Preservação do Console `tty1`**: O subsistema DRM/fbcon do Linux exibe o logotipo embutido do kernel prioritariamente no terminal ativo primário (`console=tty1`). Não redirecione para `tty3` nem altere este console, pois isso impede a renderização imediata do belo logotipo do MaiaLinux 2.0.0 no display LCD.

---

## 4. Integração do EmulationStation

O MaiaLinux 2.0.0 adiciona um sistema independente na tela principal do EmulationStation, facilitando o lançamento do ambiente desktop sem a necessidade de navegar por menus secundários (`Options -> Tools`):

1. **Definição em `/etc/emulationstation/es_systems.cfg`**:
   ```xml
   <system>
       <name>maialinux</name>
       <fullname>MaiaLinux Desktop</fullname>
       <path>/roms/maialinux/</path>
       <extension>.sh .SH</extension>
       <command>sudo perfmax %GOVERNOR% %ROM%; %ROM%; sudo perfnorm</command>
       <platform>pc</platform>
       <theme>maialinux</theme>
       <manufacturer>Maia Platform</manufacturer>
       <release>2026</release>
       <hardware>computer</hardware>
   </system>
   ```
2. **Diretório de Lançamento (`/roms/maialinux/`)**:
   * Contém `Launch MaiaLinux (LXQt).sh` e metadados em `gamelist.xml`.
   * Inclui arte dedicada (`maialinux.png`) exibida no carrossel.
3. **Temas**:
   * Os temas do EmulationStation em `/home/ark/.emulationstation/themes` apontam via link simbólico para `/roms/themes/`.
   * O tema `es-theme-nes-box` possui suporte nativo ao sistema `maialinux` com ícone personalizado e papel de parede oficial.

---

## 5. Ambiente Desktop LXQt e Correções de Usabilidade

### 5.1 Eliminação do Erro de Protetor de Tela (Screensaver) no Botão Power
**Problema Original**: Ao pressionar o botão físico de Power no LXQt, o dispositivo entrava em suspensão, mas exibia uma janela de erro informando que o screensaver não estava em execução (`Screensaver not running`).

**Causa Raiz**: O daemon `lxqt-session` monitora o evento de suspensão do `systemd-logind` (`PrepareForSleep`) e tenta bloquear a tela chamando `xdg-screensaver lock`. Como o pacote `xscreensaver` não está instalado no sistema, o script falhava e gerava a mensagem de erro.

**Solução Aplicada**:
1. Em `/home/ark/.config/lxqt/session.conf` e `/etc/xdg/lxqt/session.conf`:
   ```ini
   [General]
   lock_screen_before_power_actions=false
   lock_command=/bin/true
   ```
2. Em `/home/ark/.config/lxqt/power.conf`:
   ```ini
   [General]
   lock_screen=false
   lockScreenOnSuspend=false
   ```
3. Em `/etc/xdg/autostart/lxqt-xscreensaver-autostart.desktop`:
   Adicionada a diretiva `Hidden=true`.
4. Criados manipuladores fictícios (`dummy scripts`) em `/usr/local/bin/xscreensaver` e `/usr/local/bin/xscreensaver-command` retornando sempre status `0`.

### 5.2 Teclado Virtual para Programação (`matchbox-keyboard`)
**Problema Original**: O teclado virtual original possuía tamanho de teclas excelente para a tela de 640×480, mas não exibia linha de números nem símbolos de programação essenciais (`-`, `+`, `=`, `_`, `/`, `\`, `;`, `:`, `[`, `]`, `{`, `}`, `<`, `>`, etc.).

**Solução Aplicada**:
Foi desenvolvido um layout ergonômico de 4 linhas e 50 teclas em `/home/ark/.matchbox/keyboard.xml`, com as seguintes características:
* **Linha 1 (Números e Operadores Diretos)**: `1 2 3 4 5 6 7 8 9 0 - = [⇦ Backspace]`
* **Linha 2**: `[Tab] q w e r t y u i o p [⏎ Enter]`
* **Linha 3**: `[Esc] a s d f g h j k l ; '`
* **Linha 4**: `[⇧ Shift] z x c v b n m , . / [?123] [ Espaço ]`
* **Camada de Símbolos (`?123` / Mod1)**: Ativa instantaneamente todos os símbolos de codificação (`[ ]`, `{ }`, `< >`, `|`, `\`, `~`, '`', `!`, `@`, `#`, `$`, `%`, `^`, `&`, `*`, `_`, `+`, `:`, `"`, `?`).
* **Dimensões e Posicionamento**:
  - No Openbox (`/home/ark/.config/openbox/lxqt-rc.xml`), a janela do teclado é fixada em `x=0`, `y=280`, `largura=640`, `altura=180`.
  - Cada tecla possui proporções confortáveis (~49×45 pixels), ideais para toque direto ou navegação pelo analógico com o `gptokeyb`.

---

## 6. Procedimentos de Manutenção e Atualização

### Atualizando o Logotipo do Kernel:
1. Coloque a imagem desejada em formato PNG (`640x480`).
2. Execute no computador host:
   ```bash
   python3 /home/roberto/projects/maialinux/scripts/host/generate-custom-kernel-image.py \
       --logo /caminho/para/nova-imagem.png \
       --output /media/roberto/dArkOS_Fat/Image
   ```
3. Execute `sync` antes de ejetar o cartão SD.

### Restaurando a Partição 2 em Caso de Emergência:
Se por engano a partição 2 for sobrescrita por scripts legados, restaure-a com a imagem original limpa:
```bash
sudo dd if=/home/roberto/projects/maialinux/config/boot/resource_darkos_original.img of=/dev/sdX2 bs=4M status=progress conv=fsync
```
*(Substitua `/dev/sdX2` pelo identificador correto do cartão SD no host)*.

