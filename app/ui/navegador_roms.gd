class_name NavegadorRoms
extends RefCounted
## Listagem de ROMs no armazenamento. Só lógica — a página de ROMs desenha.
##
## No Quest as ROMs chegam por `adb push` ou pelo gerenciador de arquivos do
## headset, então precisamos ler /sdcard. No Android 11+ o acesso por caminho
## de arquivo em armazenamento compartilhado volta a funcionar com
## READ_EXTERNAL_STORAGE, então DirAccess basta — sem MediaStore.

const EXTENSOES := ["smc", "sfc", "fig", "swc", "zip"]  ## o que o snes9x aceita

const PERMISSAO := "android.permission.READ_EXTERNAL_STORAGE"


## Pastas oferecidas como ponto de partida. Só as que existem de fato, para a
## lista não mostrar caminho morto.
static func raizes() -> Array:
	var candidatas: Array
	if OS.has_feature("android"):
		candidatas = [
			{"nome": "Downloads", "caminho": "/sdcard/Download"},
			{"nome": "ROMs", "caminho": "/sdcard/ROMs"},
			{"nome": "Armazenamento", "caminho": "/sdcard"},
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
			elif nome.get_extension().to_lower() in EXTENSOES:
				arquivos.append({
					"nome": nome, "caminho": completo, "pasta": false,
					"tamanho": _tamanho(completo),
				})
		nome = dir.get_next()
	dir.list_dir_end()

	var por_nome := func(a: Dictionary, b: Dictionary) -> bool:
		return a.nome.nocasecmp_to(b.nome) < 0
	pastas.sort_custom(por_nome)
	arquivos.sort_custom(por_nome)
	return pastas + arquivos


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


static func precisa_permissao() -> bool:
	return OS.has_feature("android")


static func tem_permissao() -> bool:
	if not precisa_permissao():
		return true
	return PERMISSAO in OS.get_granted_permissions()


## Dispara o diálogo do Android. A resposta é assíncrona e chega no
## `on_request_permissions_result` do MainLoop; a página re-checa ao reabrir.
static func pedir_permissao() -> void:
	if precisa_permissao():
		OS.request_permissions()


## Garante que user://roms exista, para haver sempre um destino gravável e uma
## raiz válida mesmo sem permissão nenhuma.
static func garantir_pasta_local() -> void:
	if not DirAccess.dir_exists_absolute("user://roms"):
		DirAccess.make_dir_recursive_absolute("user://roms")


static func _tamanho(caminho: String) -> int:
	var f := FileAccess.open(caminho, FileAccess.READ)
	return f.get_length() if f != null else 0
