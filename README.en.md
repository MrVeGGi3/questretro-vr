# questretro-vr

*[Português](README.md) · **English***

A **VR-native** emulator for the Meta Quest 3S, built in **Godot 4** on top of
**libretro** cores. The game runs on a screen you resize from handheld to cinema,
inside a room — or in passthrough, in your actual bedroom.

Five consoles: **SNES, Nintendo 64, Mega Drive, Sega CD and Nintendo DS**.

> **The app is self-sufficient inside the headset.** Emulation cores download from
> the menu's Cores page, and you drop ROMs in any folder on the Quest. After the
> APK is installed, no step requires a computer.

This English README covers everything you need to install, play, build and
contribute. The [Portuguese README](README.md) is the primary one and goes deeper
on the reasoning behind each design decision — it is where the long-form notes
live.

## Install and play

1. **Install the APK** from [Releases](https://github.com/MrVeGGi3/questretro-vr/releases),
   via SideQuest or `adb install questretro-vr-release.apk`.
2. **Grant file access.** Open the menu (hold the left controller's menu button for
   0.5 s), go to **ROMs** and tap **"Allow access"**; in the Android settings that
   open, find QuestRetro and flip the switch.

   **This step is not optional and it is the one that confuses people most.**
   Without it the app sees neither your games nor your cores — and because cores and
   ROMs live in `/sdcard`, outside the app, they **stay there** if you reinstall
   while the permission resets. The result looks like an app that lost everything
   and only needs the switch turned back on.
3. **Download a core** from the menu's **Cores** tab. One per console, each with its
   license shown before the download button. The APK ships none, and
   [THIRD-PARTY.md](THIRD-PARTY.md) explains why.
4. **Drop your ROMs** in any folder on the headset — `Download` works fine. The
   **ROMs** tab scans storage and builds a list of games.
5. **Play.** Hold the menu button to open the panel at any time; a short tap is Start.

Sega CD is the only system that needs one extra file: the Mega CD BIOS, in
`/sdcard/QuestRetro/system/`. The app cannot download it — it is Sega's.

**Language:** the app speaks English and Portuguese, and starts in the headset's
language without being asked. To switch by hand: **Screen** tab, first row.
It applies immediately, no restart.

**Left-handed?** **Input** tab, first row, "Pointing hand". Moves the DS stylus and
the menu laser to the left hand, also immediately.

## What this APK deliberately does not ship

**No emulation cores and no ROMs.**

The cores are third-party and their licenses do not coexist in a single package:
snes9x and genesis_plus_gx forbid commercial use, mupen64plus-next and melonDS are
GPL, and Meta's OpenXR loader inside the APK is proprietary. Shipping them together
would require publicly defending an argument we would rather not have to defend. So
the app does what RetroArch does — it is a host that `dlopen`s a core **you**
obtained — and the Cores page fetches each one from libretro's official buildbot, at
your request, showing the license before downloading.

Two rules follow from that analysis and hold as behavior: the download is **always
requested**, never automatic, and the license appears **before** the button.

This is also the only thing in the app that touches the network. The `INTERNET`
permission exists for it alone, and nothing is ever sent anywhere.

ROMs are someone else's work and you use your own.

The full reasoning, piece by piece, is in [THIRD-PARTY.md](THIRD-PARTY.md).

## Highlights

- **A game library, not a file list.** The app scans headset storage, cleans up
  titles from filenames (collection numbering, region and language tags,
  `Legend of Zelda, The`-style trailing articles) and groups by console, with
  **Continue** and **Favorites** on top. Bad dumps (No-Intro's `[b]`) are flagged
  with a `△` rather than hidden, because such a ROM crashes and corrupts in ways
  that look like an emulator bug.
- **Per-cartridge physical controls.** The N64 *flight yoke* maps both hands' poses
  onto the stick axes, and the DS stylus is the pointing laser itself. Buttons are
  remappable, with a per-game profile — the Star Fox map does not follow you into
  Mario 64.
- **Save states with thumbnails** and undo-on-delete, plus battery SRAM saved
  automatically (every second, in RetroArch's `.srm` format, so saves travel both
  ways).
- **Three room modes**, one of them an arcade hall built entirely in code, with
  vertex-painted lighting and no assets. Measured on the Quest 3S: it costs no fps.
- **BIOS without `adb`**: Sega CD looks for the BIOS in `/sdcard/QuestRetro/system`,
  a folder that appears on its own and that you can reach from the Quest's own file
  manager.
- **Two screens for the DS**, as separate objects in space — the top one large and
  far, the bottom one close and tilted back, like a console resting in your hands.

## Controls in the headset

The mapping changes with the ROM's system. On **SNES** and **Mega Drive**, the left
stick becomes a digital D-pad (angular sectors, adjustable dead zone) and the right
stick resizes the screen. On **N64** both sticks are real axes — the left is the
stick, the right is the C-buttons, which the core exposes as a second stick — so the
screen is adjusted from the Screen page's sliders instead.

On **Nintendo DS**, the right trigger starts mapped to **Nothing** on purpose: it is
the stylus tip touching down, and mapping it to R would press R on every tap.

## Building

### GDExtension (desktop)

Requirements: `cmake`, `g++`, and `godot-cpp` cloned.

```bash
cd libretrogd
git clone --depth 1 --branch 4.5 https://github.com/godotengine/godot-cpp.git
for T in template_debug template_release; do
  cmake -S . -B build-linux-$T -DGODOTCPP_TARGET=$T -DCMAKE_BUILD_TYPE=Release
  cmake --build build-linux-$T -j"$(nproc)"
done
# produces: app/bin/libretrogd.linux.template_{debug,release}.x86_64.so
```

**`GODOTCPP_TARGET` is not optional, and `CMAKE_BUILD_TYPE` does not replace it.**
The first picks the godot-cpp API variant; the second only enables optimization.
`GODOTCPP_TARGET` defaults to `template_debug`, so passing only
`-DCMAKE_BUILD_TYPE=Release` gets you a *debug* binary — which works in the editor
and in the debug APK, and kills the app at release startup with a SIGSEGV inside the
engine and no extension frame in the backtrace.

### Cores, for desktop development

```bash
cd app/cores
B=https://buildbot.libretro.com/nightly/linux/x86_64/latest
curl -fsSL -O $B/snes9x_libretro.so.zip                 # SNES
curl -fsSL -O $B/mupen64plus_next_libretro.so.zip       # N64
curl -fsSL -O $B/genesis_plus_gx_libretro.so.zip        # Mega Drive + Sega CD
curl -fsSL -O $B/melonds_libretro.so.zip                # Nintendo DS
unzip -o '*.so.zip' && rm -f *.so.zip
```

On the headset you do not need any of this — use the Cores page.

### Running without a headset

```bash
godot --headless --path app --import    # first time, to scan the GDExtension
godot --headless --xr-mode off --path app -s res://scripts/testes/test_load.gd -- --rom /path/game.sfc
godot --xr-mode off --path app -- --rom /path/game.sfc   # desktop scene, video + audio + keyboard
```

`--xr-mode off` is not optional: the project enables OpenXR, and neither outcome
works — **without** an active runtime the loader hangs at startup and Godot never
reaches the script (printing nothing); **with** one, the test becomes a headset
session.

Keyboard: arrows = D-pad, `Z`/`X` = B/A, `A`/`S` = Y/X, `Q`/`W` = L/R,
`Enter` = Start, `Shift` = Select.

### Android APK

See [docs/EXPORT.md](docs/EXPORT.md) (Portuguese) and `tools/exportar-release.sh`.

## Adding a language

One more column in [`app/traducoes/ui.csv`](app/traducoes/ui.csv) and one entry in
`Idioma.LOCALES`/`ROTULOS` (`app/scripts/ui/idioma.gd`). No code changes: the keys
live in the Controls' `.text` and the engine translates at draw time, so new text
shows up on its own.

Portuguese is a translation like any other — there is no language baked into the
code, and that is what makes a third language cost the CSV and nothing else.
`test_ui` fails on a key missing a translation in any language, and on a key that
reaches the screen untranslated; `test_sala` does the same for the label under the
screen, whose messages never pass through the panel and so escaped that test.

## Why Godot, godot-cpp 4.5, libretro cores

- **Godot**: FOSS, mature Quest support (OpenXR 1.1, `godot-openxr-vendors`), and
  the editor runs natively on the Quest. Unity would only win on official samples.
- **godot-cpp 4.5**: newest stable release; GDExtension is forward-compatible
  (`compatibility_minimum = 4.5`), so it loads in Godot 4.6/4.7 without a rebuild.
- **libretro**: do not reinvent emulation. One `.so` per system — almost:
  `genesis_plus_gx` covers Mega Drive and Sega CD by itself, which is why the two
  are a single system here. Four cores for five consoles.

## Project layout

```
libretrogd/    C++ GDExtension hosting libretro cores
app/           Godot project — cenas/ (scenes), scripts/ (by subject), traducoes/
docs/          EXPORT.md: the Android/Quest trail, in Portuguese
tools/         exportar-release.sh: signed release build
```

Scenes and scripts live in separate trees on purpose: opening a `.tscn`, its script
sits at the mirrored path under `scripts/` — `cenas/vr_main.tscn` uses
`scripts/vr/xr_main.gd`.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Issues and pull requests in English or
Portuguese are equally welcome.

## License

MIT — see [LICENSE](LICENSE).

Everything that is not this project's own work is listed in
[THIRD-PARTY.md](THIRD-PARTY.md), with the license and origin of each piece. No
libretro core, no ROM and no BIOS is distributed or versioned here.
