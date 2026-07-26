# Export do APK para o Meta Quest 3S

Ambiente já validado nesta máquina: Android SDK em `~/Android/Sdk`, **NDK r25c**
(`25.2.9519653`), **JDK 17** (`/usr/lib/jvm/java-17-openjdk-amd64`), templates de
export 4.6.3 e `debug.keystore` presentes. As editor settings do Godot já apontam
para o SDK e o JDK 17.

## Pré-requisitos do projeto (uma vez)

1. **Addon** `godotopenxrvendors` em `app/addons/` (copiado do VeG-Orbit-Sim).
   Os binários ficam em `.bin/` (não versionados).
2. **Template de build Android** extraído em `app/android/build/`
   (equivale ao botão *Project > Install Android Build Template*):
   ```bash
   unzip -o ~/.local/share/godot/export_templates/4.6.3.stable.mono/android_source.zip -d app/android/build
   printf '4.6.3.stable.mono' > app/android/.build_version
   : > app/android/build/.gdignore
   ```
3. **Extensão arm64** e **core android** presentes:
   ```bash
   # extensão
   cd libretrogd
   NDK=~/Android/Sdk/ndk/25.2.9519653
   cmake -S . -B build-android \
     -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" \
     -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-29 -DCMAKE_BUILD_TYPE=Release
   cmake --build build-android -j"$(nproc)"   # -> app/bin/libretrogd.android.arm64.so
   # cores
   cd ../app/cores
   B=https://buildbot.libretro.com/nightly/android/latest/arm64-v8a
   curl -fsSL -O $B/snes9x_libretro_android.so.zip
   curl -fsSL -O $B/mupen64plus_next_gles3_libretro_android.so.zip
   unzip -o '*.so.zip' && rm -f *.so.zip
   ```
   No Android o mupen vem separado por versão de GL (`gles2`/`gles3`); o Quest
   usa o **gles3**. O nome não bate com o do desktop, por isso `EmuCore.CORES`
   escreve os dois por extenso em vez de montar por sufixo.

## Gerar o APK

```bash
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
export ANDROID_HOME=~/Android/Sdk ANDROID_SDK_ROOT=~/Android/Sdk
godot --headless --path app --export-debug "Quest (Meta)" "$PWD/dist/questretro-vr.apk"
```

O preset `Quest (Meta)` (em `app/export_presets.cfg`) já traz:
`gradle_build=true`, `arm64-v8a`, `xr_mode=1`, `enable_meta_plugin=true`,
suporte a Quest 2/3/Pro, `min_sdk=24`, `target_sdk=32`.

O `exclude_filter` tira o core/extensão de desktop; o `include_filter` garante o
core android e a ROM demo (`roms/demo.smc`, homebrew freeware) no pacote.

## Sideload no Quest 3S

```bash
adb install -r dist/questretro-vr.apk
```

O app aparece em *Apps > Origens desconhecidas* no headset.

## Verificar o APK (opcional)

```bash
AAPT2=$(ls ~/Android/Sdk/build-tools/*/aapt2 | head -1)
"$AAPT2" dump xmltree --file AndroidManifest.xml dist/questretro-vr.apk | grep -iE 'oculus|headtracking|IMMERSIVE'
```
Deve listar `android.hardware.vr.headtracking`, `com.oculus.intent.category.VR`
e `org.khronos.openxr.intent.category.IMMERSIVE_HMD`.

## Permissão de armazenamento

`READ_EXTERNAL_STORAGE` **não serve** para ler ROMs. No Android 11+ ela só dá
acesso a **mídia** (imagem, áudio, vídeo); um `.sfc` não é mídia, então o app
leva `Permission denied` em `/sdcard` inteiro mesmo com a permissão concedida —
medido no Quest 3S. O próprio Godot denuncia isso no manifesto, onde ela sai
com `maxSdkVersion='29'`:

```bash
AAPT2=$(ls ~/Android/Sdk/build-tools/*/aapt2 | head -1)
"$AAPT2" dump permissions dist/questretro-vr.apk
# uses-permission: name='android.permission.READ_EXTERNAL_STORAGE' maxSdkVersion='29'
# uses-permission: name='android.permission.MANAGE_EXTERNAL_STORAGE'
```

Quem destrava tipo de arquivo arbitrário é `MANAGE_EXTERNAL_STORAGE`, no preset
via `permissions/custom_permissions`. Ela não tem diálogo de runtime: o botão
"Permitir acesso" da página de ROMs abre a tela do Android por intent, e a
pessoa liga a chave uma vez. Detalhes que custaram tempo:

- A tela **por app** (`MANAGE_APP_ALL_FILES_ACCESS_PERMISSION`) **não existe no
  Quest** — resolve para "No activity found". Usamos a lista geral
  (`MANAGE_ALL_FILES_ACCESS_PERMISSION` → `Settings$ManageExternalStorageActivity`),
  então a pessoa cai numa lista e precisa achar *QuestRetro* nela.
- No `JavaClassWrapper` o construtor Java é exposto pelo **nome simples da
  classe**, não por `new`: `Intent.Intent(acao)` é o `new Intent(action)`.
  Chamar `.new()` dá `Nonexistent function 'new' in base 'JavaClass'`.
- Conferir o estado sem entrar no headset:
  ```bash
  adb shell appops get com.questretro.vr MANAGE_EXTERNAL_STORAGE   # allow / default
  ```

## ROMs sem mexer em permissão

`/sdcard/Android/data/com.questretro.vr/files/roms` é lida pelo app sem
permissão alguma e recebe `adb push` direto — é a raiz "Pasta do app (adb)" do
navegador:

```bash
adb push jogo.sfc /sdcard/Android/data/com.questretro.vr/files/roms/
```

Não serve para quem copia por cabo USB: o Android esconde `Android/data` do MTP
e do gerenciador de arquivos do headset. Para esse caso, só a permissão acima.

> O caminho é montado a partir de `NavegadorRoms.PACOTE`, que precisa casar com
> `package/unique_name` do preset — o Godot 4.6 não expõe o nome do pacote em
> runtime.

> **Cuidado ao editar `export_presets.cfg` à mão**: o `ConfigFile` do Godot trata
> `;` como comentário, não `#`. Uma linha com `#` faz o parse da seção parar ali,
> e as chaves seguintes somem silenciosamente — o export roda sem erro e a
> permissão simplesmente não aparece no manifesto. Conferir com:
> ```bash
> AAPT2=$(ls ~/Android/Sdk/build-tools/*/aapt2 | head -1)
> "$AAPT2" dump permissions dist/questretro-vr.apk
> ```

## Copiar ROMs para o headset

```bash
adb push jogo.sfc /sdcard/Download/     # exige MANAGE_EXTERNAL_STORAGE ligada
```

O navegador oferece `/sdcard/Download`, `/sdcard/ROMs`, `/sdcard`, a pasta
externa do app e a pasta de dados. Sem a permissão ligada, só as duas últimas
funcionam — e a de dados (`user://roms`) não é alcançável de fora sem `run-as`,
o que só existe em build de debug.

## Renderização por hardware (cores de N64)

O mupen64plus não produz framebuffer de software: ele desenha por GPU. O
`LibretroHost` atende `SET_HW_RENDER` emprestando ao core o **contexto GL do
próprio Godot** e um FBO nosso; `run_frame()` salva o alvo de render, binda o
FBO, chama `retro_run` e devolve tudo.

Três coisas presas a isso, que quebram em silêncio se mudarem:

- **`renderer/rendering_method="gl_compatibility"`** em `project.godot`. É o que
  torna o contexto compartilhável. No renderer Mobile (Vulkan) nada disto vale.
- **Thread principal**: `step()` sai de `_process`, que no gl_compatibility roda
  na mesma thread que tem o contexto corrente. Ligar o modo de renderização
  multi-thread quebra a premissa.
- **Devolver o alvo de render** depois do `retro_run` não é zelo: sem isso o
  Godot desenha o frame seguinte dentro do FBO do emulador.

`gl_funcs.cpp` resolve as funções de GL por `dlsym` em vez de incluir header,
porque desktop (`GL/gl.h`) e Android (`GLES3/gl3.h`) brigam por tipos e por
ligação. Se a resolução falhar, `SET_HW_RENDER` é recusado e o core cai no
renderizador de software dele.

Conferir qual caminho está valendo:

```bash
adb logcat | grep -i "hw render"     # "libretrogd: hw render em FBO 640x480"
```

## Pendências conhecidas

- **Core carregado no Android**: `EmuCore._preparar_core()` copia o `.so` de
  `res://` para `user://` porque `dlopen` não abre de dentro do APK. ✅ Testado
  em device (Quest 3S).
- **GLideN64 derruba o app no Quest**: com `rdp-plugin=gliden64`, o Star Fox 64
  morre no primeiro frame com `SIGSEGV` (null deref) dentro de
  `libGLESv2_adreno.so`, chamado pelo core. O rastro é um `memcpy` de 64 bytes
  com origem nula — o tamanho de uma matriz 4x4.

  O que **não** é a causa, por eliminação já feita no device: nosso FBO sobe
  (`hw render em FBO 640x480`), o `context_reset()` do core retorna limpo, a ROM
  abre a 640x480@60 e o dynarec inicia. Com `rdp-plugin=angrylion` — software
  puro, sem GL — o mesmo jogo roda fluido, grava `.srm` e responde ao controle.
  Ou seja: core, ROM, input, áudio, SRAM e o empréstimo de contexto estão de pé;
  o problema é o GLideN64 sobre o driver da Adreno.

  Por isso `EmuCore.OPCOES` usa `angrylion` no Android e `gliden64` no desktop.

  Já descartados como causa: pasta de sistema faltando (era bug real, corrigido)
  e cache de shaders em disco (`EnableShadersStorage=False` não mudou nada).
  A investigar: `EnableFBEmulation=False`, desligar as cópias de cor/profundidade
  para a RDRAM, e a variante `gles2` do core.

- **Testar opções de core sem rebuild**: `user://opcoes_core.cfg` sobrescreve
  `EmuCore.OPCOES`, uma seção por sistema. No Android o `user://` é a pasta
  **interna** do app — `/sdcard/Android/data/...` é outra coisa —, então só se
  escreve por `run-as`, e só em build de debug:
  ```bash
  adb shell "run-as com.questretro.vr sh -c \
      'printf \"[n64]\nmupen64plus-rdp-plugin=\\\"gliden64\\\"\n\" > files/opcoes_core.cfg'"
  adb shell run-as com.questretro.vr cat files/opcoes_core.cfg   # conferir
  ```
  O app imprime no log cada opção que leu do arquivo, para o teste dizer com que
  configuração rodou.
- **Lançar por `adb` exige controles ligados**: com eles desligados o Quest
  intercepta e mostra *controller required* — no logcat,
  `common_system_dialog_app_launch_blocked_controller_required`. Não é crash do
  app; é preciso estar de headset com os controles ativos.
- **Crash ao pausar**: o Godot segfalta em
  `GodotVulkanRenderView.lambda$onActivityPaused$0` (VkThread) quando o app é
  pausado — tirar o headset, ou subir por `adb` com o headset ocioso. Além de
  derrubar o app, torna o gatilho `NOTIFICATION_APPLICATION_PAUSED` não
  confiável: a SRAM depende da gravação periódica, não dele.
- **Remap de input**: a página de Input mostra o mapa do controle mas ainda não
  deixa remapear (ver o comentário em `ui/paginas/pag_input.gd`). Zona morta do
  D-pad já é ajustável.
- **Integração com `romkeep`**: prevista para depois desta fase.
