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
   curl -fsSL -O $B/mupen64plus_next_gles2_libretro_android.so.zip   # só para comparar
   unzip -o '*.so.zip' && rm -f *.so.zip
   ```
   No Android o mupen vem separado por versão de GL (`gles2`/`gles3`); o Quest
   usa o **gles3**. O nome não bate com o do desktop, por isso `EmuCore.CORES`
   escreve os dois por extenso em vez de montar por sufixo.

   O `gles2` não é usado por padrão — está aí porque o `include_filter` leva
   `cores/*_android.so` inteiro, e com ele no APK dá para comparar as duas
   variantes pela chave `core` do `opcoes_core.cfg`, sem novo export.

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
- **GLideN64 derruba o app no Quest** — investigado a fundo e **sem solução por
  configuração**. Com `rdp-plugin=gliden64`, o Star Fox 64 morre no primeiro
  frame com `SIGSEGV` (null deref) dentro de `libGLESv2_adreno.so`, chamado pelo
  core:

  ```
  #00 __memcpy_aarch64_simd (libc)     x1 (origem) = 0x0, x2 (tamanho) = 0x40
  #01 libGLESv2_adreno.so +0x1b2a04
  #02 libGLESv2_adreno.so +0x1f6d60
  #03 libGLESv2_adreno.so +0x1f5908
  #04 libGLESv2_adreno.so +0x1c8b88
  #05 libGLESv2_adreno.so +0x1e2320
  #06 mupen64plus_next_..._libretro_android.so   <- daqui pra baixo, o core
  ```

  Os cinco quadros do driver são **byte a byte iguais em todas as execuções** —
  inclusive entre as variantes `gles2` e `gles3`, que são binários diferentes —
  enquanto os quadros do core mudam. É uma única chamada de GL, atingida de
  vários pontos do GLideN64, sempre com 64 bytes de dado nulo.

  O `memcpy` é chamado **pelo driver**, não pelo core: quem é nulo é o *dado*,
  não o ponteiro de função. Isso importa porque afasta a hipótese de resolução
  de símbolos — e, de todo modo, o core nem usa a nossa: ele linka direto contra
  `libGLESv3.so`/`libGLESv2.so` (102 símbolos `gl*` resolvidos pelo linker
  dinâmico), então `gl_funcs.cpp` nunca esteve nesse caminho.

  Também **não** é a causa, por eliminação feita no device: nosso FBO sobe
  (`hw render em FBO 640x480`), o `context_reset()` do core retorna limpo, a ROM
  abre a 640x480@60 e o dynarec inicia. Com `rdp-plugin=angrylion` — software
  puro, sem GL — o mesmo jogo roda fluido, grava `.srm` e responde ao controle.
  Ou seja: core, ROM, input, áudio, SRAM e o empréstimo de contexto estão de pé.

  Por isso `EmuCore.rdp_do_n64()` usa `angrylion` no Android e `gliden64` no
  desktop.

  **Descartados como causa** (cada um medido no Quest, com o crash inalterado):

  | hipótese | resultado |
  |---|---|
  | pasta de sistema faltando | era bug real, corrigido — não era o crash |
  | `EnableShadersStorage=False` | sem efeito (e o core nem declara a opção no Android) |
  | resolução de símbolos de GL | o core não usa a nossa; linka GL direto |
  | `EnableFBEmulation=False` | sem efeito — e isso já cobre as cópias para RDRAM, que são sub-recursos dela |
  | `EnableHWLighting=False` | sem efeito |
  | `MultiSampling=0` | sem efeito |
  | `EnableLODEmulation=False` | sem efeito |
  | `EnableTextureCache=False` | sem efeito |
  | `EnableLegacyBlending=True` | sem efeito |
  | `EnableFragmentDepthWrite=False` | sem efeito |
  | variante `gles2` do core | crash idêntico, mesmos quadros do driver |

  As oito opções acima foram aplicadas **todas de uma vez**, na configuração mais
  defensiva que o core aceita, e o crash saiu bit a bit igual ao da rodada com
  só uma delas. Não há combinação dessas opções que salve o GLideN64 aqui.

  **Quem voltar nisto** tem duas trilhas que não foram andadas: (1) rodar o
  GLideN64 no RetroArch do mesmo headset — se crashar igual, o bug é do core
  sobre a Adreno e não há nada nosso nele; se não crashar, o problema volta a
  ser o FBO/contexto que emprestamos; (2) um build do core com símbolos, que
  daria o nome da chamada de GL em vez do offset.

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
  configuração rodou. Opção que o core não declara vira aviso
  (`libretrogd: opção desconhecida: ...`) em vez de silêncio — foi assim que se
  viu que `EnableShadersStorage` e `EnableN64DepthCompare` nunca valeram no
  Android, apesar de existirem como texto dentro do `.so`.

  A chave reservada **`core`** escolhe o `.so` em vez de uma opção, e serve para
  comparar variantes do mesmo core sem export+install:
  ```bash
  printf '[n64]\ncore="mupen64plus_next_gles2_libretro_android.so"\nmupen64plus-rdp-plugin="gliden64"\n' \
      > /tmp/oc.cfg
  adb push /tmp/oc.cfg /data/local/tmp/oc.cfg
  adb shell "run-as com.questretro.vr sh -c 'cat /data/local/tmp/oc.cfg > files/opcoes_core.cfg'"
  ```
  Vale só para `.so` que estejam no APK — o `include_filter` do preset leva
  `cores/*_android.so` inteiro, então basta ter baixado a variante antes do
  export. Nome que não existe vira aviso e cai no padrão, em vez de medir a
  variante errada em silêncio.
- **Lançar por `adb` exige controles ligados**: com eles desligados o Quest
  intercepta e mostra *controller required* — no logcat,
  `common_system_dialog_app_launch_blocked_controller_required`. Não é crash do
  app; é preciso estar de headset com os controles ativos.
- **Crash ao pausar**: o Godot segfalta em
  `GodotVulkanRenderView.lambda$onActivityPaused$0` (VkThread) quando o app é
  pausado — tirar o headset, ou subir por `adb` com o headset ocioso. Além de
  derrubar o app, torna o gatilho `NOTIFICATION_APPLICATION_PAUSED` não
  confiável: a SRAM depende da gravação periódica, não dele.

  **Suspeita de que esta pendência esteja vencida.** O rastro é de uma
  `GodotVulkanRenderView`, mas no logcat de hoje o nosso processo instancia
  `GLSurfaceView` e `OpenGLRenderer` — GL, como `project.godot` pede nas linhas
  19 e 24. (As linhas de Vulkan no log são do compositor do Horizon OS, pid
  separado, não nossas.) Isso encaixa com o crash ser **anterior** ao commit que
  pôs o Quest em `gl_compatibility`, quando o Android ainda subia em Vulkan.

  Não está confirmado: com o headset ocioso o app não chega a rodar de verdade —
  o `vrshell` fica com o foco e o nosso processo vai de `OnResume` a `OnPause`
  na hora —, então não dá para provocar a pausa de um app *em execução* por
  `adb`. Quem estiver de headset confirma em dez segundos: pausar e ver se o app
  sobrevive.

- **Janela de perda da SRAM**: como o app morre ao ser pausado, o que protege o
  progresso na prática é só a gravação periódica. `cenas/test_sram.tscn` mede o
  atraso entre o jogo salvar e os bytes chegarem ao disco; com o
  `INTERVALO_SRAM` de 5 s ele dava **4,9 s**, ou seja, a janela inteira.
  Baixado para 1 s (medido: **0,9 s**, tanto no SNES quanto no N64, cujo buffer
  é de 290 KB). Checar mais vezes é quase de graça — sem mudança a função sai na
  comparação de buffer, sem tocar no disco.

  Falta o veredito no headset, que é outra pergunta: salvar dentro do jogo,
  tirar o Quest da cabeça, reabrir e ver se o progresso está lá — uma vez com
  alguns segundos de folga e outra tirando o headset logo depois de salvar.
- **Save state do N64: conferido** (antes era a pendência de que a página de
  Saves oferecia os slots sem garantia). O estado **não repete byte a byte** —
  nem logo depois de restaurar, nem refazendo o mesmo trecho —, mas isso nunca
  provou defeito: o mupen roda uma `EmuThread` própria, o nosso `step()` não
  avança uma quantidade fixa de trabalho, e a comparação de bytes não distingue
  restauração ruim de core que não repete. A asserção era inconclusiva, não
  falsa. `test_ui.gd` segue pulando ela no N64 e mantendo no SNES.

  Quem confere agora é `cenas/test_estado.tscn`, que mede a **imagem** em vez
  dos bytes: grava, colhe uma janela de frames de referência, avança 180 frames,
  restaura e pergunta se o frame de volta cai na janela. Tudo em unidades de "o
  quanto um frame emulado muda", que o próprio teste mede na janela — assim o
  limiar não é calibrado por ROM.

  Medido no desktop, resíduo em frames de distância:

  | ROM | renderizador | restaurado | 180 frames depois |
  |---|---|---|---|
  | Star Fox 64 | `gliden64` | 0,0 | 107,3 |
  | Star Fox 64 | `angrylion` | 0,7 | 31,7 |
  | Super Mario 64 | `gliden64` | 0,1 | 4,0 |
  | Chrono Trigger (controle SNES) | — | 0,0 | 4,2 |

  A linha do `angrylion` não é zelo: é o renderizador que roda **no Quest**, e
  provar o save state só sob `gliden64` deixaria de fora justamente a
  configuração que vai para o headset. Rodou no desktop sem rebuild, pela
  sobrescrita de `user://opcoes_core.cfg` descrita acima.

  Com a restauração salteada de propósito, o Star Fox 64 dá 107,2 em vez de 0,0
  — a asserção reprova quando deve.

  Duas armadilhas que custaram caro e estão codificadas no teste, porque o
  controle do SNES reprovou com a restauração comprovadamente correta:

  1. **Onde gravar.** Num fade a distância entre imagens satura: na intro do
     Star Fox 64, dois frames vizinhos se afastam 0,018 enquanto 180 frames se
     afastam 0,026. Ali nenhum limiar significa nada. O teste tenta trechos em
     sequência e só aceita aquele em que o frame distante está mesmo distante.
  2. **Escolher olhando para trás não serve.** Um buscador que procura mudança
     acumulada nas amostras já vistas pousa sempre logo depois de um corte de
     cena — onde a mudança recente é enorme e não diz nada sobre o que vem. A
     escolha é feita medindo para a frente, o que também evita usar save state
     para decidir onde testar save state.

  E conferido **no headset**, que era a outra pergunta — o teste mede o
  framebuffer, não a experiência de gravar, jogar um trecho e voltar ao ponto
  com o controle respondendo. Com isso a pendência está fechada nas duas pontas:
  a medida no desktop e o uso no Quest.

- **Remap de input**: a página de Input mostra o mapa do controle mas ainda não
  deixa remapear (ver o comentário em `scripts/ui/paginas/pag_input.gd`). O que dá para
  ajustar são os contínuos: zona morta do D-pad (SNES) e o guidão de nave (N64).
- **Integração com `romkeep`**: prevista para depois desta fase.
