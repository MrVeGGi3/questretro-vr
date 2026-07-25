# questretro-vr

Emulador **VR-nativo** para Meta Quest 3S, feito em **Godot 4** com cores
**libretro**. Diferenciais de projeto: tela redimensionável (de portátil a
cinema gigante) e controles físicos por jogo (ex: "guidão de nave" pro Star Fox).

> Status: **Fase 0 concluída** — o pipeline de emulação (GDExtension + core
> libretro) carrega e roda dentro do Godot no desktop. Fase 1 (cena VR + APK
> Quest) é o próximo passo. Ver `docs/` e o plano.

## Estrutura

```
libretrogd/        GDExtension C++ que hospeda cores libretro
  src/
    libretro.h         header oficial da API libretro (licença ISC)
    libretro_host.*    classe LibretroHost: dlopen do core, callbacks, frame loop
    register_types.*   registro da classe no Godot
  CMakeLists.txt       build (usa godot-cpp branch 4.5)
  godot-cpp/           dependência clonada (não versionada)
app/               projeto Godot
  libretrogd.gdextension
  main.tscn / main.gd  cena de teste desktop (Fase 0)
  test_load.gd         teste headless do pipeline
  bin/                 .so da GDExtension (gerado)
  cores/               cores libretro .so (baixados; não versionados)
cores/             (reservado)
docs/
```

## Por que Godot (e não Unity), godot-cpp 4.5, cores libretro

- **Godot**: FOSS, suporte Quest maduro (OpenXR 1.1, `godot-openxr-vendors`),
  editor roda nativo no Quest. Unity só ganharia em samples oficiais.
- **godot-cpp 4.5**: é a release estável mais nova; GDExtension é
  forward-compatible (`compatibility_minimum = 4.5`), então carrega no Godot
  4.6/4.7 sem rebuild. Buildar contra `master` casaria a ABI do 4.7 mas é alvo
  móvel — sem ganho pro nosso uso.
- **libretro**: não reinventar emulação. Um core `.so` por sistema (snes9x no MVP).

## Build da GDExtension (desktop)

Pré-requisitos: `cmake`, `g++`, e o `godot-cpp` clonado.

```bash
cd libretrogd
git clone --depth 1 --branch 4.5 https://github.com/godotengine/godot-cpp.git   # se ainda não tiver
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j"$(nproc)"
# gera: app/bin/libretrogd.linux.x86_64.so
```

## Baixar os cores

```bash
cd app/cores
B=https://buildbot.libretro.com/nightly/linux/x86_64/latest
curl -fsSL -O $B/snes9x_libretro.so.zip                 # SNES
curl -fsSL -O $B/mupen64plus_next_libretro.so.zip       # N64
unzip -o '*.so.zip' && rm -f *.so.zip
```

O core sai da extensão da ROM (`EmuCore.core_para_rom`): `.smc/.sfc/.fig/.swc/.zip`
vão para o snes9x, `.z64/.n64/.v64` para o mupen64plus. Trocar de ROM entre
sistemas troca o `.so` sozinho, gravando a SRAM do jogo anterior antes.

O N64 desenha por GPU, num FBO que a GDExtension empresta ao core — ver
"Renderização por hardware" em `docs/EXPORT.md` para o que isso amarra.

## Rodar

**Teste headless** (prova extensão, carga do core e round-trip da SRAM; ROM opcional):

```bash
godot --headless --path app --import           # 1ª vez, para escanear a GDExtension
godot --headless --xr-mode off --path app -s res://test_load.gd -- --rom /caminho/jogo.sfc
```

`--xr-mode off` não é opcional nos testes, porque o projeto liga OpenXR e nenhum
dos dois desfechos serve: **sem** runtime ativo o loader trava no arranque e o
Godot nem chega a rodar o script (sem imprimir nada); **com** um runtime ativo o
teste vira uma sessão de headset.

**Cena desktop** (vídeo na tela + áudio + teclado):

```bash
godot --xr-mode off --path app -- --rom /caminho/jogo.sfc
```

> Sem o `--xr-mode off`, com o WiVRn ativo, o Godot entra em modo VR e
> **segfalta no primeiro frame estéreo** — dentro de `libopenxr_wivrn.so` +
> Mesa/gallium, com `gl_compatibility` numa Intel integrada. Reproduz 4/4 e é
> anterior aos saves de bateria (o HEAD limpo crasha igual). Testar em VR de
> verdade, por enquanto, é pelo APK no headset (`docs/EXPORT.md`).

Teclado: setas = D-pad, `Z`/`X` = B/A, `A`/`S` = Y/X, `Q`/`W` = L/R,
`Enter` = Start, `Shift` = Select.

## Controles no headset

O mapa muda com o sistema da ROM. No **SNES**, o analógico esquerdo vira D-pad
digital (por setores angulares, com zona morta ajustável) e o direito
redimensiona/aproxima a tela.

No **N64**, os dois analógicos são eixos de verdade: o esquerdo é o manche, o
direito são os C-buttons — que o core expõe como um segundo manche, não como
quatro botões. Com o direito ocupado, a tela se ajusta pelos sliders da página
Tela. Z fica no grip esquerdo, L/R nos gatilhos, A/B nos botões do controle
direito.

Esse mapa não é decorado: sai dos descritores que o próprio core declara
(`SET_INPUT_DESCRIPTORS`), e eles surpreendem — no N64, `JOYPAD_B` é o **A**.

## ROMs

**Não** versionamos ROMs (direitos autorais). Use as suas. Integração futura com
o catálogo `romkeep` está prevista na Fase 3.

Jogos com bateria gravam sozinhos em `user://saves/<jogo>.srm`, no mesmo formato
do RetroArch — dá para levar um save de lá para cá e vice-versa. A gravação é
automática (a cada 5 s, se algo mudou) e também ao trocar de ROM, ao fechar o app
e quando o Quest suspende a sessão. A página **Saves** do menu mostra o tamanho
da bateria e quando ela foi gravada pela última vez.

## Roadmap

- **Fase 0 ✅** — GDExtension libretro rodando no Godot desktop.
- **Fase 1 ✅** — cena OpenXR, quad redimensionável com o framebuffer, APK Quest 3S,
  input dos controllers Touch.
- **Fase 2 ✅** — menu in-VR: navegador de ROMs, configurações persistentes de
  tela/vídeo/áudio/input e save states.
- **Fase 3** — saves de bateria (SRAM) ✅; core N64 com renderização por
  hardware ✅ (verificado no desktop; falta medir no Quest); a seguir:
  mapeamento pose→eixo por jogo (controles físicos), integração com `romkeep`,
  salas/arcade virtual.

## Menu dentro do headset

Segure o **botão de menu** (controle esquerdo) por 0,5 s para abrir o painel;
toque curto continua valendo como Start. Aponte com o controle direito e use o
gatilho para clicar. As configurações ficam em `user://config.cfg` e sobrevivem
entre sessões.

No desktop, `Tab` abre o painel e o mouse interage direto — dá para iterar a UI
sem build e sideload.

Para ver as páginas do menu sem headset nenhum:

```bash
xvfb-run -a godot --xr-mode off --path app res://test_ui.tscn   # -> user://ui_*.png
```

Esse mesmo teste confere o caminho de clique do laser, o round-trip dos save
states e a persistência das configurações.

O `--xr-mode off` é obrigatório: o projeto liga OpenXR, e sem um runtime ativo
na máquina o Godot **trava no arranque** sob Xvfb, sem imprimir nada — parece
travamento do teste, mas é do motor.
