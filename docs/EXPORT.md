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

O preset traz `permissions/read_external_storage=true`, que é o que põe
`android.permission.READ_EXTERNAL_STORAGE` no manifesto e deixa o navegador de
ROMs ler `/sdcard`. No Android 11+ o acesso por caminho de arquivo em
armazenamento compartilhado voltou a funcionar com essa permissão, então
`DirAccess` basta — sem MediaStore.

Não usamos `MANAGE_EXTERNAL_STORAGE`: ela não tem diálogo de runtime e exigiria
que a pessoa fosse até *Special app access* nas configurações do Quest.

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
adb push jogo.sfc /sdcard/Download/
```

O navegador do app oferece `/sdcard/Download`, `/sdcard/ROMs`, `/sdcard` e a
pasta de dados do app. Sem a permissão concedida, só a última funciona.

## Pendências conhecidas

- **Core carregado no Android**: `EmuCore._preparar_core()` copia o `.so` de
  `res://` para `user://` porque `dlopen` não abre de dentro do APK. Testar em
  device.
- **Remap de input**: a página de Input mostra o mapa do controle mas ainda não
  deixa remapear (ver o comentário em `ui/paginas/pag_input.gd`). Zona morta do
  D-pad já é ajustável.
- **Integração com `romkeep`**: prevista para depois desta fase.
