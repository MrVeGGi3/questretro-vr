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

## Baixar um core (ex: SNES)

```bash
cd app/cores
curl -fsSL -O https://buildbot.libretro.com/nightly/linux/x86_64/latest/snes9x_libretro.so.zip
unzip snes9x_libretro.so.zip && rm snes9x_libretro.so.zip
```

## Rodar

**Teste headless** (prova extensão + carga do core; ROM opcional):

```bash
godot --headless --path app --import           # 1ª vez, para escanear a GDExtension
godot --headless --path app -s res://test_load.gd -- --rom /caminho/jogo.sfc
```

**Cena desktop** (vídeo na tela + áudio + teclado):

```bash
godot --path app -- --rom /caminho/jogo.sfc
```

Teclado: setas = D-pad, `Z`/`X` = B/A, `A`/`S` = Y/X, `Q`/`W` = L/R,
`Enter` = Start, `Shift` = Select.

## ROMs

**Não** versionamos ROMs (direitos autorais). Use as suas. Integração futura com
o catálogo `romkeep` está prevista na Fase 2.

## Roadmap

- **Fase 0 ✅** — GDExtension libretro rodando no Godot desktop.
- **Fase 1** — cena OpenXR, quad redimensionável com o framebuffer, APK Quest 3S,
  input dos controllers Touch.
- **Fase 2** — mapeamento pose→eixo por jogo (controles físicos), core N64
  (Star Fox 64), integração com `romkeep`, salas/arcade virtual.
