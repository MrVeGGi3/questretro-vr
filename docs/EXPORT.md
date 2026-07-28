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

   **E o passthrough no manifesto** — `app/android/` é gitignored, então isto se
   perde num clone novo e o modo Passthrough para de funcionar sem erro nenhum
   no build (o runtime só passa a oferecer OPAQUE). Ver "Passthrough" nas
   pendências para por que não sai da opção do preset:
   ```bash
   python3 - <<'PY'
   from pathlib import Path
   p = Path("app/android/build/src/main/AndroidManifest.xml")
   s = p.read_text()
   if "com.oculus.feature.PASSTHROUGH" not in s:
       alvo = '        android:required="true" />'
       s = s.replace(alvo, alvo + """

    <!-- Passthrough (modo Sala). À mão porque o godotopenxrvendors 5.1.0 não
         emite o bloco de elemento de topo. required="false": o app roda sem. -->
    <uses-feature
        tools:node="replace"
        android:name="com.oculus.feature.PASSTHROUGH"
        android:required="false" />""", 1)
       p.write_text(s)
       print("manifesto: PASSTHROUGH adicionado")
   else:
       print("manifesto: PASSTHROUGH já estava lá")
   PY
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
- **Crash ao pausar: não reproduz mais.** O registro antigo era um segfault em
  `GodotVulkanRenderView.lambda$onActivityPaused$0` (VkThread) ao pausar, que
  além de derrubar o app tornava o `NOTIFICATION_APPLICATION_PAUSED` não
  confiável.

  Medido de headset, em três pausas seguidas (tirar o Quest da cabeça): **nenhum
  `Fatal signal`, nenhum SIGSEGV, nenhum tombstone**. A saída é ordeira —
  `OnPause` → o nosso handler → `OnStop` → `onActivityDestroyed` → `OnDestroy` →
  o processo termina.

  O que explica: o crash era do tempo em que o Android subia em Vulkan. Hoje o
  log do device diz `OpenGL API OpenGL ES 3.2 ... Adreno (TM) 740`, ou seja
  `gl_compatibility` valendo como `project.godot` pede (linhas 19 e 24). As
  linhas de Vulkan que aparecem no logcat são do compositor do Horizon OS, de
  outro pid. O rastro antigo é anterior ao commit que fez essa troca.

  Duas consequências práticas. A primeira: **tirar o headset destrói a
  atividade**, não só pausa — o processo termina de vez, então não existe
  "voltar para onde estava"; a próxima sessão é um arranque novo. A segunda: o
  `APPLICATION_PAUSED` **chega até nós e dá tempo de agir** — a nossa linha sai
  4 ms depois da notificação e uns 70 ms antes do `OnStop`. Ele voltou a ser um
  gatilho de verdade, e não só um enfeite ao lado da gravação periódica.

- **Janela de perda da SRAM**: como o app morre ao ser pausado, o que protege o
  progresso na prática é só a gravação periódica. `cenas/test_sram.tscn` mede o
  atraso entre o jogo salvar e os bytes chegarem ao disco; com o
  `INTERVALO_SRAM` de 5 s ele dava **4,9 s**, ou seja, a janela inteira.
  Baixado para 1 s (medido: **0,9 s**, tanto no SNES quanto no N64, cujo buffer
  é de 290 KB). Checar mais vezes é quase de graça — sem mudança a função sai na
  comparação de buffer, sem tocar no disco.

  **Conferido no headset**, salvando dentro do Chrono Trigger:

  | 18:32:28 | pausa — `SRAM sem mudança` (nada salvo ainda) |
  |---|---|
  | **18:32:47,409** | o `.srm` é escrito: 8192 bytes, 41,5% não-zero |
  | 18:32:50 | pausa — `SRAM sem mudança`, 3 s depois da escrita |

  O save saiu do jogo por volta de 18:32:46 e estava em disco ~1 s depois. O
  `sem mudança` da segunda pausa não é ausência de save: é a prova de que a
  gravação periódica já tinha feito o trabalho antes de o headset sair. Que é
  exatamente o que se quer — a sobrevivência do progresso não depende do
  caminho de morte do app.

  Duas armadilhas para quem for repetir. A demo que abre por padrão
  (`Classic Kong`) tem `SRAM: 0 Kbit` e nunca gravaria nada — tem que ser um
  cartucho com bateria. E não adianta só jogar: sem salvar *dentro* do jogo a
  SRAM não muda, e todas as pausas dizem `sem mudança` sem que isso signifique
  problema nenhum.
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

- **Remap de input: feito** (antes era a pendência de que a página de Input
  mostrava o mapa sem deixar trocá-lo). O que segurava não era a interface e sim
  o modo "aperte o botão que você quer": com o painel aberto o input do jogo fica
  congelado, e um modo de captura teria de distinguir "apertei para escolher" de
  "apertei para jogar". Escolher **apontando** contorna isso inteiro — tocar numa
  linha abre os destinos ali embaixo dela, tocar num destino fecha —, e apontar
  é o que o laser já faz.

  Nada de `PopupMenu` nem `OptionButton`: eles abrem em outra janela, e a página
  vive num `SubViewport` colado num quad. A janela apareceria fora do painel, ou
  não apareceria.

  A lista de destinos sai dos descritores que o core declara
  (`SET_INPUT_DESCRIPTORS`), como já saíam os nomes — é o core que sabe que
  `JOYPAD_L2` é o "Z Trigger" do N64 e não existe no SNES. **Nada** é destino de
  primeira classe: é como se tira um botão do caminho sem perdê-lo.

  O mapa virou chave de configuração (uma por origem do Touch e por sistema), o
  que o põe sob o perfil do cartucho de graça. A conta mora em
  `scripts/vr/mapa_input.gd`, sem dependência de XR, como o `guidao.gd` — é o que
  permite testar sem headset os dois erros que só apareceriam lá: id que sai do
  mapa é zerado a cada frame (senão remapear com o dedo no gatilho deixaria o
  tiro preso ligado) e duas origens no mesmo destino somam em vez de uma anular
  a outra.

  Os analógicos ficam de fora: não são botões para o core. Conferido no headset
  e no desktop nos dois sistemas.
- **Passthrough: sobe no Quest 3S** — `Sala: passthrough ligado (alpha blend)`,
  sobre `gl_compatibility`, com o OpenXR 1.1.54 do runtime Oculus 206.134.0.
  Não foi de graça: **três** coisas precisam estar no lugar, e faltando qualquer
  uma o runtime oferece só `OPAQUE` como blend mode.

  1. **`xr/openxr/extensions/meta/passthrough=true`** no `project.godot`. É a
     principal, e a menos óbvia: na Meta o passthrough **não** vem por blend mode
     nativo. Sem esta chave o runtime lista só `[0]` (OPAQUE) em
     `get_supported_environment_blend_modes()`, e não há o que ligar. Quem
     destrava é a extensão `XR_FB_passthrough`, que esta chave registra e que
     passa a aceitar o `ALPHA_BLEND` por cima do que o runtime declara.

  2. **`com.oculus.feature.PASSTHROUGH` no manifesto.** A opção certa para isso
     seria `meta_xr_features/passthrough` no preset — e ela **é** lida (mexer nas
     opções irmãs muda o manifesto gerado). Mas o `godotopenxrvendors` 5.1.0 não
     emite o bloco de *manifest element contents* do plugin Meta para opção
     nenhuma: no manifesto gerado só aparecem os blocos de *application* e de
     *activity*. Conferido também com `meta_xr_features/hand_tracking=2`, que
     igualmente não sai. Daí a linha ir à mão no template gradle — ver
     "Pré-requisitos do projeto", passo 4.

     (`xr_features/passthrough` é outra coisa: é a opção do export nativo do
     Godot, inerte quando o plugin da Meta está no comando. Deixá-la em 1 não
     produz nada.)

  3. **Alpha blend mais `transparent_bg`**, que é o que o `xr_main` faz quando o
     modo Passthrough entra, e o fundo transparente que a `Sala` põe no
     `Environment`.

  Conferir:

  ```bash
  adb logcat | grep -i "Sala:"     # "passthrough ligado (alpha blend)"
  ```

  Se não subir, a linha é `Sala: passthrough indisponível — caindo no Vazio`,
  com a lista do que o runtime ofereceu. O app avisa na tela em vez de ficar
  preto em silêncio — um preto calado seria indistinguível de um preto
  proposital.

  **Armadilha de diagnóstico, que custou caro aqui.** Com o headset bloqueado ou
  fora da cabeça, o app sobe, segura a sessão imersiva e **não imprime uma linha
  sequer** — nem o `OpenXR: Created instance`, que é anterior a qualquer script.
  Processo vivo, consumindo CPU, segurando tracking. É indistinguível de um
  travamento na inicialização, e foi registrado aqui como se a extensão de
  passthrough quebrasse o arranque — o que era falso: com o headset acordado o
  mesmo build subiu em **1 segundo**. Pior: nesse estado o app fica por cima do
  overlay do sistema e o headset não mostra nem a tela de desbloqueio.

  Antes de culpar qualquer mudança por "travar o arranque", conferir se o
  headset está na cabeça e destravado. E lançar por `adb` com uma rede: se o
  `OpenXR: Created instance` não aparecer em ~25 s, `am force-stop`, senão o
  headset fica preso.

- **Orçamento de frame do fliperama: medido.** Star Fox 64 no Quest 3S (portanto
  N64 com o `angrylion` por software, que é o caso pesado), Fliperama ligado,
  tela em ~2,5×, **953 amostras de 1 s**:

  | | |
  |---|---|
  | render | média **69,8** fps, máx 74 — alvo 72 |
  | passos do emu | média **60,6**/s, mín 54 — o core pede 60 |
  | segundos < 65 fps | 47 (**4,9 %**) |
  | segundos < 55 fps | 4 (**0,4 %**) |
  | emulação atrasada (< 58 passos) | 5 s (0,5 %) |

  Ou seja: o salão **não** derruba o caso comum. A emulação acompanha o relógio
  e as quedas são raras.

  As quedas que sobram acontecem em cena pesada — a explosão de um chefe é a
  mais visível. Duas observações de quem jogou, que não são medida mas apontam
  para longe do salão: o mesmo tranco já existia **antes** do fliperama, e
  **outro chefe rodou tranquilo com o fliperama ligado**. Se o salão fosse a
  causa, ele estaria lá nos dois casos igualmente — o que varia é a cena.

  Ninguém achou que valia a pena fechar isso com número, e concordo: o custo
  aparece em segundos isolados, não atrapalha jogar, e a suspeita que sobra é da
  emulação. Se um dia interessar, o A/B com a **mesma cena** nos dois modos
  resolve, e a instrumentação já está pronta — `_aplicar_sala()` imprime
  `Sala: modo <nome>`, então uma captura de DIAG fatia por ambiente sozinha.

  A explicação que sobra para as quedas, e que casa com a forma delas: no Quest o
  N64 roda por software, com a CPU desenhando o RDP pixel a pixel. Uma explosão
  que toma a tela é o pior caso possível para isso, e não passa perto do que o
  Godot desenha — o salão são seis malhas estáticas, sem luz nem sombra, numa GPU
  que fora isso desenha um quad.

  Como repetir:

  ```bash
  adb logcat -s godot | grep -E "DIAG|Sala: modo"
  ```

  O `-- --diag` do desktop não atravessa o `am start` no Android (medido), e por
  isso existe o interruptor **Vídeo → Diagnóstico**, que também escreve os
  números na tela. Ligá-lo zera os contadores: sem isso a primeira amostra
  despeja tudo o que se acumulou desde o arranque (51589 passos num intervalo de
  1 s, na primeira vez que isto foi medido).

- **Áudio descartado em cena normal.** Na mesma captura, 47 das 953 amostras
  descartaram áudio — 7619 amostras no total, ~0,17 s espalhados por 16 min.
  Acontecem com o render em 69–72 fps, ou seja **não** são consequência de queda
  de quadro, e quase sempre num segundo em que o emulador rodou 61 passos em vez
  de 60: o acumulador adianta um passo, o core gera ~1,7 % mais áudio do que o
  `AudioStreamGenerator` consome, e o excedente cai fora. É pequeno e ninguém
  reclamou de som picotado, mas está registrado porque o mecanismo é o mesmo que
  já causou o problema de 16 % descrito em "Rodar" no README.

- **Nintendo DS: medido, e o DS confirma o mecanismo do áudio.** Trauma Center no
  Quest 3S — o mais pesado dos cinco jogos de DS, e o que puxa mais 3D —, com
  `melonds_threaded_renderer` ligado, **255 amostras de 1 s**:

  | | |
  |---|---|
  | render | média **71,6** fps, máx 74 — alvo 72 |
  | passos do emu | média **60,6**/s, mín 51 — o core pede 59,9 |
  | segundos < 65 fps | 5 (**2,0 %**) |
  | emulação atrasada (< 58 passos) | 3 (**1,2 %**) |
  | áudio descartado | 7271 amostras (~0,16 s em 4,2 min) |

  O DS roda liso. As quedas são três segundos isolados em quatro minutos.

  O que o olho não pega e a série mostra: **as duas piores amostras são
  exatamente as que descartaram áudio pesado** — 2398 e 4753 amostras, com os
  passos do emu caindo para 52 e 51. As outras quedas de render, com os passos
  firmes em 60, descartaram **zero**.

  Isso fecha o mecanismo descrito no item acima por outro lado: lá o descarte
  vinha do emulador **adiantando** um passo (61 em vez de 60), aqui vem de ele
  **atrasar** (51). Nos dois casos o que sobra é dessincronia entre o que o core
  gera e o que o `AudioStreamGenerator` consome — e é por isso que
  `audio descartado` no DIAG vale como sintoma de ritmo, não de volume.

  A medida foi tirada **depois** de ligar a rasterização em thread, então ela não
  diz quanto a opção ajudou: não há linha de base com ela desligada. O que se
  sabe é que, com ela, o sistema mais pesado do app fica no alvo.

- **A tela grande passa do salão.** No topo do slider de tamanho a tela chega a
  11,2 m de largura, e nenhum salão de proporção plausível a contém — o teto e o
  chão a cortam antes. O salão é dimensionado a partir do alcance da tela (a
  parede do fundo fica além da distância máxima, e há asserção segurando isso),
  mas o extremo continua sendo extremo. A saída é o modo Vazio, que existe para
  isso. Se de dentro do headset isso incomodar antes do extremo, a correção
  natural é a parede do fundo recuar junto com a escala.

- **Sega CD: um `.chd` corrompido parece bug do emulador.** Ao ligar o
  genesis_plus_gx, `Sonic CD (USA).chd` falhava no `retro_load_game` sem o core
  logar **nada** — e isso consumiu uma investigação inteira, porque o formato da
  falha aponta para todo lado menos para o arquivo.

  O que foi descartado, cada um medindo: `need_fullpath` e o
  `SET_CONTENT_INFO_OVERRIDE` (chegamos a implementar o env 65 e depois a
  reverter, porque o `need_fullpath` global do core já resolve — ver abaixo);
  caminho com espaços e parênteses; opções do core (`system_hw`,
  `region_detect`, `cd_loading_method`); e a BIOS, que está no lugar, com o
  header `SEGA-CD BOOT ROM ... 1.10` e md5 de BIOS conhecida.

  Quem fechou o caso foi o **`strace`**: o core abre o `.chd` (`openat ... = 40`)
  e falha **sem nunca tocar nas BIOS** — ou seja, morre ao interpretar o arquivo.
  E o `chdman info` do MAME, que é a ferramenta de referência do formato, dá
  `Error opening CHD file: Input/output error` no mesmo arquivo, enquanto lê os
  outros dois `.chd` da mesma pasta sem reclamar.

  Dois cores independentes (genesis_plus_gx e picodrive) falham igual nele e
  carregam os outros. O arquivo é que está quebrado.

  **A lição de método**: quando dois cores diferentes falham do mesmo jeito, o
  suspeito deixa de ser o core. Uma ferramenta de fora — `chdman`, `strace` — dá
  a resposta mais rápido que qualquer hipótese sobre a nossa camada.

  E uma sobre integridade: o `romkeep` marca esse arquivo como `status='ok'`,
  porque ele confere se os bytes **mudaram** desde o catálogo. Detecta bit rot;
  não detecta o que já chegou quebrado. Vale um `chdman info` ao catalogar CHDs.

- **`SET_CONTENT_INFO_OVERRIDE` (env 65) não é implementado, e está tudo bem.**
  É por ele que um core diz, por extensão, se quer o arquivo aberto por ele em
  vez de receber os bytes. Foi implementado durante a investigação acima e
  **revertido depois de medido**: sem o handler, o `need_fullpath` global do
  genesis_plus_gx já é `true`, e tanto `.md` quanto `.chd` carregam. Manter o
  código mudaria o caminho de carga de todos os cores para resolver nada.

  Se um dia um core precisar, o sinal é `retro_load_game` falhando só para
  algumas extensões — e o `need_fullpath` global sendo `false`.

- **`RETRO_DEVICE_POINTER` é usado, e não é sobra.** O host implementa o ponteiro
  (`set_pointer` mais os ids `X/Y/PRESSED/COUNT` em `_on_input_state`) porque é
  por ele que o toque do DS entra — sem isso o melonDS roda e nenhum dos jogos de
  caneta se joga.

  Registrado aqui porque quase aconteceu o contrário com o env 65 logo acima:
  código de host acrescentado numa investigação, que depois se mostrou
  desnecessário e foi revertido. Este **não** é esse caso, e a prova é direta —
  `test_caneta` exercita a conta, e os cinco jogos de DS da coleção dependem dela.

  `POINTER_COUNT` merece nota: cores consultam quantos ponteiros estão encostados
  antes de ler X/Y, e devolver 0 ali faz o toque ser ignorado mesmo com
  `PRESSED` valendo 1 — uma falha silenciosa a mais na mesma família.

  `clear_input()` zera o ponteiro junto com os botões. Quem chama é o menu
  abrindo, e o menu abre com o gatilho na mão: sem isso a caneta ficaria
  encostada na tela do jogo o tempo todo em que o painel estivesse aberto.

- **As duas telas do DS dependem de duas opções do core.**
  `EmuCore.OPCOES["nds"]` fixa `melonds_screen_layout = "Top/Bottom"` e
  `melonds_screen_gap = 0`. São os padrões do core, e ainda assim estão escritos:
  a divisão do framebuffer em dois quads recorta a metade exata, e um
  `screen_gap` diferente de zero desloca tudo. O sintoma seria a caneta errando o
  alvo por alguns pixels — que ninguém liga a uma opção de vídeo.

- **Integração com `romkeep`**: prevista para depois desta fase.
