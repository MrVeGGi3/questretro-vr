#!/usr/bin/env bash
# Gera a capa da página da itch.io, em 630x500.
#
# A medida não é escolha: é a que a itch pede, e ela reduz a imagem para ~315x250
# na vitrine. Por isso o texto é grande e o rodapé fica longe da borda — o que
# cabe justo em 630 some no thumbnail, que é onde a maioria vê a página.
#
# As cores saem do tema do próprio app (app/scripts/ui/tema.gd), e o ciano é o
# neon do salão de arcade. A arte é o logo do projeto; nada aqui é de terceiros.
set -euo pipefail

cd "$(dirname "$0")/.."
SAIDA="${1:-docs/loja/capa-itch.png}"
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

convert -size 630x500 gradient:'#221f2b'-'#0e0c12' "$TMP/bg.png"

# Brilho atrás do logo. Sem ele o logo flutua num fundo chapado e a capa parece
# um slide, não uma capa.
convert -size 630x500 xc:none -fill '#9a85e8' -draw 'circle 315,150 315,255' \
	-blur 0x60 -channel A -evaluate multiply 0.22 +channel "$TMP/glow.png"

convert app/assets/logo.png -resize 200x200 "$TMP/logo.png"

mkdir -p "$(dirname "$SAIDA")"
convert "$TMP/bg.png" "$TMP/glow.png" -composite \
	\( "$TMP/logo.png" \) -geometry +215+48 -composite \
	-font "$FB" -pointsize 68 -fill '#efecf4' -gravity north -annotate +0+262 'QuestRetro' \
	-font "$FR" -pointsize 24 -fill '#9a85e8' -gravity north -annotate +0+345 'emulador VR para Meta Quest' \
	-fill '#2ce8e8' -draw 'rectangle 260,400 370,403' \
	-font "$FB" -pointsize 20 -fill '#b8b0c8' -gravity north -annotate +0+425 'SNES · N64 · MEGA DRIVE · SEGA CD · DS' \
	"$SAIDA"

echo "capa: $SAIDA"
identify "$SAIDA"
