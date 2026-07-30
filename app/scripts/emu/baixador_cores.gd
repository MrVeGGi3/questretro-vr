class_name BaixadorCores
extends Node
## Busca um core libretro do buildbot oficial, a pedido da pessoa. Sem UI: quem
## desenha é `PagCores`.
##
## **Por que baixar é diferente de empacotar.** O APK não traz core nenhum, e a
## razão está em `THIRD-PARTY.md`: snes9x e genesis_plus_gx vedam uso comercial,
## mupen64plus-next e melonDS são GPL, e as duas condições não convivem num mesmo
## pacote. Nada disso muda aqui, porque **um download não cria pacote**: quem
## distribui o binário é o buildbot da libretro, e o dever de fornecer o fonte
## correspondente é de lá. É o mesmo modelo do RetroArch, que também não embute
## core e também oferece um baixador.
##
## O que sustenta essa leitura é a regra que este arquivo existe para cumprir: o
## download é **sempre pedido pela pessoa**, nunca automático, e a licença de cada
## core aparece antes do botão. Sem isso, "o usuário obteve" deixaria de ser
## verdade — e é dessa frase que a análise inteira depende.
##
## Nenhuma lista nova para manter: os nomes de arquivo saem de `EmuCore.CORES`, e
## a URL é o mesmo nome com `.zip`. Console novo aparece aqui sozinho.

## Um core baixado com sucesso. `caminho` é o `.so` final, já no lugar.
signal concluido(sistema: String, caminho: String)
signal falhou(sistema: String, msg: String)
## `total` vem 0 quando o servidor não manda Content-Length.
signal progresso(sistema: String, recebido: int, total: int)

## O mesmo endereço que o README manda usar à mão. `arm64-v8a` fixo porque o
## preset exporta só essa ABI — montar a arquitetura por variável criaria URL
## para alvo que não existe.
const BASE := "https://buildbot.libretro.com/nightly/android/latest/arm64-v8a"

## Registro do que foi baixado, ao lado dos próprios cores. O nightly é alvo
## móvel: sem data e tamanho não há como saber, depois, qual binário está rodando
## quando um core começa a falhar.
const REGISTRO := "cores.cfg"

## Sufixo do arquivo em construção. Um `.so` truncado passaria no `file_exists` e
## falharia no `dlopen` — o formato de erro mais confuso que existe, e já custou
## uma investigação neste projeto. Nada chega ao nome final antes de estar inteiro.
const SUFIXO_PARCIAL := ".parcial"

## Licença de cada core, para a página mostrar **antes** de baixar. Resumo do que
## está por extenso em `THIRD-PARTY.md`; a intenção é que ninguém baixe sem saber
## o que está trazendo para dentro do aparelho.
const LICENCAS := {
	"snes": "CORES_LICENCA_SNES",
	"n64": "CORES_LICENCA_N64",
	"megadrive": "CORES_LICENCA_MEGADRIVE",
	"nds": "CORES_LICENCA_NDS",
}

var _http: HTTPRequest
var _sistema := ""
var _nome := ""
var _zip_tmp := ""


func _ready() -> void:
	_http = HTTPRequest.new()
	# Deixa o Godot escrever direto no disco em vez de acumular o corpo na RAM: um
	# core passa de 2 MB e o headset não tem memória sobrando durante um jogo.
	add_child(_http)
	_http.request_completed.connect(_ao_terminar)


## Nome do `.so` que este baixador busca. **Sempre o de Android**, e não o da
## plataforma corrente: `BASE` aponta para `android/latest/arm64-v8a`, então pedir
## o nome de desktop daria 404 num endereço que só publica o de Android. No
## aparelho os dois coincidem e o erro passaria despercebido — foi o teste de URL,
## rodando no desktop, que o mostrou.
static func nome_baixavel(sistema: String) -> String:
	return EmuCore.nome_do_core(sistema, "android")


## URL do core deste sistema. "" quando não conhecemos o sistema.
##
## Estática e sem rede de propósito: é o que permite conferir na CI que toda
## entrada de `EmuCore.CORES` gera endereço bem formado, sem baixar nada.
static func url_do_core(sistema: String) -> String:
	var nome := nome_baixavel(sistema)
	if nome.is_empty():
		return ""
	return "%s/%s.zip" % [BASE, nome]


## true enquanto há download em curso — a página usa para não deixar pedir dois.
func ocupado() -> bool:
	return not _sistema.is_empty()


func baixar(sistema: String) -> bool:
	if ocupado():
		return false
	var nome := nome_baixavel(sistema)
	var destino := Armazenamento.cores()
	if nome.is_empty() or destino.is_empty():
		falhou.emit(sistema, tr("BAIXADOR_SEM_CORE_PARA") % sistema)
		return false
	# `garantir()` não basta como teste de permissão: ele sai satisfeito quando a
	# pasta **já existe**, e ela sobrevive à desinstalação do app por morar em
	# `/sdcard`. Depois de reinstalar, a permissão volta a zero e a pasta continua
	# lá — então a checagem passava e a falha só aparecia lá na frente, como
	# `RESULT_DOWNLOAD_FILE_CANT_OPEN`, que a UI mostrava como "resultado 10".
	# Medido no Quest 3S, e o único jeito de saber se dá para escrever é escrever.
	Armazenamento.garantir()
	if not _da_para_gravar(destino):
		falhou.emit(sistema, tr("BAIXADOR_SEM_PERMISSAO"))
		return false

	_sistema = sistema
	_nome = nome
	_zip_tmp = destino.path_join("." + nome + ".zip" + SUFIXO_PARCIAL)
	_http.download_file = _zip_tmp

	var err := _http.request(url_do_core(sistema))
	if err != OK:
		_encerrar()
		falhou.emit(sistema, tr("BAIXADOR_FALHA") % err)
		return false
	set_process(true)
	return true


func cancelar() -> void:
	if not ocupado():
		return
	_http.cancel_request()
	var sis := _sistema
	_encerrar()
	falhou.emit(sis, tr("BAIXADOR_CANCELADO"))


func _process(_delta: float) -> void:
	if not ocupado():
		set_process(false)
		return
	progresso.emit(_sistema, _http.get_downloaded_bytes(), _http.get_body_size())


func _ao_terminar(resultado: int, codigo: int, _headers: PackedStringArray,
		_corpo: PackedByteArray) -> void:
	var sis := _sistema
	var nome := _nome
	var zip := _zip_tmp
	_encerrar()

	if resultado != HTTPRequest.RESULT_SUCCESS:
		_apagar(zip)
		falhou.emit(sis, _explicar(resultado))
		return
	if codigo != 200:
		_apagar(zip)
		# 404 aqui quase sempre quer dizer que o buildbot renomeou o arquivo — o
		# nightly muda, e o nome vem de `EmuCore.CORES`, que é nosso.
		falhou.emit(sis, tr("BAIXADOR_SERVIDOR") % [codigo, nome])
		return

	var final := Armazenamento.cores().path_join(nome)
	var msg := extrair(zip, nome, final)
	_apagar(zip)
	if not msg.is_empty():
		falhou.emit(sis, msg)
		return

	_registrar(sis, final)
	concluido.emit(sis, final)


## Tira o `.so` de dentro do zip e o põe em `destino`, inteiro ou nada.
##
## Devolve "" em caso de sucesso, ou a mensagem de erro. Estática e sem rede: a CI
## exercita os dois modos de falha com zips montados na hora.
##
## Procura pelo **nome**, e não pela primeira entrada: o buildbot já publicou
## pacote com o `.so` fora da raiz, e assumir posição daria core errado com nome
## certo.
static func extrair(zip_path: String, nome_so: String, destino: String) -> String:
	var z := ZIPReader.new()
	if z.open(zip_path) != OK:
		return TranslationServer.translate("BAIXADOR_ZIP_INVALIDO")

	var interno := ""
	for f: String in z.get_files():
		if f.get_file() == nome_so:
			interno = f
			break
	if interno.is_empty():
		z.close()
		return TranslationServer.translate("BAIXADOR_ZIP_SEM_SO") % nome_so

	var dados := z.read_file(interno)
	z.close()
	if dados.is_empty():
		return TranslationServer.translate("BAIXADOR_SO_VAZIO") % nome_so

	# Escreve em parcial e só então renomeia: é isto que garante que nunca exista
	# um `.so` de nome final pela metade, nem se o app morrer no meio da escrita.
	var parcial := destino + SUFIXO_PARCIAL
	var f := FileAccess.open(parcial, FileAccess.WRITE)
	if f == null:
		return TranslationServer.translate("BAIXADOR_SEM_ESCRITA") % parcial.get_base_dir()
	f.store_buffer(dados)
	f.close()

	if FileAccess.file_exists(destino):
		DirAccess.remove_absolute(destino)
	if DirAccess.rename_absolute(parcial, destino) != OK:
		DirAccess.remove_absolute(parcial)
		return TranslationServer.translate("BAIXADOR_SEM_MOVER") % destino
	return ""


## Restos de um download interrompido. No Quest o app **morre** ao ser pausado, e
## tirar o headset é como quase toda sessão termina — então isto não é higiene
## teórica: é o caso comum.
static func limpar_temporarios() -> void:
	var pasta := Armazenamento.cores()
	if pasta.is_empty():
		return
	var d := DirAccess.open(pasta)
	if d == null:
		return
	d.list_dir_begin()
	var nome := d.get_next()
	while not nome.is_empty():
		if nome.ends_with(SUFIXO_PARCIAL):
			d.remove(nome)
		nome = d.get_next()
	d.list_dir_end()


## Data e tamanho do que foi baixado, por sistema. Ver `REGISTRO`.
static func _registrar(sistema: String, caminho: String) -> void:
	var arquivo := Armazenamento.base().path_join(REGISTRO)
	if arquivo.is_empty():
		return
	var cfg := ConfigFile.new()
	cfg.load(arquivo)  # ausente é normal na primeira vez
	cfg.set_value(sistema, "arquivo", caminho.get_file())
	cfg.set_value(sistema, "baixado_em", Time.get_datetime_string_from_system(false, true))
	cfg.set_value(sistema, "bytes", _tamanho(caminho))
	cfg.save(arquivo)


static func _tamanho(caminho: String) -> int:
	var f := FileAccess.open(caminho, FileAccess.READ)
	if f == null:
		return 0
	var n := f.get_length()
	f.close()
	return int(n)


## Só se sabe se dá para gravar gravando: no Android a permissão de armazenamento
## não se lê por API que valha, e `dir_exists_absolute` responde true para pasta
## que existe mas está fora do alcance.
static func _da_para_gravar(pasta: String) -> bool:
	var teste := pasta.path_join(".escrita" + SUFIXO_PARCIAL)
	var f := FileAccess.open(teste, FileAccess.WRITE)
	if f == null:
		return false
	f.close()
	DirAccess.remove_absolute(teste)
	return true


## Traduz o código do HTTPRequest para algo que diga o que fazer.
##
## O número cru não serve para quem está dentro do headset: "resultado 10" é
## `RESULT_DOWNLOAD_FILE_CANT_OPEN`, que na prática quer dizer "a permissão de
## armazenamento não foi concedida" — e sem esta tradução a mensagem manda a
## pessoa procurar problema na internet dela.
static func _explicar(resultado: int) -> String:
	match resultado:
		HTTPRequest.RESULT_CANT_CONNECT, HTTPRequest.RESULT_CANT_RESOLVE:
			return TranslationServer.translate("BAIXADOR_SEM_INTERNET")
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
			return TranslationServer.translate("BAIXADOR_TLS")
		HTTPRequest.RESULT_TIMEOUT, HTTPRequest.RESULT_NO_RESPONSE:
			return TranslationServer.translate("BAIXADOR_SEM_RESPOSTA")
		HTTPRequest.RESULT_DOWNLOAD_FILE_CANT_OPEN, HTTPRequest.RESULT_DOWNLOAD_FILE_WRITE_ERROR:
			return TranslationServer.translate("BAIXADOR_SEM_PERMISSAO")
		_:
			return TranslationServer.translate("BAIXADOR_FALHA") % resultado


static func _apagar(caminho: String) -> void:
	if not caminho.is_empty() and FileAccess.file_exists(caminho):
		DirAccess.remove_absolute(caminho)


func _encerrar() -> void:
	_sistema = ""
	_nome = ""
	_zip_tmp = ""
	set_process(false)
