# Terceiros

O código deste projeto é MIT (ver [`LICENSE`](LICENSE)). Este arquivo lista o que **não** é
nosso: de onde vem, sob que licença, e — a coluna que mais importa — **se este projeto
redistribui aquilo ou não**.

A distinção entre "está no repo" e "está no APK" é o que organiza tudo abaixo, porque licença
se cumpre no ato de distribuir, não no de usar.

## No repositório

| O que é | Onde | Upstream | Licença | Redistribuímos? |
|---|---|---|---|---|
| Header da API libretro | `libretrogd/src/libretro.h` | [libretro/libretro-common](https://github.com/libretro/libretro-common) | **MIT** — © 2010-2024 The RetroArch team, texto integral nas linhas 1-28 do próprio arquivo | **Sim**, é versionado aqui |
| `godotopenxrvendors` (addon) | `app/addons/godotopenxrvendors/` | [GodotVR/godot_openxr_vendors](https://github.com/GodotVR/godot_openxr_vendors) 5.1.0 | **Apache-2.0** (addon e loaders: `androidxr/`, `khronos/`, `magicleap/`, `pico/`, `meta/LICENSE-LOADER`) | **Sim**, os fontes/licenças. Os binários (`.bin/`) **não** são versionados |
| Meta OpenXR SDK | via addon, `app/addons/godotopenxrvendors/meta/LICENSE-SDK` | Meta / Facebook Technologies, LLC | **Oculus SDK License Agreement — proprietária.** Não é open source | Sim, o texto da licença; o SDK entra no APK pelo addon |
| Arte (`icon.png`, `logo.png`) | `app/assets/` | original deste projeto | MIT, junto do resto | **Sim** |

## Baixados no build, não versionados

| O que é | Upstream | Licença | Redistribuímos? |
|---|---|---|---|
| godot-cpp 4.5 | [godotengine/godot-cpp](https://github.com/godotengine/godot-cpp) | **MIT** | Não é versionado, mas é **ligado estaticamente** no `.so` da GDExtension — qualquer binário nosso carrega o aviso MIT do godot-cpp e do Godot |
| Godot Engine 4.6.3 (runtime) | [godotengine/godot](https://github.com/godotengine/godot) | **MIT** | Sim, o runtime vai dentro do APK |

## Cores libretro — nós NÃO distribuímos nenhum

Os cores são o motor de emulação de cada console. **Este projeto não empacota nenhum deles**: o
APK sai sem cores e quem instala fornece os seus (ver a seção de cores no
[README](README.md#baixar-os-cores)).

Isso não é economia de espaço, é a razão de ser desta seção:

| Core | Consoles | Licença | Por que importa |
|---|---|---|---|
| snes9x | SNES | Licença Snes9x — **veda uso comercial**. Não é OSI, e é incompatível com GPL | Não pode ser vendido nem combinado com GPL |
| genesis_plus_gx | Mega Drive, Sega CD | Licença própria (Charles MacDonald / Eke-Eke) — **veda uso comercial**, incompatível com GPL | Idem |
| mupen64plus-next | Nintendo 64 | **GPL** | Distribuir o binário criaria dever de fornecer o fonte correspondente |
| melonDS | Nintendo DS | **GPL-3.0** | Idem |

Três consequências de empacotá-los, e é por isso que não empacotamos:

1. **GPL contra não-comercial.** snes9x e genesis_plus_gx vedam uso comercial; mupen64plus e
   melonDS são GPL. As duas condições não convivem num mesmo pacote sem que alguém tenha de
   sustentar publicamente o argumento de "mera agregação".
2. **GPL contra o Oculus SDK.** A GPLv3 proíbe restrições adicionais, e o loader da Meta é
   proprietário e vive no mesmo processo.
3. **O dever de fornecer o fonte.** Os cores vêm do buildbot *nightly* da libretro — alvo móvel,
   sem commit fixo a apontar. É uma obrigação impossível de cumprir com aquele binário.

Com os cores fora do pacote, os três desaparecem juntos, e o papel deste app fica o que sempre
foi de fato: um host que abre por `dlopen` um core que **o usuário** obteve. É o mesmo modelo do
RetroArch, que também não embute core no frontend.

O `libretro.h` ser MIT (e não GPL) é justamente o que permite isso: a API é aberta de propósito
para que hosts de qualquer licença a implementem.

## ROMs

Nenhuma ROM é versionada aqui, e nenhuma vai no APK — o `.gitignore` barra as extensões de
cartucho e imagem de disco. Jogos são obra de terceiros e quem instala usa os seus.

## BIOS

Nenhum arquivo de BIOS é versionado nem distribuído. O Sega CD exige a BIOS do Mega CD, que é
propriedade da Sega e tem de vir do usuário.
