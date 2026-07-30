#!/usr/bin/env bash
# Gera o APK de release assinado com a chave do projeto.
#
# Existe por dois motivos concretos:
#
# 1. Em `--headless` o Godot **não instancia as EditorSettings**, que é onde o
#    keystore fica configurado quando se exporta pelo editor. Sem passar os três
#    valores por variável de ambiente, o export falha com "Você deve configurar:
#    uma Keystore de Lançamento, OU Usuário e Senha de Lançamento, OU nenhum
#    deles" — a reclamação é de configuração *parcial*, e some quando os três
#    chegam juntos.
# 2. A linha de comando equivalente tem mais de 400 caracteres e quebra ao ser
#    colada num terminal, perdendo variáveis pelo caminho. Foi assim que o erro
#    acima apareceu duas vezes seguidas parecendo outra coisa.
#
# A senha é pedida na hora e nunca vai para o histórico do shell nem para o repo.
set -euo pipefail

cd "$(dirname "$0")/.."
RAIZ="$PWD"

export JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/java-17-openjdk-amd64}"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}"
export ANDROID_SDK_ROOT="$ANDROID_HOME"

# A chave mora fora de `app/android/` de propósito: aquela pasta é o template de
# build do Godot e é apagada ao ser reinstalada. Ver .gitignore.
KEYSTORE="$RAIZ/android/meta_quest.keystore"
ALIAS="${QUESTRETRO_ALIAS:-questretro}"
SAIDA="${1:-$RAIZ/dist/questretro-vr-release.apk}"

if [ ! -f "$KEYSTORE" ]; then
	echo "erro: keystore não encontrada em $KEYSTORE" >&2
	echo "gere com:" >&2
	echo "  cd $RAIZ/android && keytool -genkeypair -keystore meta_quest.keystore \\" >&2
	echo "      -alias $ALIAS -keyalg RSA -keysize 4096 -validity 10950 \\" >&2
	echo "      -dname CN=QuestRetro,O=MrVeGGi3,C=BR" >&2
	exit 1
fi

export GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$KEYSTORE"
export GODOT_ANDROID_KEYSTORE_RELEASE_USER="$ALIAS"

# A senha vem da variável, se houver, ou é pedida no terminal.
#
# Ler de `/dev/tty` explicitamente, e não da entrada padrão: rodado de dentro de
# outra ferramenta o script pode não ter stdin, e aí o `read` falha na hora —
# com `set -e`, isso encerrava tudo **sem imprimir nada**, o que parece o script
# não ter rodado. Melhor dizer o que fazer do que sumir.
# `[ -r /dev/tty ]` **não** basta: o arquivo existe e passa no teste mesmo quando
# não há terminal por trás, e a leitura só falha depois. Abrir de verdade é o
# único teste que vale.
ARQ_SENHA="$RAIZ/android/.senha-keystore"

if [ -f "$ARQ_SENHA" ]; then
	# Arquivo local, ignorado pelo git. É a forma preferida quando o script roda
	# de dentro de outra ferramenta: a senha não passa por linha de comando, não
	# entra no histórico do shell e não fica registrada em transcrição nenhuma.
	GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="$(head -n1 "$ARQ_SENHA")"
elif [ -n "${QUESTRETRO_SENHA:-}" ]; then
	GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="$QUESTRETRO_SENHA"
elif { exec 3</dev/tty; } 2>/dev/null; then
	read -rsp "Senha da keystore ($ALIAS): " GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD <&3
	exec 3<&-
	echo
else
	echo "erro: sem terminal para pedir a senha." >&2
	echo "guarde-a num arquivo local (não vai para o git):" >&2
	echo "  printf '%s\\n' 'sua-senha' > $ARQ_SENHA && chmod 600 $ARQ_SENHA" >&2
	echo "ou passe na variável:" >&2
	echo "  QUESTRETRO_SENHA='sua-senha' $0" >&2
	exit 1
fi
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD

mkdir -p "$(dirname "$SAIDA")"
godot --headless --path app --export-release "Quest (Meta)" "$SAIDA"

echo
echo "APK: $SAIDA"
# Conferir a assinatura aqui, e não depois: um APK assinado com a chave errada
# instala normalmente e só revela o problema quando a **próxima** versão for
# recusada por assinatura incompatível — com os saves de todo mundo no meio.
APKSIGNER="$(ls "$ANDROID_HOME"/build-tools/*/apksigner 2>/dev/null | tail -1 || true)"
if [ -n "$APKSIGNER" ]; then
	"$APKSIGNER" verify --print-certs "$SAIDA" | grep -i "certificate DN" || true
fi
