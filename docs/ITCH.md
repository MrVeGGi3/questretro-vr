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
| Project URL | `questretro-vr` |
| Classification | **Tool** — é um emulador, não um jogo. Custa alcance (a vitrine de Games é muito maior), e mesmo assim é o rótulo honesto |
| Kind of project | Downloadable |
| Release status | Released |
| Pricing | **No payments**, com "Donate" ligado — grátis, doação opcional |
| Uploads | o APK, marcado **Android** |
| Cover | `docs/loja/capa-itch.png` (630×500, gerada por `tools/gerar-capa-itch.sh`) |
| Community | Comments — dá um canal a quem não tem conta no GitHub |

**Sobre o preço:** a decisão de não cobrar estava registrada como "porque snes9x e
genesis_plus_gx vedam uso comercial". Esse motivo caducou — ele valia quando os
cores iam no pacote, e eles saíram. Hoje nada no APK barra cobrar. O que sustenta
a gratuidade agora é outra coisa, e é escolha, não obrigação: o código é MIT e o
APK já está de graça nos Releases, então preço seria só um pedágio para quem não
conhece o outro link.

### Tags

`emulator`, `virtual-reality`, `vr`, `meta-quest`, `retro`, `snes`, `nintendo-64`,
`sega-genesis`, `nintendo-ds`, `godot`, `open-source`, `libretro`

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
