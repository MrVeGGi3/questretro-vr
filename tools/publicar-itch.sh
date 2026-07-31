#!/usr/bin/env bash
# Sobe o APK de release para a itch.io, pelo butler.
#
# Roda **desta máquina**, e não da CI, pela mesma razão que o export: a
# assinatura exige a keystore, que por desenho nunca sai daqui (ver .gitignore).
# Um workflow que assinasse no GitHub precisaria da chave como secret, e aí ela
# passaria a existir em mais um lugar — que é exatamente o que se quer evitar.
#
# Uso:
#   tools/exportar-release.sh && tools/publicar-itch.sh
set -euo pipefail

cd "$(dirname "$0")/.."
RAIZ="$PWD"

APK="${1:-$RAIZ/dist/questretro-vr-release.apk}"
ALVO="${QUESTRETRO_ITCH:-veggi3/questretro-vr}"

# O canal **precisa** conter "android": é dele que a itch infere a plataforma do
# arquivo. Num canal chamado "quest" o APK sobe, aparece na página e **não**
# recebe a marca de Android — quem entra pelo app da itch não vê botão de
# instalar, e o sintoma não menciona canal nenhum.
CANAL="android"

if [ ! -f "$APK" ]; then
	echo "erro: APK não encontrado em $APK" >&2
	echo "gere antes com: tools/exportar-release.sh" >&2
	exit 1
fi

# A versão sai do export_presets, e não é digitada aqui: dois lugares para o
# mesmo número é o jeito de publicar "0.1.0" com o binário do 0.2.0.
VERSAO="$(grep -oP 'version/name="\K[^"]+' "$RAIZ/app/export_presets.cfg")"
if [ -z "$VERSAO" ]; then
	echo "erro: não achei version/name em app/export_presets.cfg" >&2
	exit 1
fi

# Conferir a assinatura antes de subir, e não depois. Um APK assinado com a
# chave errada instala normalmente e só se revela quando a **próxima** versão
# for recusada por assinatura incompatível — com os saves de todo mundo no meio.
# Na itch isso é pior que no GitHub: quem baixou de lá atualiza pelo app, e a
# atualização é justamente o que quebra.
ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}"
APKSIGNER="$(ls "$ANDROID_HOME"/build-tools/*/apksigner 2>/dev/null | tail -1 || true)"
if [ -n "$APKSIGNER" ]; then
	if ! "$APKSIGNER" verify --print-certs "$APK" | grep -qi "CN=QuestRetro"; then
		echo "erro: $APK não está assinado com a chave do projeto." >&2
		echo "refaça com tools/exportar-release.sh antes de publicar." >&2
		exit 1
	fi
	echo "assinatura: ok (CN=QuestRetro)"
else
	echo "aviso: apksigner não encontrado; assinatura não conferida." >&2
fi

echo "sha256: $(sha256sum "$APK" | cut -d' ' -f1)"
echo "subindo $VERSAO para $ALVO:$CANAL"

butler push "$APK" "$ALVO:$CANAL" --userversion "$VERSAO"

echo
butler status "$ALVO"
echo
echo "página: https://${ALVO%%/*}.itch.io/${ALVO##*/}"
