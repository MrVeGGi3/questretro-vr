# Descrição da página da itch.io

Para colar no corpo da página. Inglês primeiro — é o público que baixa sideload de
Quest —, português abaixo.

## Tagline

O campo curto, que aparece embaixo do título na busca e na vitrine:

```
An arcade that fits in your bedroom — SNES, N64, Mega Drive, Sega CD and DS
```

Escolhido por fazer duas coisas de uma vez: dá uma imagem na cabeça (é o que faz
clicar) e nomeia os consoles (é o que a busca indexa). A abertura da descrição abaixo
foi escrita para **entregar** essa promessa na primeira linha — se o tagline mudar, a
abertura muda junto, senão a página promete uma coisa e começa com outra.

Em português, se um dia a página for traduzida:

```
Um fliperama que cabe no seu quarto — SNES, N64, Mega Drive, Sega CD e DS
```

---

**A VR-native emulator for the Meta Quest.** Your game runs on a screen you resize
from handheld to cinema — floating in an arcade hall, alone in the dark, or in
passthrough, in your actual bedroom.

Five consoles: **SNES, Nintendo 64, Mega Drive, Sega CD and Nintendo DS.**

### No computer needed after install

Grant file access, download a core from the menu's Cores page, drop your ROMs in any
folder on the headset. That's it. No `adb`, no PC, no cable.

### What it does that a flat emulator can't

- **A flight yoke for Star Fox 64** — both hands' poses map onto the stick axes.
- **The DS stylus is your pointing laser**, with the two screens as separate objects
  in space: top one large and far, bottom one close and tilted back, like a console
  resting in your hands.
- **Three rooms** — empty void, an arcade hall built entirely in code, or passthrough.
- **A game library, not a file list.** It scans your headset, cleans up titles from
  filenames and groups by console. Bad dumps get flagged, not hidden.
- **Per-cartridge control profiles** — the Star Fox map doesn't follow you into
  Mario 64.
- **Save states with thumbnails**, undo-on-delete, and battery saves in RetroArch's
  format, so your saves travel both ways.

Left-handed? One row in the Input tab moves the stylus and the menu laser. Speaks
English and Portuguese, and starts in your headset's language without being asked.

### It ships no cores and no ROMs, on purpose

The emulation cores are third-party and their licenses don't coexist in one package.
So this app does what RetroArch does — it's a host that loads a core **you** obtained
— and the Cores page fetches each one from libretro's official buildbot, at your
request, showing the license before downloading. ROMs are someone else's work and you
use your own.

That's also the only thing here that touches the network. Nothing is ever uploaded:
no telemetry, no account, no server.

### Notes

- Built and measured on **Quest 3S**. Quest 2/3 should work and weren't measured.
- N64 uses the software renderer on the headset — GLideN64 crashes on the Adreno.
  Star Fox 64 runs smooth.
- Sega CD needs the Mega CD BIOS, which is Sega's and can't ship here.

Free and open source (MIT). Code, full reasoning and issues:
<https://github.com/MrVeGGi3/questretro-vr>

---

## Português

**Emulador VR-nativo para Meta Quest.** O jogo roda numa tela que você redimensiona
de portátil a cinema — dentro de um salão de arcade, sozinho no escuro, ou em
passthrough, no seu quarto de verdade.

Cinco consoles: **SNES, Nintendo 64, Mega Drive, Sega CD e Nintendo DS.**

### Nenhum passo precisa de computador

Conceda o acesso aos arquivos, baixe um core pela página Cores do menu, e ponha suas
ROMs em qualquer pasta do headset. Só isso. Sem `adb`, sem PC, sem cabo.

### O que ele faz que emulador de tela plana não faz

- **O guidão de nave do Star Fox 64** — a pose das duas mãos vira os eixos do manche.
- **A caneta do DS é o seu laser**, com as duas telas como objetos separados no
  espaço: a de cima grande e longe, a de baixo perto e inclinada, como um console
  apoiado nas mãos.
- **Três salas** — o vazio, um salão de arcade construído em código, ou passthrough.
- **Uma biblioteca de jogos, não uma lista de arquivos.** Varre o headset, limpa o
  título do nome do arquivo e agrupa por console. Dump ruim é sinalizado, não
  escondido.
- **Perfil de controle por cartucho** — o mapa do Star Fox não vai junto para o
  Mario 64.
- **Save states com miniatura**, desfazer ao apagar, e saves de bateria no formato do
  RetroArch, que vão e voltam.

Canhoto? Uma linha na aba Input move a caneta e o laser do menu. Fala português e
inglês, e abre na língua do headset sem ninguém pedir.

### Não traz core nem ROM, de propósito

Os cores são de terceiros e as licenças deles não convivem num mesmo pacote. Então o
app faz o que o RetroArch faz — é um host que carrega um core que **você** obteve — e
a página Cores busca cada um do buildbot oficial da libretro, a seu pedido, mostrando
a licença antes de baixar. ROMs são obra de terceiros e você usa as suas.

É também a única coisa aqui que usa rede. Nada é enviado a lugar nenhum: sem
telemetria, sem conta, sem servidor.

### Limites

- Feito e medido no **Quest 3S**. Quest 2/3 devem funcionar e não foram medidos.
- O N64 usa o renderizador por software no headset — o GLideN64 derruba o app na
  Adreno. Star Fox 64 roda fluido.
- O Sega CD precisa da BIOS do Mega CD, que é da Sega e não pode acompanhar.

Grátis e open source (MIT). Código, o raciocínio completo e as issues:
<https://github.com/MrVeGGi3/questretro-vr>
