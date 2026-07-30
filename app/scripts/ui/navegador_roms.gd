class_name NavegadorRoms
extends RefCounted
## Listagem de ROMs no armazenamento. Só lógica — a página de ROMs desenha.
##
## No Quest as ROMs chegam por `adb push` ou pelo gerenciador de arquivos do
## headset, então precisamos ler /sdcard. E aí esbarramos no armazenamento por
## escopo do Android 11+: `READ_EXTERNAL_STORAGE` só dá acesso a **mídia**
## (imagem, áudio, vídeo). Uma ROM não é mídia, então com ela o app leva
## `Permission denied` em /sdcard inteiro — medido no Quest 3S, com a permissão
## concedida. Quem destrava tipo de arquivo arbitrário é MANAGE_EXTERNAL_STORAGE.
##
## Daí as duas vias, e as duas importam:
##   1. MANAGE_EXTERNAL_STORAGE, ligada uma vez pela pessoa em Ajustes. Cobre
##      /sdcard/Download, /sdcard/ROMs e o cartão inteiro.
##   2. A pasta externa do próprio app, que dispensa permissão e recebe
##      `adb push` direto. É a saída para quem não quer mexer em Ajustes — mas
##      não é alcançável por MTP nem pelo gerenciador do Quest, porque o Android
##      esconde `Android/data`.

## Extensão → sistema. É daqui que sai qual core carregar (ver
## `EmuCore.core_para_rom`) e qual mapa de controle vale (ver `xr_main`).
## `zip` fica no SNES porque é como as ROMs de SNES costumam circular; ROM de
## N64 zipada o mupen não abre, já que ele exige caminho de arquivo real.
## O `genesis_plus_gx` cobre cartucho de Mega Drive **e** disco de Sega CD, com o
## mesmo controle, então os dois caem no mesmo sistema: um core, um mapa de
## botões, um nome. O Sega CD é um add-on do Mega Drive, então chamar Sonic CD de
## "Mega Drive" na lista não é engano — é a máquina que roda o disco.
##
## `.bin` fica de fora de propósito, apesar de ser cartucho de Mega Drive válido:
## ele é também a faixa de dados que acompanha um `.cue`, e oferecer as duas
## coisas na mesma lista faria a pessoa escolher a faixa em vez do jogo. Quem tem
## `.bin` de cartucho renomeia para `.md`.
const SISTEMAS := {
	"smc": "snes", "sfc": "snes", "fig": "snes", "swc": "snes", "zip": "snes",
	"z64": "n64", "n64": "n64", "v64": "n64",
	"md": "megadrive", "gen": "megadrive", "smd": "megadrive",
	"chd": "megadrive", "cue": "megadrive",
	"nds": "nds",
}

## Nome que a interface mostra para cada sistema.
const NOMES_SISTEMA := {
	"snes": "SNES", "n64": "N64", "megadrive": "Mega Drive", "nds": "Nintendo DS",
}

## Sistemas cujo framebuffer traz **duas** telas empilhadas, e que por isso viram
## dois quads no espaço em vez de um. Ver `xr_main._aplicar_tela()`.
const DUAS_TELAS := ["nds"]


## Se este sistema tem duas telas.
static func tem_duas_telas(sistema: String) -> bool:
	return sistema in DUAS_TELAS

## Precisa casar com `package/unique_name` do preset em export_presets.cfg: o
## Godot 4.6 não expõe o nome do pacote em runtime, e é ele que forma o caminho
## da pasta externa do app.
const PACOTE := "com.questretro.vr"

## Tela geral de "acesso a todos os arquivos". A variante por app
## (MANAGE_APP_ALL_FILES_ACCESS_PERMISSION) não existe no Quest — resolve para
## "No activity found" —, então caímos na lista e a pessoa acha o app nela.
const ACAO_ACESSO_TOTAL := "android.settings.MANAGE_ALL_FILES_ACCESS_PERMISSION"


## Pastas oferecidas como ponto de partida. Só as que existem de fato, para a
## lista não mostrar caminho morto.
static func raizes() -> Array:
	var candidatas: Array
	if OS.has_feature("android"):
		candidatas = [
			{"nome": "Downloads", "caminho": "/sdcard/Download"},
			{"nome": "ROMs", "caminho": "/sdcard/ROMs"},
			{"nome": "Armazenamento", "caminho": "/sdcard"},
			# Esta funciona sem permissão nenhuma e é o destino do `adb push`.
			{"nome": "Pasta do app (adb)", "caminho": pasta_externa()},
			{"nome": "Dados do app", "caminho": ProjectSettings.globalize_path("user://roms")},
		]
	else:
		candidatas = [
			{"nome": "Dados do app", "caminho": ProjectSettings.globalize_path("user://roms")},
			{"nome": "Downloads", "caminho": OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)},
			{"nome": "Pasta pessoal", "caminho": OS.get_environment("HOME")},
		]

	var existentes: Array = []
	for c in candidatas:
		if not c.caminho.is_empty() and DirAccess.dir_exists_absolute(c.caminho):
			existentes.append(c)
	return existentes


## Conteúdo de uma pasta: subpastas primeiro, depois ROMs, cada grupo em ordem
## alfabética sem diferenciar maiúsculas. Devolve vazio se não deu para abrir.
static func listar(caminho: String) -> Array:
	var dir := DirAccess.open(caminho)
	if dir == null:
		push_warning("NavegadorRoms: não abriu %s (erro %d)" % [caminho, DirAccess.get_open_error()])
		return []

	var pastas: Array = []
	var arquivos: Array = []

	dir.list_dir_begin()
	var nome := dir.get_next()
	while not nome.is_empty():
		if not nome.begins_with("."):
			var completo := caminho.path_join(nome)
			if dir.current_is_dir():
				pastas.append({"nome": nome, "caminho": completo, "pasta": true, "tamanho": 0})
			elif SISTEMAS.has(nome.get_extension().to_lower()):
				arquivos.append({
					"nome": nome, "caminho": completo, "pasta": false,
					"tamanho": _tamanho(completo),
					"sistema": sistema_de(completo),
				})
		nome = dir.get_next()
	dir.list_dir_end()

	var por_nome := func(a: Dictionary, b: Dictionary) -> bool:
		return a.nome.nocasecmp_to(b.nome) < 0
	pastas.sort_custom(por_nome)
	arquivos.sort_custom(por_nome)
	return pastas + arquivos


## Sistema de uma ROM pela extensão, ou "" se não reconhecemos o arquivo.
static func sistema_de(caminho: String) -> String:
	return SISTEMAS.get(caminho.get_extension().to_lower(), "")


## Nome legível do sistema, para a lista de ROMs e a página de Input.
static func nome_sistema(sistema: String) -> String:
	return NOMES_SISTEMA.get(sistema, sistema.to_upper())


## Caminho da pasta acima, ou vazio se já estamos numa raiz do sistema.
static func acima(caminho: String) -> String:
	var pai := caminho.get_base_dir()
	if pai.is_empty() or pai == caminho:
		return ""
	return pai


static func formatar_tamanho(bytes: int) -> String:
	if bytes >= 1024 * 1024:
		return "%.1f MB" % (bytes / 1048576.0)
	if bytes >= 1024:
		return "%d KB" % (bytes / 1024)
	return "%d B" % bytes


## Pasta externa do app: `/sdcard/Android/data/<pacote>/files/roms`. O app lê e
## escreve nela sem permissão alguma, e o `adb push` alcança de fora.
static func pasta_externa() -> String:
	return "/sdcard/Android/data/%s/files/roms" % PACOTE


static func precisa_permissao() -> bool:
	return OS.has_feature("android")


## Só MANAGE_EXTERNAL_STORAGE vale aqui. READ_EXTERNAL_STORAGE fica concedida e
## mesmo assim não abre uma ROM, então perguntar por ela enganaria a interface.
static func tem_permissao() -> bool:
	if not precisa_permissao():
		return true
	var ambiente := JavaClassWrapper.wrap("android.os.Environment")
	if ambiente == null:
		push_warning("NavegadorRoms: sem android.os.Environment")
		return false
	return ambiente.isExternalStorageManager()


## Abre a tela de Ajustes do Android onde a chave é ligada. Não há diálogo de
## runtime para esta permissão: é uma viagem à lista de Ajustes e volta, e a
## página relê o estado ao reabrir.
static func pedir_permissao() -> void:
	if not precisa_permissao():
		return
	var runtime := Engine.get_singleton("AndroidRuntime")
	if runtime == null:
		push_warning("NavegadorRoms: sem o singleton AndroidRuntime")
		return
	var intent_cls := JavaClassWrapper.wrap("android.content.Intent")
	if intent_cls == null:
		push_warning("NavegadorRoms: sem android.content.Intent")
		return
	# O construtor Java é exposto pelo nome simples da classe, não por `new`:
	# `Intent.Intent(acao)` é o `new Intent(action)`.
	var intent: Variant = intent_cls.Intent(ACAO_ACESSO_TOTAL)
	if intent == null:
		push_warning("NavegadorRoms: não construí o Intent (%s)" % JavaClassWrapper.get_exception())
		return
	runtime.getActivity().startActivity(intent)
	# Sem isto, uma ActivityNotFoundException viraria um botão que não faz nada.
	var erro: Variant = JavaClassWrapper.get_exception()
	if erro != null:
		push_warning("NavegadorRoms: startActivity falhou: %s" % erro)


## Garante que as pastas próprias existam, para haver sempre um destino gravável
## e uma raiz válida mesmo sem permissão nenhuma.
static func garantir_pasta_local() -> void:
	if not DirAccess.dir_exists_absolute("user://roms"):
		DirAccess.make_dir_recursive_absolute("user://roms")
	# A externa some quando o app é desinstalado, então recriamos sempre.
	if precisa_permissao() and not DirAccess.dir_exists_absolute(pasta_externa()):
		DirAccess.make_dir_recursive_absolute(pasta_externa())
	# As pastas do usuário — cores e BIOS —, que ao contrário das duas de cima são
	# alcançáveis de fora do headset. Depende da permissão, então falha calada
	# aqui e passa a funcionar assim que a pessoa a concede — ver
	# `Armazenamento.garantir()`.
	#
	# No arranque, e não na primeira carga de core: pasta que existe é descobrível,
	# e quem for procurar onde pôr a BIOS tem de achá-la antes de conseguir abrir
	# um jogo, não depois.
	Armazenamento.garantir()
	# Restos de download interrompido. No Quest o app morre ao ser pausado, e tirar
	# o headset é como quase toda sessão termina — então o arranque é o único lugar
	# confiável para varrer isto.
	BaixadorCores.limpar_temporarios()


static func _tamanho(caminho: String) -> int:
	var f := FileAccess.open(caminho, FileAccess.READ)
	return f.get_length() if f != null else 0
