# Contribuir

*Issues e pull requests em português ou inglês, tanto faz. English version below.*

## Antes de abrir uma issue

Duas perguntas respondem a maior parte do que chega:

- **"O app não acha meus jogos / diz que não há core."** É a permissão de
  armazenamento. Menu → **ROMs** → "Permitir acesso", e ligue a chave nos Ajustes do
  Android. Sem ela o app não enxerga nada em `/sdcard` — nem ROMs, nem cores. Ela
  volta a zero quando você reinstala o APK, enquanto os arquivos continuam lá; é por
  isso que parece que o app perdeu tudo.
- **"Por que o APK não vem com os cores?"** Porque as licenças dos quatro não
  convivem num mesmo pacote. O raciocínio inteiro está em
  [THIRD-PARTY.md](THIRD-PARTY.md), e essa decisão não está em discussão.

Para bug, diga o **console e o core**, se foi no headset ou no desktop, e o que o
log mostrou. No Quest: `adb logcat -s godot`.

## O que não entra no repositório

Nunca, em pull request nenhum: **ROM, BIOS, core libretro compilado, keystore ou
senha**. O `.gitignore` cobre os padrões conhecidos, mas ele não é a última linha de
defesa — você é.

## Rodar os testes

O que se prova sem headset é o que a CI roda, e você pode rodar igual:

```bash
godot --headless --xr-mode off --path app --import        # obrigatório num clone limpo
godot --headless --xr-mode off --path app res://cenas/test_biblioteca.tscn
xvfb-run -a godot --xr-mode off --path app res://cenas/test_ui.tscn
xvfb-run -a godot --language en --xr-mode off --path app res://cenas/test_ui.tscn
```

`--xr-mode off` **não é opcional**: o projeto liga OpenXR e, sem runtime ativo, o
Godot trava no arranque sem imprimir nada. Parece teste pendurado; é o motor.

O `--import` também não: num clone limpo não existe `app/.godot/`, e abrir uma cena
antes de importar trava em silêncio.

Os testes que dependem de ROM (`test_troca_rom`, `test_sram`, `test_estado`) ficam
fora da CI porque ROM não é versionada. Se você mexeu no que eles cobrem, rode-os
localmente com uma ROM sua e diga no PR que rodou.

## A regra que mais importa

**Mudança que aparece no headset se prova no headset.** Este projeto já teve um
commit que passou em todo teste de desktop e quebrou o app inteiro no Quest — o APK
público não abria jogo nenhum, respondendo "Sem core carregado" com o core no lugar
certo. Nenhum teste de mesa pegava, porque no desktop a ROM entra por outro caminho.

Se você não tem um Quest, tudo bem: abra o PR dizendo isso e o que você conseguiu
verificar. O que não vale é o silêncio — "testado" sem dizer onde custa caro aqui.

Medição de fps só conta com o **headset vestido**. Fora dele o número sai, e mente.

## Acrescentar um idioma

Uma coluna em [`app/traducoes/ui.csv`](app/traducoes/ui.csv) e uma entrada em
`Idioma.LOCALES`/`ROTULOS` (`app/scripts/ui/idioma.gd`). Nada de código muda.

Os `.translation` **são** versionados, apesar de gerados: o `project.godot` os lista
e o motor tenta carregá-los antes de qualquer `--import` poder gerá-los. Regenere e
commite junto.

## Mensagens de commit

O histórico é em português e em prosa — a mensagem diz o que mudou **e por quê**,
não o arquivo que foi tocado. Não use prefixos de conventional commits. Se escrever
em inglês for mais natural para você, escreva; a forma importa mais que a língua.

---

# Contributing (English)

Issues and pull requests in English or Portuguese are equally welcome. The
repository's own docs and commit history are in Portuguese;
[README.en.md](README.en.md) is the English entry point.

## Before opening an issue

- **"The app can't find my games / says there's no core."** It's the storage
  permission. Menu → **ROMs** → "Allow access", then flip the switch in Android
  settings. Without it the app sees nothing under `/sdcard`. It resets when you
  reinstall the APK while your files stay put, which is why it looks like the app
  lost everything.
- **"Why doesn't the APK ship the cores?"** Because the four licenses do not coexist
  in one package. The full reasoning is in [THIRD-PARTY.md](THIRD-PARTY.md), and
  that decision is not up for discussion.

For a bug, say which **console and core**, headset or desktop, and what the log
showed. On the Quest: `adb logcat -s godot`.

## Never commit

**ROMs, BIOS files, compiled libretro cores, keystores or passwords.** `.gitignore`
covers the known patterns, but it is not the last line of defense — you are.

## Running the tests

Same commands the CI runs:

```bash
godot --headless --xr-mode off --path app --import        # required on a clean clone
godot --headless --xr-mode off --path app res://cenas/test_biblioteca.tscn
xvfb-run -a godot --xr-mode off --path app res://cenas/test_ui.tscn
xvfb-run -a godot --language en --xr-mode off --path app res://cenas/test_ui.tscn
```

`--xr-mode off` is **not optional**: the project enables OpenXR and, with no active
runtime, Godot hangs at startup printing nothing. Neither is `--import`: a clean
clone has no `app/.godot/`, and opening a scene first hangs silently.

ROM-dependent tests (`test_troca_rom`, `test_sram`, `test_estado`) stay out of CI
because ROMs are not versioned. If you touched what they cover, run them locally
with your own ROM and say so in the PR.

## The rule that matters most

**A change that shows up in the headset gets proven in the headset.** This project
already had a commit that passed every desktop test and broke the whole app on the
Quest — the public APK opened no game at all, answering "no core loaded" with the
core sitting right where it belonged. No desk test caught it, because on desktop the
ROM arrives by a different path.

No Quest? That's fine — open the PR saying so, and what you did verify. What doesn't
work is silence: "tested" without saying where is expensive here.

fps numbers only count with the headset **on your head**. Off it, you still get a
number, and it lies.

## Commit messages

The history is Portuguese prose — the message says what changed **and why**, not
which file was touched. No conventional-commit prefixes. Write in English if that's
more natural for you; the shape matters more than the language.
