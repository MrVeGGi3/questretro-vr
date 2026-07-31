# Publicar na itch.io

O GitHub é onde o projeto mora; a itch.io é onde o sideload de Quest de fato
circula. Ela não tem a revisão de loja que barraria um emulador — e a posição
deste app é a mais segura possível, porque o que se distribui é um host, sem core
e sem ROM dentro.

Conta: **`veggi3`**. Alvo do butler: **`veggi3/questretro-vr:android`**.

## Subir uma versão

```bash
tools/exportar-release.sh
tools/publicar-itch.sh
```

O segundo confere a assinatura antes de subir e tira a versão do
`export_presets.cfg`, para não haver dois lugares dizendo o número.

**O canal tem de se chamar `android`.** É dele que a itch infere a plataforma.
Num canal com outro nome o APK sobe, aparece na página e não recebe a marca —
quem entra pelo app da itch fica sem botão de instalar, e o erro não fala em
canal nenhum.

Isso roda **desta máquina**, não da CI: assinar exige a keystore, que por desenho
nunca sai daqui. Um workflow que assinasse no GitHub precisaria da chave como
secret, o que a colocaria em mais um lugar — exatamente o que se evita.

## Criar a página (uma vez, na web)

O butler sobe arquivo, mas não cria projeto. Em <https://itch.io/game/new>:

| campo | valor |
|---|---|
| Title | QuestRetro |
| Short description / tagline | `An arcade that fits in your bedroom — SNES, N64, Mega Drive, Sega CD and DS` |
| Project URL | `questretro-vr` |
| Classification | **Tool** — é um emulador, não um jogo. Custa alcance (a vitrine de Games é muito maior), e mesmo assim é o rótulo honesto |
| Kind of project | Downloadable |
| Release status | Released |
| Pricing | **`Donate`** — baixa de graça, com botão de doação. Não é `No payments` (esse tira o botão) nem `$X or more` (esse cobra) |
| Uploads | o APK, marcado **Android** |
| Cover | `docs/loja/capa-itch.png` (630×500) |
| Banner | `docs/loja/banner-itch.png` (1920×480) — vai em "Edit theme" |
| Background | `docs/loja/fundo-itch.png` (1920×1080), em "Edit theme" → Background image |
| Description | `docs/loja/descricao-itch.html`, colado no **"Edit as HTML"** do editor |
| Community | Comments — dá um canal a quem não tem conta no GitHub |

E o bloco de metadados, que a itch mostra na lateral como "More information":

| campo | valor |
|---|---|
| Made with | Godot |
| Languages | English, Português (Brasil) |
| Inputs | marcar suporte a **VR** e a controle; o app não usa teclado nem mouse no headset |
| License | MIT |
| Links | `Source code` → <https://github.com/MrVeGGi3/questretro-vr> |

O link para o GitHub vai **nos metadados**, e não só no corpo: é ali que quem procura
a fonte olha primeiro, e é o que separa este app dos APKs anônimos que circulam no
mesmo nicho.

**Sobre o tagline.** Ele foi escolhido por fazer duas coisas de uma vez: dá uma imagem
na cabeça (é o que faz clicar) e nomeia os consoles (é o que a busca indexa). A
**abertura da descrição foi escrita para entregar essa promessa na primeira frase** —
se o tagline mudar, a abertura muda junto, senão a vitrine promete uma coisa e a
página começa com outra. Em português, se um dia a página for traduzida:
`Um fliperama que cabe no seu quarto — SNES, N64, Mega Drive, Sega CD e DS`.

**Sobre o preço.** A decisão de não cobrar estava registrada como "porque snes9x e
genesis_plus_gx vedam uso comercial". Esse motivo caducou: ele valia quando os cores
iam no pacote, e eles saíram. Hoje nada no APK barra cobrar.

Fica grátis por escolha, então, e por três razões que se sustentam sem aquela:

1. O APK já está de graça nos Releases e o código é MIT — preço seria pedágio para
   quem não achou o outro link.
2. O nicho é gratuito por inteiro. O **EmuVR**, que é o análogo mais próximo (frontend
   de VR sobre cores libretro, com o usuário fornecendo tudo), diz explicitamente que
   é grátis e sempre será.
3. **Monetizar é o agravante que atrai processo.** O Yuzu tirava ~US$ 30 mil/mês de
   Patreon e fechou acordo de US$ 2,4 milhões com a Nintendo em 2024. O dinheiro não
   foi a causa isolada — ia junto com contornar criptografia e emular console da
   geração corrente, e este projeto não faz nenhum dos dois —, mas foi o que
   transformou um alvo tolerado em alvo prioritário.

Se um dia mudar de ideia, o caminho pisado é o do **PPSSPP Gold**: build paga
idêntica à livre, fonte aberta, sem tier de acesso antecipado — que foi justamente a
forma que a Nintendo atacou.

### Tags

`emulator`, `virtual-reality`, `vr`, `meta-quest`, `retro`, `snes`, `nintendo-64`,
`sega-genesis`, `nintendo-ds`, `godot`, `open-source`, `libretro`

## Arte

As três peças saem de um comando:

```bash
tools/gerar-arte-itch.sh    # -> docs/loja/{capa,banner,fundo}-itch.png
```

**A capa é composição; o banner e o fundo são o salão de arcade de verdade** — o
mesmo `Sala.aplicar(Sala.FLIPERAMA)` que roda no headset, renderizado em outra
proporção por `app/scripts/loja/banner_sala.gd`. A página promete "um fliperama que
cabe no seu quarto", e a arte que sustenta isso é a coisa em si.

Três decisões que não são gosto:

- **O banner leva só o wordmark.** O tagline não entra: a itch já o imprime logo
  abaixo do banner, e na imagem ele cairia em cima das linhas de neon que convergem
  — o pior lugar possível para texto claro. Testado, e ilegível.
- **O fundo é escurecido e desfocado com força** (`-blur 0x8 -modulate 42`). A coluna
  de conteúdo tem ~960px e fica por cima dele; a página é quase toda texto, e fundo
  com contraste real a torna cansativa. Se ainda assim atrapalhar, a saída sem risco é
  cor chapada `#0e0c12`, que é o mesmo tom.
- **O render precisa de `xvfb-run`.** Em `--headless` puro o SubViewport sai preto,
  sem uma linha de erro no log — o script já cuida disso, mas quem chamar o `.gd` à
  mão vai tropeçar.

## Capturas

As de interface saem dos testes, sem headset:

```bash
xvfb-run -a godot --xr-mode off --path app res://cenas/test_ui.tscn
# -> ~/.local/share/godot/app_userdata/QuestRetro/ui_*.png  (1280x800)
```

Servem para a página: `ui_menu_roms` (a biblioteca com jogos), `ui_menu_input`
(remap e a mão que aponta), `ui_menu_sala` (os três ambientes), `ui_menu_tela`.

**Não** use `ui_menu_cores`: fora do headset a página aparece vazia, dizendo que
os cores vêm de `res://cores` — o oposto do que ela faz no Quest, que é o recurso
que vale mostrar.

Elas não são versionadas, porque os testes as regeram a cada execução e a última
limpeza de histórico deste repo nasceu de PNG versionado. Gere antes de subir.

**O buraco que só o headset preenche.** A tela flutuando na sala é o argumento
inteiro do projeto e não existe em captura nenhuma aqui — as de interface mostram
o menu, não a experiência. Enquanto não houver imagem de dentro do Quest, a
página vende o app pelo lado mais fraco. Capture pelo próprio headset (o botão de
captura do Quest) ou por `adb shell screenrecord`.

## Depois de publicar

Ponha o link da itch no README e nas notas do release do GitHub, e o link do
GitHub na página da itch. Quem chega por um lado costuma querer o outro: o código
para quem chegou pela loja, a instalação fácil para quem chegou pelo código.
