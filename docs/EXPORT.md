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
   # core
   cd ../app/cores
   curl -fsSL -O https://buildbot.libretro.com/nightly/android/latest/arm64-v8a/snes9x_libretro_android.so.zip
   unzip -o snes9x_libretro_android.so.zip && rm snes9x_libretro_android.so.zip
   ```

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

## Pendências conhecidas

- **Core carregado no Android**: `EmuCore._preparar_core()` copia o `.so` de
  `res://` para `user://` porque `dlopen` não abre de dentro do APK. ✅ Testado
  em device (Quest 3S).
- **Crash ao pausar**: o Godot segfalta em
  `GodotVulkanRenderView.lambda$onActivityPaused$0` (VkThread) quando o app é
  pausado — tirar o headset, ou subir por `adb` com o headset ocioso. Além de
  derrubar o app, torna o gatilho `NOTIFICATION_APPLICATION_PAUSED` não
  confiável: a SRAM depende da gravação periódica, não dele.
- **Remap de input**: a página de Input mostra o mapa do controle mas ainda não
  deixa remapear (ver o comentário em `ui/paginas/pag_input.gd`). Zona morta do
  D-pad já é ajustável.
- **Integração com `romkeep`**: prevista para depois desta fase.
