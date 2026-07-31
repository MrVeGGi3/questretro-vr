#!/usr/bin/env bash
# Gera as três peças de arte da página da itch.io: capa, banner e fundo.
#
# A capa é composição (ImageMagick). O banner e o fundo são **renders do salão
# de arcade de verdade** — o mesmo `Sala.aplicar(Sala.FLIPERAMA)` que roda no
# headset, por `app/scripts/loja/banner_sala.gd`. É de propósito: a página
# promete "um fliperama que cabe no seu quarto", e a arte que sustenta a
# promessa é a coisa em si, não um desenho parecido com ela.
#
# Uso:  tools/gerar-arte-itch.sh
set -euo pipefail

cd "$(dirname "$0")/.."
SAIDA="${1:-docs/loja}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FB=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf
FR=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf

for f in "$FB" "$FR"; do
	if [ ! -f "$f" ]; then
		echo "erro: fonte não encontrada: $f (instale fonts-dejavu)" >&2
		exit 1
	fi
done
command -v convert >/dev/null || { echo "erro: ImageMagick não instalado" >&2; exit 1; }

mkdir -p "$SAIDA"

# ---------------------------------------------------------------- capa (630x500)
#
# A medida não é escolha: é a que a itch pede, e ela reduz para ~315x250 na
# vitrine. Por isso o texto é grande e o rodapé fica longe da borda — o que cabe
# justo em 630 some no thumbnail, que é onde a maioria vê a página.
#
# As cores saem do tema do próprio app (app/scripts/ui/tema.gd), e o ciano é o
# neon do salão. A arte é o logo do projeto; nada aqui é de terceiros.
convert -size 630x500 gradient:'#221f2b'-'#0e0c12' "$TMP/bg.png"

# Brilho atrás do logo. Sem ele o logo flutua num fundo chapado e a capa parece
# um slide, não uma capa.
convert -size 630x500 xc:none -fill '#9a85e8' -draw 'circle 315,150 315,255' \
	-blur 0x60 -channel A -evaluate multiply 0.22 +channel "$TMP/glow.png"

convert app/assets/logo.png -resize 200x200 "$TMP/logo.png"

convert "$TMP/bg.png" "$TMP/glow.png" -composite \
	\( "$TMP/logo.png" \) -geometry +215+48 -composite \
	-font "$FB" -pointsize 68 -fill '#efecf4' -gravity north -annotate +0+262 'QuestRetro' \
	-font "$FR" -pointsize 24 -fill '#9a85e8' -gravity north -annotate +0+345 'emulador VR para Meta Quest' \
	-fill '#2ce8e8' -draw 'rectangle 260,400 370,403' \
	-font "$FB" -pointsize 20 -fill '#b8b0c8' -gravity north -annotate +0+425 'SNES · N64 · MEGA DRIVE · SEGA CD · DS' \
	"$SAIDA/capa-itch.png"
echo "capa  : $SAIDA/capa-itch.png"

# ------------------------------------------------- banner e fundo (renderizados)
if ! command -v godot >/dev/null; then
	echo "aviso: godot não encontrado — banner e fundo não foram gerados." >&2
	echo "a capa acima está pronta; rode de novo com o godot no PATH." >&2
	exit 0
fi

# `xvfb-run` porque o render precisa de contexto de GL: em `--headless` puro o
# SubViewport sai preto, e sem erro nenhum no log.
CORRE="godot"
command -v xvfb-run >/dev/null && CORRE="xvfb-run -a godot"

USUARIO="$HOME/.local/share/godot/app_userdata/QuestRetro"

$CORRE --xr-mode off --path app -s res://scripts/loja/banner_sala.gd \
	-- --tamanho 1920x480 --nome banner_sala >/dev/null 2>&1
$CORRE --xr-mode off --path app -s res://scripts/loja/banner_sala.gd \
	-- --tamanho 1920x1080 --nome fundo_sala >/dev/null 2>&1

for f in banner_sala fundo_sala; do
	if [ ! -f "$USUARIO/$f.png" ]; then
		echo "erro: o render não produziu $USUARIO/$f.png" >&2
		echo "rode o script do Godot à mão para ver o log." >&2
		exit 1
	fi
done

# Banner: só o wordmark. O tagline **não** entra aqui — a itch já o imprime logo
# abaixo do banner, e na imagem ele ainda cairia em cima das linhas de neon que
# convergem, que é o pior lugar possível para texto claro.
convert "$USUARIO/banner_sala.png" \
	-font "$FB" -pointsize 62 -fill '#efecf4' -gravity north -annotate +0+52 'QuestRetro' \
	"$SAIDA/banner-itch.png"
echo "banner: $SAIDA/banner-itch.png"

# Fundo: escurecido e desfocado com força. A coluna de conteúdo da itch tem
# ~960px e fica por cima disto — um fundo com contraste real transforma texto
# longo em algo cansativo de ler, e a página é quase toda texto.
convert "$USUARIO/fundo_sala.png" -blur 0x8 -modulate 42 \
	-fill '#0e0c12' -colorize 45% "$SAIDA/fundo-itch.png"
echo "fundo : $SAIDA/fundo-itch.png"

identify "$SAIDA"/capa-itch.png "$SAIDA"/banner-itch.png "$SAIDA"/fundo-itch.png
