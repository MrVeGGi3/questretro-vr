# questretro-vr

Emulador **VR-nativo** para Meta Quest 3S, feito em **Godot 4** com cores
**libretro**. Diferenciais de projeto: tela redimensionável (de portátil a
cinema gigante) e controles físicos por jogo (ex: "guidão de nave" pro Star Fox).

> Status: **Fases 0 a 7 concluídas**, todas conferidas no Quest 3S. Rodam
> **SNES, N64, Mega Drive, Sega CD e Nintendo DS** (quatro cores libretro), com
> menu in-VR, biblioteca de jogos, save states e saves de bateria, controles
> remapeáveis com perfil por cartucho, o "guidão de nave" do N64, a **sala** em
> volta da tela (vazio, fliperama ou passthrough) e a **caneta** do DS. Ver o
> Roadmap abaixo e `docs/EXPORT.md`.

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
  project.godot / export_presets.cfg / libretrogd.gdextension
  openxr_action_map.tres   ações do OpenXR (o que cada botão do Touch envia)

  cenas/           todos os .tscn
    vr_main.tscn       a cena principal (project.godot aponta para ela)
    main.tscn          cena de teste desktop (Fase 0)
    test_*.tscn        cenas dos testes

  scripts/         todos os .gd, subdivididos por assunto
    main.gd            par da cena desktop
    emu/               emu_core.gd, config_emu.gd — o emulador e a configuração
    vr/                xr_main.gd, painel_menu.gd, guidao.gd, mapa_input.gd,
                       sala.gd, caneta_ds.gd
    ui/                menu_raiz, tema, widgets, navegador_roms,
                       biblioteca_roms (varredura e títulos, sem UI nem XR)
      paginas/           uma por página do menu
    testes/            test_*.gd (inclusive test_load.gd e test_shot.gd,
                       que rodam por `-s` e não têm cena)

  assets/          icon.png, logo.png
  bin/             .so da GDExtension (gerado)
  cores/           cores libretro .so (baixados; não versionados)
  roms/            demo.smc (homebrew freeware, essa vai no APK)
cores/             (reservado)
docs/
```

Cena e script ficam em árvores separadas por escolha de organização. Ao abrir um
`.tscn`, o script dele está no caminho espelhado sob `scripts/` — `cenas/vr_main.tscn`
usa `scripts/vr/xr_main.gd`.

## Por que Godot (e não Unity), godot-cpp 4.5, cores libretro

- **Godot**: FOSS, suporte Quest maduro (OpenXR 1.1, `godot-openxr-vendors`),
  editor roda nativo no Quest. Unity só ganharia em samples oficiais.
- **godot-cpp 4.5**: é a release estável mais nova; GDExtension é
  forward-compatible (`compatibility_minimum = 4.5`), então carrega no Godot
  4.6/4.7 sem rebuild. Buildar contra `master` casaria a ABI do 4.7 mas é alvo
  móvel — sem ganho pro nosso uso.
- **libretro**: não reinventar emulação. Um core `.so` por sistema — quase: o
  `genesis_plus_gx` cobre Mega Drive e Sega CD sozinho, e é por isso que os dois
  entram como um sistema só aqui. Hoje são quatro cores para cinco consoles.

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
curl -fsSL -O $B/genesis_plus_gx_libretro.so.zip        # Mega Drive + Sega CD
curl -fsSL -O $B/melonds_libretro.so.zip                # Nintendo DS
unzip -o '*.so.zip' && rm -f *.so.zip
```

O DS **não** precisa de BIOS: o melonDS traz FreeBIOS e gera a firmware, e os
jogos arrancam sem `bios7`/`bios9`/`firmware` no disco.

O Sega CD precisa da BIOS do Mega CD em `user://system/`, com os nomes que o
core procura — `bios_CD_U.bin`, `bios_CD_E.bin`, `bios_CD_J.bin`. Sem ela o
disco não abre.

O core sai da extensão da ROM (`EmuCore.core_para_rom`): `.smc/.sfc/.fig/.swc/.zip`
vão para o snes9x, `.z64/.n64/.v64` para o mupen64plus,
`.md/.gen/.smd/.chd/.cue` para o genesis_plus_gx e `.nds` para o melonDS.
Trocar de ROM entre sistemas troca o `.so` sozinho, gravando a SRAM do jogo
anterior antes.

Um core para dois consoles: o genesis_plus_gx roda cartucho de Mega Drive e
disco de Sega CD, com o mesmo controle. Por isso os dois são **um** sistema aqui
— um core, um mapa de botões, um nome —, e um `.chd` de Sonic CD aparece na lista
como "Mega Drive", que é a máquina que roda o disco.

`.bin` fica de fora de propósito: é cartucho de Mega Drive válido, mas também é a
faixa de dados que acompanha um `.cue`, e oferecer as duas coisas na mesma lista
faria escolher a faixa em vez do jogo.

O N64 desenha por GPU, num FBO que a GDExtension empresta ao core — ver
"Renderização por hardware" em `docs/EXPORT.md` para o que isso amarra.

## Rodar

**Teste headless** (prova extensão, carga do core e round-trip da SRAM; ROM opcional):

```bash
godot --headless --path app --import           # 1ª vez, para escanear a GDExtension
godot --headless --xr-mode off --path app -s res://scripts/testes/test_load.gd -- --rom /caminho/jogo.sfc
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

O **Mega Drive** (e o Sega CD, que usa o mesmo controle) segue o desenho do SNES:
analógico esquerdo vira D-pad, e a mão direita fica com o controle de 3 botões
inteiro — A, B, C e Start —, que é tudo o que Sonic pede. Os extras do controle
de 6 botões vão para a esquerda.

O **Nintendo DS** tem seção própria mais abaixo, porque a tela de baixo é caneta
e isso muda o mapa: o gatilho direito nasce em "Nada" por ser a ponta da caneta.

### Trazer a tela para a frente

**Clique do analógico direito** e a tela — com a sala junto — vem para onde você
está olhando agora. Também está na página **Tela**, como "Trazer para a frente",
porque um atalho escondido atrás de um clique sem rótulo é um atalho que ninguém
acha.

Existe porque a tela nascia amarrada à origem do espaço de jogo, não a você.
Quem virasse a cadeira, se deitasse no sofá ou simplesmente se levantasse ficava
com ela de lado — e os sliders de distância e altura não giram nada. Em VR isso
não é conforto, é a diferença entre jogar e não jogar.

A **sala vem junto**, e não é detalhe: mover só a tela a jogaria para dentro de
uma parede do fliperama, que é dimensionado a partir do alcance dela. Movendo as
duas, a relação entre tela e salão continua valendo — inclusive a asserção de que
a parede do fundo fica além da distância máxima.

Só a **guinada** entra. Inclinar ou tombar a cabeça no instante do clique não
deixa a tela torta nem no chão, pela mesma razão que o guidão ignora as outras
duas rotações: olhar em volta não é comandar.

E não persiste entre sessões, de propósito: a origem do espaço de jogo muda a
cada recentragem do próprio Quest, então uma âncora guardada apontaria para um
lugar que não existe mais.

Os dois cliques de analógico ficam simétricos: o esquerdo recentra o guidão de
nave, o direito recentra a tela. Nenhum dos dois é botão para o core — o mapa de
input cobre só os botões, gatilhos e grips —, então não disputam com jogo nenhum.

A conta é geometria pura, e por isso tem asserção sem headset em `test_sala`: o
modo de falhar é sinal trocado, que põe a tela **atrás** de quem centralizou, e
de dentro do headset isso não se lê como "coordenada invertida" e sim como "a
tela sumiu".

Esse mapa não é decorado: sai dos descritores que o próprio core declara
(`SET_INPUT_DESCRIPTORS`), e eles surpreendem em dois dos quatro cores — no N64
`JOYPAD_B` é o **A**, e no Mega Drive o "A" do controle é `JOYPAD_Y` e o "C" é
`JOYPAD_A`. Só o SNES e o DS batem com o nome.

Com o painel aberto, o **analógico direito rola a página** — sem isso nada
abaixo da dobra seria alcançável, porque o laser só sabe apontar e clicar.

Arrastar a barra de rolagem com o laser também vale, e vale **até o fim**: ao
descer o pegador o raio sai pela borda de baixo do painel antes de a lista
acabar, e o ponteiro segue pelo plano do quad em vez de largar o arrasto ali.
Sem isso a barra congelava onde o raio saiu e era preciso soltar, voltar para
dentro e pegar de novo — o que só incomodou de verdade quando a biblioteca
trouxe a primeira lista longa.

### Remapear os botões

Na página **Input**, toque numa linha e os destinos aparecem ali embaixo dela;
toque num destino e a linha muda. Os nomes são os que o core dá àquele console —
"Z Trigger" existe no N64 e não no SNES —, e **Nada** desliga a origem, que é
como se tira um botão do caminho sem perdê-lo.

Escolher apontando, em vez de um modo "aperte o botão que você quer", contorna o
problema que segurava o remap: com o painel aberto o input do jogo fica
congelado, e um modo de captura teria de distinguir "apertei para escolher" de
"apertei para jogar". Apontar é o que o laser já sabe fazer.

Os dois analógicos ficam de fora: eles não são botões para o core. O esquerdo do
SNES vira as quatro direções, e no N64 os dois são eixos de verdade.

Com um **perfil de cartucho** ligado (abaixo), o mapa que você montar vale só
para aquele jogo.

### Guidão de nave (N64)

Ligue na página **Input** e o manche do N64 deixa de sair do thumbstick e passa
a sair da **pose das duas mãos**: segure os controles como o guidão de uma nave.
A barra imaginária entre as mãos gira como um volante — para ir à esquerda, a
mão direita sobe e a esquerda desce. Empurrar e puxar sobe e desce o nariz.

O repouso é capturado quando você **fecha o painel**, e não quando mexe num
ajuste: com o menu aberto sua mão está esticada apontando para ele, e capturar
aquela pose deixaria a arfagem grudada no batente. Com o guidão ligado o
analógico esquerdo fica livre, e o **clique dele recentra** a qualquer momento —
vale usar sempre que mudar de posição.

Tudo é medido no referencial da sua guinada, não no do quarto: virar o corpo não
troca o significado dos comandos. Inclinar a cabeça também não — olhar em volta
não é pilotar.

Ajustes, todos na mesma página:

| ajuste | o que faz |
|---|---|
| **Inclinação cheia** | quantos graus de tombo valem eixo cheio |
| **Curso cheio** | quantos centímetros de empurrão valem eixo cheio |
| **Zona morta** | ignora tremor de mão (radial, não por eixo) |
| **Curva** | acima de 1 reage mais no começo do movimento; abaixo, controle fino perto do centro |
| **Inverter subir/descer** | o Star Fox 64 já nasce invertido, e a preferência varia |
| **Mostrar leitura** | os eixos ao vivo na tela, para diagnosticar sem adivinhar |

Curso e inclinação decidem *onde* o eixo satura; a **curva** decide como a
resposta se distribui até lá. Zero e cheio são pontos fixos dela, então mexer na
curva nunca custa alcance — só muda o caminho até o batente. É por isso que ela
existe em vez de um multiplicador de sensibilidade, que seria só outro nome para
mexer no curso.

A conta vive em `app/scripts/vr/guidao.gd`, sem nenhuma dependência de XR — entra
`Transform3D`, sai `Vector2`. É o que permite verificá-la sem headset:

```bash
godot --headless --xr-mode off --path app res://cenas/test_guidao.tscn
```

### Perfil por cartucho

Os ajustes acima começam valendo para todo mundo. Na página **Input**, "Ajustes
deste jogo" → **Criar perfil** faz o jogo em execução ganhar os seus próprios: a
partir dali, mexer num slider aqui não mexe em mais nada. É o que o Star Fox 64
pede e o Super Mario 64 não — a pose das duas mãos no lugar do manche não faz
sentido num jogo de plataforma, e até aqui ligar o guidão para um ligava para os
dois.

O perfil nasce copiando o que já estava valendo, então criá-lo nunca muda o
comportamento no mesmo instante. Apagar pede duas batidas, pela mesma razão que
apagar um save state pede: no headset o clique sai de um laser apontado à
distância. Apagado, o jogo volta a seguir os ajustes gerais.

Só **input** entra no perfil — o mapa de botões e os ajustes contínuos (zona
morta do D-pad, guidão inteiro). Tamanho de tela, brilho e volume são
preferência de quem joga, não do cartucho: duplicá-los por jogo só criaria
lugares diferentes para consertar a mesma coisa.

Cada perfil é um `user://perfis/<jogo>.cfg`, com o mesmo nome que o `.srm` e os
slots de estado daquele cartucho.

## Nintendo DS: duas telas e uma caneta

O DS tem duas telas, e aqui elas viram **dois objetos separados** no espaço: a de
cima grande e longe, a de baixo perto e inclinada para trás, como um console
apoiado nas mãos. Cada uma tem tamanho, distância e altura próprios — os da tela
de baixo aparecem na página **Tela** só quando há um DS carregado.

As duas saem do mesmo framebuffer (o melonDS empilha as telas num 256×384), e o
que as separa é recorte de UV no material, não uma segunda cópia da imagem.

A **caneta** é o mesmo laser que aponta o menu, mirando a tela de baixo: o
gatilho direito é a ponta encostando. Por isso ele nasce em **Nada** no mapa de
botões do DS — mapeado em R, todo toque apertaria R junto. O R fica no grip, e
Start continua vindo do toque curto no botão de menu, como em todo sistema.

O DS é o sistema mais pesado que roda aqui — dois processadores e um GPU 3D, tudo
em software — e ainda assim fica no alvo: **71,6 fps de média** num alvo de 72,
medidos com Trauma Center ao longo de 255 amostras de um segundo. Isso depende de
uma opção que o core traz desligada (`melonds_threaded_renderer`); os detalhes e
o que a medição mostrou sobre o áudio estão em `docs/EXPORT.md`.

A conta que converte o ponto no quad em toque vive em `scripts/vr/caneta_ds.gd`,
sem nenhuma dependência de XR, e o que a torna traiçoeira é o libretro querer a
posição sobre o **framebuffer inteiro** enquanto o quad mostra só metade dele.
Errar isso põe a caneta na tela de cima e o jogo parece não responder — daí ela
ter teste próprio:

```bash
xvfb-run -a godot --xr-mode off --path app res://cenas/test_caneta.tscn
```

## A sala

Onde a tela flutua. Página **Sala** do menu, três modos:

| modo | o que é |
|---|---|
| **Vazio** | só a tela, o resto preto — o padrão |
| **Fliperama** | um salão de arcade em volta: carpete, neon nas quinas, gabinetes acesos nas paredes |
| **Passthrough** | o seu quarto de verdade, pelas câmeras do Quest 3S |

Os três conferidos no headset. O passthrough tem uma pegadinha que vale saber
antes de mexer nele: na Meta ele **não** vem por blend mode nativo — o runtime
oferece só `OPAQUE` até a extensão `XR_FB_passthrough` entrar, e ainda depende de
uma linha no manifesto que o addon de vendors não emite sozinho. As três peças
estão em `docs/EXPORT.md`; faltando qualquer uma, o modo cai no Vazio avisando.

Nasce no Vazio porque uma atualização não deve trocar o cenário debaixo de
quem já usa o app — a mesma razão pela qual o guidão nasce desligado. E o modo
fica **fora** do perfil do cartucho: onde você joga é preferência sua, não do
jogo, como já valia para tamanho de tela, brilho e volume.

O salão é construído em código, sem asset nenhum, e é dimensionado a partir do
**alcance da tela** e não do que pareceria um fliperama plausível: a tela vai de
portátil a cinema, e num salão de proporção realista a tela grande atravessaria
a parede do fundo. Mesmo assim há um limite — no topo do slider de tamanho a
tela passa do salão, e aí a saída é o Vazio, que existe para isso.

Nada de luz em tempo real, sombra ou glow: o projeto roda em `gl_compatibility`
nos dois alvos, onde isso é caro ou não existe. A iluminação está **pintada nos
vértices**, o que num fliperama escuro é justamente o efeito que se quer, e o
salão inteiro cabe em seis malhas.

O salão **não custa fps**, e isso deixou de ser inferência. Star Fox 64 parado no
Quest 3S, alternando Vazio e Fliperama em blocos de ~20 s: **mediana 70 fps dos
dois lados**, nos dez blocos, com ~90 amostras cada. Antes o que havia era o
número absoluto (69,8 fps de média em 953 amostras de jogo), que dizia "cabe no
orçamento" mas não separava o salão do resto.

Ligue **Vídeo → Diagnóstico** para ver os números na própria tela, sem cabo nem
rebuild. Cada amostra carrega o estado em que rodou — resolução e formato do
frame, sala, se o menu estava aberto — e quanto do segundo foi gasto dentro do
core, convertendo pixel e bombeando áudio. Isso existe porque contador de fps
sozinho diz *que* o frame ficou longo e nunca *onde*: três suspeitos das quedas
foram eliminados por comparação direta (a sala, o painel aberto e a resolução
interna do N64) e nenhum deles teria caído sem a amostra dizer em que
configuração rodou. Os detalhes e o que ainda não está atribuído estão em
`docs/EXPORT.md`.

Para ver a sala sem headset — porque "ficou escuro demais" e "a parede está
virada para fora" nenhuma asserção pega:

```bash
xvfb-run -a godot --xr-mode off --path app res://cenas/test_sala.tscn   # -> user://sala_*.png
```

O mesmo teste afirma o que a foto não mostra: que trocar de modo não deixa
geometria para trás (um vazamento só apareceria no headset, como queda de fps
sem causa aparente), que o salão sai igual a cada arranque, e que a parede do
fundo continua além da distância máxima da tela — esta última para quando
alguém resolver "arrumar" as proporções do salão.

## ROMs

**Não** versionamos ROMs (direitos autorais). Use as suas.

Jogos com bateria gravam sozinhos em `user://saves/<jogo>.srm`, no mesmo formato
do RetroArch — dá para levar um save de lá para cá e vice-versa. A gravação é
automática (a cada 1 s, se algo mudou) e também ao trocar de ROM, ao fechar o app
e quando o Quest suspende a sessão. A página **Saves** do menu mostra o tamanho
da bateria e quando ela foi gravada pela última vez.

Um segundo, e não cinco, porque no Quest o app morre ao ser pausado — e tirar o
headset é como quase toda sessão acaba, então o timer é o que de fato protege o
progresso. Checar mais vezes é quase de graça: sem mudança, a gravação sai na
comparação de buffer sem tocar no disco. `test_sram` mede esse atraso.

Apagar um save state **tem desfazer**: o slot vai para `user://states/lixeira/`
e o botão "Desfazer" ocupa o mesmo canto enquanto o slot estiver vazio. As duas
batidas de confirmação continuam lá, mas não bastaram — um save foi apagado por
engano no headset, e num Quest sem root o `remove_absolute` era definitivo. A
resposta não foi uma terceira pergunta, que só treinaria a pessoa a confirmar sem
ler. Gravar por cima é o que diz que o antigo não interessa mais, e aí o desfazer
se recusa.

Os save states dos quatro slots valem também no N64: que restaurar devolve o
jogo ao ponto gravado está conferido por imagem em `test_estado` (o teste de
bytes não servia lá — ver `docs/EXPORT.md`) e jogado no headset.

## A biblioteca

A página **ROMs** abre numa lista de **jogos**, não de arquivos. A varredura acha
as ROMs onde estiverem, o título sai limpo do nome do arquivo, e a lista vem
agrupada por console, com **Continuar** e **Favoritos** no topo.

Navegar em pastas não escala para quem instala o APK. Essa pessoa não tem `adb`
para arrumar nada: despeja as ROMs em `/sdcard/Download` misturadas com o resto
do aparelho, e precisa reconhecer o jogo em

```
5478 - Ghost Trick - Phantom Detective (USA) (En,Fr,De,Es,It).nds
```

apontando um laser a 2 m de distância. As regras de limpeza do título saíram de
arquivos reais — numeração de coleção, tags de região e idioma, artigo no fim ao
estilo `Legend of Zelda, The` — e cada uma é uma linha da tabela em
`test_biblioteca`. Elas não são exemplos: **são** as regras, e mexer na limpeza
sem mexer na tabela é o jeito de quebrar a lista inteira em silêncio.

Duas coisas que a limpeza **não** faz: juntar dumps regionais do mesmo jogo
(`Sonic (USA)` e `Sonic (Japan)` continuam duas linhas, e a região é o que as
separa) e esconder dump ruim — o `[b]` do No-Intro vira um `△` na linha, porque
uma ROM assim trava e corrompe de formas que parecem bug do emulador, e sem o
aviso a investigação vai toda para o lugar errado.

**Extensão não basta**, e isso só aparece quando se varre o aparelho inteiro.
`.md` é Mega Drive e é Markdown: a primeira varredura do `$HOME` desta máquina
devolveu **1161 jogos de Mega Drive**, e todos eram documentação de repositório.
`.zip` é ROM de SNES compactada e é qualquer outra coisa compactada — em
Downloads eram seis zips, nenhum deles jogo. Um teto de tamanho não resolveria:
há `CHANGELOG.md` maior que cartucho.

Então essas duas extensões passam por um exame de conteúdo antes de virar linha:
o `.md` precisa trazer `SEGA` em `0x100`, que é onde o cartucho diz de que
console é, e o `.zip` precisa ter uma ROM de SNES dentro (só de SNES — o mupen
exige caminho de arquivo real e não abre N64 compactado, então aceitar um zip de
`.z64` daria linha na lista e erro ao carregar). Depois do exame, as mesmas
raízes deram **21 jogos**. Só a varredura desconfia: no modo Pastas quem abriu a
pasta foi a pessoa, e lá a lista mostra o que estiver lá — é a saída para o dump
esquisito que o exame recusar. O log diz quantos foram recusados, porque essa é
a primeira pergunta quando um jogo não aparece.

O índice fica em `user://biblioteca.json` e é o único uso de JSON no projeto: o
`ConfigFile` do resto é chave→valor por seção, e isto é uma lista de registros.
Abrir o painel só revalida o que já está lá (um `file_exists` por item); varrer a
árvore de novo é o botão **Reescanear**. A varredura anda por orçamento de
**milissegundos por frame**, e não por "N pastas por frame", porque uma pasta com
3000 arquivos custa mais que trinta pastas vazias — medir em pastas deixaria
justamente o caso ruim sem limite. E o limite existe porque em VR travar o frame
não é lentidão, é enjoo.

O modo **Pastas** continua ali, no botão do rodapé: é a saída para a ROM que a
varredura não alcançou — pasta funda demais, extensão que não reconhecemos — e
sem ela essa ROM ficaria inalcançável.

A varredura é lógica de arquivo e de texto, sem uma linha de XR ou de UI, então
prova-se sem headset e em `--headless`:

```bash
godot --headless --xr-mode off --path app res://cenas/test_biblioteca.tscn
```

O que só se pega ali: título que sai vazio (linha clicável que não diz em que
jogo se está clicando), regionais que desabam num só, pasta oculta que a
varredura devia recusar, tamanho que volta do JSON como float, e — o pior deles
— varredura que perde estado ao ceder o frame. Esse último é comparado contra a
varredura bloqueante com orçamento **zero**, que força ceder no meio de cada
pasta; no headset ele apareceria como jogo faltando na lista, sem erro nenhum no
log. A ligação da lista com a página (título na linha, estrela, filtro de
console, e o sinal que de fato troca a ROM) é conferida por clique em `test_ui`.

## Roadmap

- **Fase 0 ✅** — GDExtension libretro rodando no Godot desktop.
- **Fase 1 ✅** — cena OpenXR, quad redimensionável com o framebuffer, APK Quest 3S,
  input dos controllers Touch.
- **Fase 2 ✅** — menu in-VR: navegador de ROMs, configurações persistentes de
  tela/vídeo/áudio/input e save states.
- **Fase 3 ✅** — saves de bateria (SRAM) ✅; core N64 ✅ — Star Fox 64 roda no
  Quest 3S e no desktop, com um porém: no headset o renderizador por GPU do
  mupen (GLideN64) derruba o app na Adreno, então lá ele usa o renderizador
  por software, que roda fluido.

  O GLideN64 no Quest foi investigado até o fim e **não se resolve por
  configuração**: oito opções do core aplicadas de uma vez e as duas variantes
  de GL (`gles2`/`gles3`) dão o mesmo crash, com os mesmos quadros do driver.
  `docs/EXPORT.md` traz o rastro, a tabela do que foi descartado e as duas
  trilhas que sobraram para quem voltar nisso.

  Controles físicos: o **guidão de nave** do N64 mapeia a pose das duas mãos nos
  eixos do manche; os botões são **remapeáveis** pela página de Input; e tudo
  isso pode virar **perfil por cartucho** — o mapa que serve ao Star Fox 64 não
  vai junto para o Mario 64 (ver "Controles no headset").

- **Fase 4** — a **sala**: a tela deixou de flutuar no vazio e passou a ter um
  lugar em volta (ver "A sala"). Três modos, um deles um salão de arcade — o
  "arcade virtual" do plano.
- **Fase 5** — mais consoles. **Mega Drive** e **Sega CD** pelo genesis_plus_gx,
  que é um core só para os dois. Acrescentar um sistema toca em quatro lugares
  (core, nome, linhas de eixo, mapa de botões) e esquecer um não dá erro nenhum —
  dá controle morto no headset —, então `test_ui` passou a conferir os quatro
  para todo sistema que o navegador reconhece.

- **Fase 6** — **Nintendo DS** pelo melonDS: duas telas como objetos separados e
  o laser virando caneta (ver "Nintendo DS"). É o primeiro sistema que exigiu
  algo do host em C++ — `RETRO_DEVICE_POINTER`, que é como o toque entra.

- **Fase 7** — a **biblioteca**: a página de ROMs virou lista de jogos em vez de
  lista de arquivos (ver "A biblioteca"). É a primeira coisa feita olhando para
  quem instala o APK e não tem `adb` — depois de seis fases de consoles,
  navegar em pastas tinha deixado de escalar. O navegador de arquivos continua
  lá como saída.

## Menu dentro do headset

Segure o **botão de menu** (controle esquerdo) por 0,5 s para abrir o painel;
toque curto continua valendo como Start. Aponte com o controle direito e use o
gatilho para clicar. As configurações ficam em `user://config.cfg` — mais um
`user://perfis/<jogo>.cfg` para cada cartucho com perfil próprio — e sobrevivem
entre sessões.

No desktop, `Tab` abre o painel e o mouse interage direto — dá para iterar a UI
sem build e sideload.

Para ver as páginas do menu sem headset nenhum:

```bash
xvfb-run -a godot --xr-mode off --path app res://cenas/test_ui.tscn   # -> user://ui_*.png
```

Esse mesmo teste confere o caminho de clique do laser, o round-trip dos save
states, a persistência das configurações e o isolamento dos perfis por
cartucho — que um ajuste de um jogo não vaze para os outros é justamente o que
nenhum PNG mostraria.

O `--xr-mode off` é obrigatório: o projeto liga OpenXR, e sem um runtime ativo
na máquina o Godot **trava no arranque** sob Xvfb, sem imprimir nada — parece
travamento do teste, mas é do motor.

Trocar de ROM tem teste próprio, porque o mupen64plus recusa um segundo
`retro_load_game` e a troca de N64 precisa recarregar o core (ver
`EmuCore.RECARREGA_SEMPRE`). Como as ROMs não são versionadas, elas vêm por
argumento:

```bash
xvfb-run -a godot --xr-mode off --path app res://cenas/test_troca_rom.tscn -- \
    --n64 "$ROMS/N64/Star Fox 64 (USA).z64" \
    --n64b "$ROMS/N64/Super Mario 64 (USA).z64" \
    --snes "$ROMS/SNES/Chrono Trigger (USA).sfc"
```

Também não roda em `--headless`: o N64 desenha por GPU, e sem contexto de GL o
FBO emprestado ao core não sobe.

Save state também tem teste próprio, pela mesma razão de fundo: no N64 o estado
serializado **não repete byte a byte** (o mupen roda uma `EmuThread` própria), e
comparar bytes ali não distingue restauração ruim de core que não repete. Então
este compara a **imagem** — grava, avança, restaura, e pergunta se o frame de
volta é o do ponto gravado:

```bash
xvfb-run -a godot --xr-mode off --path app res://cenas/test_estado.tscn -- \
    --n64 "$ROMS/N64/Star Fox 64 (USA).z64" \
    --snes "$ROMS/SNES/Chrono Trigger (USA).sfc"
```

O SNES entra como controle: ele é determinístico e sabidamente restaura, então
reprovar nele acusa a métrica e não o emulador — foi assim que o teste se
corrigiu duas vezes. Os frames comparados ficam em `user://estado_*.png`, porque
quando um teste de imagem falha só a imagem diz o motivo.

A bateria tem o seu, que mede o atraso entre o jogo salvar e os bytes chegarem
ao disco — o que se perde se o app morrer, que no Quest é o normal:

```bash
xvfb-run -a godot --xr-mode off --path app res://cenas/test_sram.tscn -- \
    --rom "$ROMS/SNES/Chrono Trigger (USA).sfc"
```

O caminho do `.srm` sai do nome da ROM, então o teste faz backup do save que já
existir e o devolve no fim — inclusive se falhar no meio. Testar a segurança do
save destruindo um save seria irônico demais.
