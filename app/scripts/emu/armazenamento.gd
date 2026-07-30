class_name Armazenamento
extends RefCounted
## Onde ficam os arquivos que **o usuário** fornece — hoje os cores, a seguir a
## BIOS. Só caminhos e busca; quem desenha é a página do menu.
##
## Não mora em `NavegadorRoms` porque aquele arquivo é "listagem de ROMs, só
## lógica" pelo próprio docstring, e core não é ROM. Os consumidores aqui são o
## `EmuCore` e o menu.
##
## **A pasta é `/sdcard/QuestRetro`, e não a pasta externa do app.** A externa
## (`/sdcard/Android/data/<pacote>/files`) dispensa permissão, o que a torna
## tentadora — mas o Android **esconde `Android/data`** do MTP e do gerenciador de
## arquivos do Quest, então só se chega nela por `adb push`. Quem instala o APK não
## tem `adb`, e é exatamente essa pessoa que este caminho existe para atender.
## `navegador_roms.gd` já registra a limitação; aqui ela é a razão da escolha.
##
## O preço é a `MANAGE_EXTERNAL_STORAGE` — **a mesma** que as ROMs já exigem, com o
## mesmo botão e o mesmo banner da página de ROMs. Nenhuma permissão nova entra.
##
## Fora do Android isto não vale: `res://cores` é diretório de verdade e o fluxo de
## desenvolvimento já põe os cores lá (ver "Baixar os cores" no README).

## Nome escolhido para aparecer legível na raiz do armazenamento quando a pessoa
## liga o headset no PC. Fica ao lado de `Download` e `ROMs`, não escondido.
const BASE := "/sdcard/QuestRetro"
const SUB_CORES := "cores"
## BIOS e firmware que o core procura. O nome é `system` porque é assim que a
## própria libretro chama (`GET_SYSTEM_DIRECTORY`), e é o nome que qualquer
## instrução de emulação na internet vai usar — inventar um diferente só faria a
## pessoa procurar no lugar errado.
const SUB_SYSTEM := "system"
const NOME_OPCOES := "opcoes_core.cfg"

## Também procuramos aqui: é onde o navegador do headset baixa, e é razoável que
## alguém deixe o `.so` onde ele caiu em vez de mover.
const EXTRA_BUSCA := "/sdcard/Download"


static func ativo() -> bool:
	return OS.has_feature("android")


static func base() -> String:
	return BASE if ativo() else ""


static func cores() -> String:
	return BASE.path_join(SUB_CORES) if ativo() else ""


## Pasta de BIOS/firmware. "" fora do Android, e aí quem chama fica no
## `user://system` do motor — que no desktop é alcançável e resolve.
static func sistema() -> String:
	return BASE.path_join(SUB_SYSTEM) if ativo() else ""


## Cria as pastas para elas **aparecerem** quando a pessoa ligar o USB: pasta que
## existe é descobrível, caminho escrito no README não é.
##
## Falha em silêncio quando a permissão não está concedida, de propósito. Quem
## explica a permissão é o banner da página de ROMs; um `push_error` no arranque
## poluiria o log de todo mundo que ainda não passou pelos Ajustes, e o arranque é
## justamente onde ninguém pediu nada ainda.
## Cria **as duas** de uma vez, e de propósito: a pessoa liga o USB uma vez só, e
## uma pasta que só aparece depois de ela já ter procurado não serve de dica.
static func garantir() -> bool:
	if not ativo():
		return false
	var ok := true
	for alvo in [cores(), sistema()]:
		if DirAccess.dir_exists_absolute(alvo):
			continue
		if DirAccess.make_dir_recursive_absolute(alvo) != OK:
			ok = false
	return ok


## Sobrescrita de opções na pasta do usuário, se ela existir. "" quando não há —
## e aí quem chama cai no `user://`, que em release não é alcançável por ninguém.
##
## É o mesmo problema dos cores: `user://` só se escreve por `run-as`, que existe
## só em build debug. Sem isto, trocar uma opção de core num APK release é
## impossível — nem para quem instalou, nem para quem quer medir.
static func arquivo_opcoes() -> String:
	if not ativo():
		return ""
	var caminho := BASE.path_join(NOME_OPCOES)
	return caminho if FileAccess.file_exists(caminho) else ""


## Procura um core pelo nome de arquivo. "" se não achou.
static func procurar_core(nome_arquivo: String) -> String:
	if not ativo() or nome_arquivo.is_empty():
		return ""
	for pasta in [cores(), EXTRA_BUSCA]:
		var caminho: String = pasta.path_join(nome_arquivo)
		if FileAccess.file_exists(caminho):
			return caminho
	return ""
