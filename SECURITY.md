# Segurança / Security

## Como reportar

Use o **[Report a vulnerability](https://github.com/MrVeGGi3/questretro-vr/security/advisories/new)**
do GitHub, que abre um canal privado. Não abra issue pública para falha de
segurança.

Use GitHub's **Report a vulnerability** button (link above) — it opens a private
channel. Please don't file a public issue for a security problem.

## A superfície, para você saber o que faz sentido reportar

O app é um host de emulação que roda offline. O que ele de fato faz:

- **Rede:** um único uso — baixar cores da libretro (`buildbot.libretro.com`), por
  HTTPS, **sempre a pedido** e nunca automaticamente. A permissão `INTERNET` existe
  só para isso. Nada é enviado a lugar nenhum: sem telemetria, sem analytics, sem
  conta, sem servidor deste projeto.
- **Armazenamento:** lê ROMs e cores de `/sdcard`, e escreve saves, save states e
  configuração. Precisa da permissão de "todos os arquivos" porque as ROMs são suas
  e ficam onde você as pôs.
- **`dlopen` de código de terceiros:** é o modelo do projeto — o core que você
  baixou roda no processo do app, com os privilégios dele. Um core adulterado é
  código arbitrário no seu headset, e é por isso que a página Cores busca do
  buildbot oficial da libretro e não de espelhos.

The app runs offline. Its only network use is downloading libretro cores over HTTPS,
always on request; nothing is ever uploaded, and there is no telemetry, no account
and no server belonging to this project. It reads ROMs and cores from `/sdcard` and
`dlopen`s third-party cores into its own process — by design, which is why the Cores
page fetches from libretro's official buildbot and not from mirrors.

## Escopo

Vale reportar: qualquer coisa que rode código que você não pediu, que exponha seus
arquivos para fora do aparelho, ou que faça o app buscar core de origem que não seja
o buildbot da libretro.

Não é deste projeto: falhas dentro dos cores libretro (reporte no core), do Godot,
do runtime OpenXR da Meta ou do sistema do Quest.
