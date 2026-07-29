class_name BibliotecaRoms
extends RefCounted
## A biblioteca: todo jogo reconhecido no aparelho, com título legível, agrupado
## por console. Só lógica — a página de ROMs desenha.
##
## Existe porque navegar em pastas não escala. Quem instala o APK despeja as ROMs
## em /sdcard/Download misturadas com o resto, não tem `adb` para arrumá-las, e
## precisa reconhecer o jogo em
## `5478 - Ghost Trick - Phantom Detective (USA) (En,Fr,De,Es,It).nds` apontando
## um laser. A varredura acha os arquivos onde estiverem, uma vez, e a lista
## passa a ser de jogos em vez de arquivos.
##
## Sem nenhuma dependência de XR ou de UI, como `guidao.gd`, `mapa_input.gd` e
## `caneta_ds.gd` — é o que permite testar sem headset a família de erro que só
## apareceria lá: jogo faltando na lista, título vazio, varredura que perde
## estado ao ceder o frame.

## Índice em disco. JSON, e não ConfigFile, porque isto é uma **lista de
## registros** e o ConfigFile é chave→valor por seção. É o primeiro uso de JSON
## no projeto.
const ARQUIVO := "user://biblioteca.json"

## Sobe quando o formato do registro muda. Índice de versão diferente é
## descartado em vez de lido meio errado — um campo que virou outra coisa daria
## lista torta sem erro nenhum.
const VERSAO := 1

## Fundo de poço da varredura. Uma raiz como /sdcard tem a árvore inteira do
## aparelho embaixo, e ROM não costuma morar a seis pastas de profundidade.
const PROFUNDIDADE_MAX := 6

## Teto de itens. Bater nele é avisado na tela — a lista truncada em silêncio
## seria indistinguível de ROM que a varredura não achou.
const TETO_ITENS := 4000

## Quantas entradas processar entre duas consultas ao relógio. Consultar a cada
## arquivo custaria mais que o trabalho medido.
const LOTE := 64

## Extensões que também são de arquivo do dia a dia, e que por isso sozinhas não
## dizem que aquilo é uma ROM. Só a **varredura** desconfia delas: no modo Pastas
## quem abriu a pasta foi a pessoa, e lá a lista mostra o que estiver lá — é
## justamente a saída para o dump esquisito que o teste abaixo recusar.
##
## `.md` é Mega Drive e é Markdown. Numa varredura do aparelho inteiro isso não é
## detalhe: na máquina onde isto foi escrito, varrer /home devolveu **1161 jogos
## de Mega Drive**, e todos eram documentação de repositório. Um teto de tamanho
## não resolveria — há `CHANGELOG.md` maior que cartucho.
##
## `.zip` é ROM de SNES compactada (ver `NavegadorRoms.SISTEMAS`) e é qualquer
## outra coisa compactada. Em Downloads eram seis zips, nenhum deles jogo.
const AMBIGUAS := ["md", "zip"]

## Onde o cartucho de Mega Drive diz de que console é: "SEGA GENESIS", "SEGA MEGA
## DRIVE ". Os quatro primeiros bytes bastam.
const MARCA_MD := 0x100

## Pastas que a varredura não abre. `Android` guarda os dados de todo app
## instalado: a nossa própria pasta lá dentro entra como raiz separada (ver
## `NavegadorRoms.pasta_externa`), e a dos outros apps é ilegível de todo modo.
const PULAR := ["Android", "LOST.DIR", "System Volume Information"]

## Regiões que o padrão No-Intro escreve entre parênteses. Serve para separar o
## grupo de região do grupo de idioma: `(USA)` é região, `(En,Fr,De)` não é, e
## sem esta lista o segundo viraria "região En".
const REGIOES := [
	"USA", "Japan", "Europe", "World", "Brazil", "Korea", "China", "Taiwan",
	"Australia", "Canada", "France", "Germany", "Spain", "Italy", "Netherlands",
	"Sweden", "Asia", "Russia", "UK", "Unknown",
]

static var _re_prefixo: RegEx
static var _re_artigo: RegEx


# ---------------------------------------------------------------------------
# Título, região e afins — o que transforma nome de arquivo em nome de jogo
# ---------------------------------------------------------------------------

## Título legível a partir do nome do arquivo.
##
## As regras saíram de arquivos reais, uma por linha:
##   Chrono Trigger (USA).sfc                     -> Chrono Trigger
##   5478 - Ghost Trick - Phantom D. (USA).nds    -> Ghost Trick - Phantom D.
##   Legend of Zelda, The - Ocarina of Time.z64   -> The Legend of Zelda - Ocarina of Time
##   Super Mario World (Japan) (En) [b].sfc       -> Super Mario World
static func titulo_de(arquivo: String) -> String:
	var base := arquivo.get_file().get_basename()

	if _re_prefixo == null:
		# Numeração de coleção ("5478 - "). Ancorada no começo e exigindo o
		# hífen, senão "1080 Snowboarding" perderia o nome.
		_re_prefixo = RegEx.create_from_string("^\\s*\\d+\\s*-\\s*")
	var nome := _re_prefixo.sub(base, "")

	nome = _sem_grupos(nome)

	if _re_artigo == null:
		# "Legend of Zelda, The - Ocarina of Time" -> "The Legend of Zelda - ..."
		# O artigo pode vir antes de um subtítulo, então o grupo 3 é opcional.
		_re_artigo = RegEx.create_from_string("^(.+?), (The|A|An|Le|La|Los|Las|El)( - .*)?$")
	var m := _re_artigo.search(nome)
	if m != null:
		nome = "%s %s%s" % [m.get_string(2), m.get_string(1), m.get_string(3)]

	nome = nome.strip_edges()
	# Nome que era só tag — "(USA).sfc" — não pode virar linha vazia na lista.
	return nome if not nome.is_empty() else base


## Região declarada no nome, ou "" se o arquivo não diz.
##
## Precisa existir porque, depois de limpar o título, `Sonic (USA).md` e
## `Sonic (Japan).md` viram a mesma linha, e a região é o que as separa.
static func regiao_de(arquivo: String) -> String:
	for grupo: String in _grupos(arquivo.get_file().get_basename()):
		# Só o primeiro item importa: em "(USA, Europe)" o resto não cabe no
		# rótulo da linha, e o primeiro já responde "de onde é este dump".
		var primeiro: String = grupo.split(",")[0].strip_edges()
		if primeiro in REGIOES:
			return primeiro
	return ""


## Se o nome carrega a marca de dump ruim do No-Intro (`[b]`).
##
## Vale mostrar: uma ROM assim trava ou corrompe de formas que parecem bug do
## emulador, e sem o aviso o tempo vai todo para o lugar errado.
static func suspeito_de(arquivo: String) -> bool:
	return "[b]" in arquivo.get_file()


## Registro de um jogo. `tamanho` vem de fora quando quem chama já mediu — a
## varredura mede uma vez e guarda, em vez de reabrir o arquivo a cada listagem.
static func item_de(caminho: String, tamanho := -1) -> Dictionary:
	var arquivo := caminho.get_file()
	return {
		"caminho": caminho,
		"arquivo": arquivo,
		"titulo": titulo_de(arquivo),
		"sistema": NavegadorRoms.sistema_de(caminho),
		"regiao": regiao_de(arquivo),
		"suspeito": suspeito_de(arquivo),
		"tamanho": tamanho if tamanho >= 0 else _tamanho(caminho),
	}


## Texto da direita da linha: console, região e tamanho, sem separador sobrando
## quando a região não é conhecida.
static func detalhe_de(item: Dictionary) -> String:
	var partes: Array[String] = []
	var sistema: String = item.get("sistema", "")
	if not sistema.is_empty():
		partes.append(NavegadorRoms.nome_sistema(sistema))
	var regiao: String = item.get("regiao", "")
	if not regiao.is_empty():
		partes.append(regiao)
	partes.append(NavegadorRoms.formatar_tamanho(int(item.get("tamanho", 0))))
	return " · ".join(partes)


# ---------------------------------------------------------------------------
# Ordem e agrupamento
# ---------------------------------------------------------------------------

## Por título, sem diferenciar maiúsculas; empate desfeito pelo nome do arquivo,
## que é o que separa dois dumps regionais do mesmo jogo. Sem o desempate a
## ordem entre eles mudaria a cada varredura, e a lista pareceria embaralhar
## sozinha entre sessões.
static func ordenar(itens: Array) -> Array:
	var copia := itens.duplicate()
	copia.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var c: int = (a.get("titulo", "") as String).nocasecmp_to(b.get("titulo", ""))
		if c != 0:
			return c < 0
		return (a.get("arquivo", "") as String).nocasecmp_to(b.get("arquivo", "")) < 0
	)
	return copia


## sistema -> itens ordenados, na ordem de console de `NavegadorRoms`.
static func agrupar(itens: Array) -> Dictionary:
	var por_sistema: Dictionary = {}
	for sistema: String in NavegadorRoms.NOMES_SISTEMA:
		var desse := itens.filter(func(i: Dictionary) -> bool: return i.get("sistema", "") == sistema)
		if not desse.is_empty():
			por_sistema[sistema] = ordenar(desse)
	return por_sistema


# ---------------------------------------------------------------------------
# Índice em disco
# ---------------------------------------------------------------------------

static func salvar(itens: Array) -> void:
	var f := FileAccess.open(ARQUIVO, FileAccess.WRITE)
	if f == null:
		push_warning("BibliotecaRoms: não gravei %s (erro %d)" % [ARQUIVO, FileAccess.get_open_error()])
		return
	f.store_string(JSON.stringify({"versao": VERSAO, "itens": itens}, "\t"))


## Índice gravado, ou vazio se não há, se está corrompido ou se é de outra
## versão do formato. Nunca devolve registro pela metade: um item sem `caminho`
## viraria uma linha que não carrega nada ao ser clicada.
static func carregar() -> Array:
	if not FileAccess.file_exists(ARQUIVO):
		return []
	var f := FileAccess.open(ARQUIVO, FileAccess.READ)
	if f == null:
		return []
	var dados: Variant = JSON.parse_string(f.get_as_text())
	if typeof(dados) != TYPE_DICTIONARY or int((dados as Dictionary).get("versao", 0)) != VERSAO:
		return []
	var brutos: Variant = (dados as Dictionary).get("itens", [])
	if typeof(brutos) != TYPE_ARRAY:
		return []

	var itens: Array = []
	for bruto: Variant in brutos:
		if typeof(bruto) != TYPE_DICTIONARY:
			continue
		var d := bruto as Dictionary
		var caminho: String = str(d.get("caminho", ""))
		if caminho.is_empty():
			continue
		# O JSON não distingue int de float, então o tamanho volta convertido —
		# sem isto, `formatar_tamanho` receberia float e o texto sairia errado.
		itens.append({
			"caminho": caminho,
			"arquivo": str(d.get("arquivo", caminho.get_file())),
			"titulo": str(d.get("titulo", "")),
			"sistema": str(d.get("sistema", "")),
			"regiao": str(d.get("regiao", "")),
			"suspeito": bool(d.get("suspeito", false)),
			"tamanho": int(d.get("tamanho", 0)),
		})
	return itens


## Tira do índice o que não está mais no disco. É a passada barata, feita toda
## vez que o painel abre — só `file_exists` por item, sem reabrir pasta nenhuma.
static func revalidar(itens: Array) -> Array:
	return itens.filter(func(i: Dictionary) -> bool:
		return FileAccess.file_exists(i.get("caminho", ""))
	)


# ---------------------------------------------------------------------------
# Varredura — instância, porque ela para no meio e continua no frame seguinte
# ---------------------------------------------------------------------------

var _pilha: Array = []          ## pastas pendentes: {caminho, nivel}
var _dir: DirAccess = null      ## pasta em andamento (null = pegar da pilha)
var _dir_caminho := ""
var _dir_nivel := 0
var _itens: Array = []
var _vistos: Dictionary = {}    ## caminho -> true, contra raízes que se contêm
var _pastas := 0
var _recusados := 0             ## extensão de ROM, conteúdo que não era
var _lotou := false


## Prepara a varredura. Não abre nada ainda — quem anda é `passo()`.
func iniciar(raizes: Array) -> void:
	_pilha.clear()
	_fechar_dir()
	_itens.clear()
	_vistos.clear()
	_pastas = 0
	_recusados = 0
	_lotou = false
	for r: Variant in raizes:
		var caminho: String = r.caminho if typeof(r) == TYPE_DICTIONARY else str(r)
		if not caminho.is_empty():
			_pilha.push_back({"caminho": caminho, "nivel": 0})


## Anda até gastar `orcamento_ms` e devolve `true` quando acabou.
##
## O orçamento é em **milissegundos**, e não em "N pastas por frame", porque uma
## pasta com 3000 arquivos custa mais que trinta pastas vazias — medir trabalho
## em pastas deixaria justamente o caso ruim sem limite. E o limite existe porque
## em VR travar o frame não é lentidão, é enjoo.
func passo(orcamento_ms: int = 6) -> bool:
	var fim := Time.get_ticks_msec() + orcamento_ms
	var acabou := false
	# Um lote sempre sai, mesmo com orçamento zero: senão um orçamento apertado
	# demais não andaria nunca e a varredura ficaria presa sem sintoma.
	while true:
		for _i in LOTE:
			if not _uma_entrada():
				acabou = true
				break
		if acabou or Time.get_ticks_msec() >= fim:
			break
	return acabou


func pronta() -> bool:
	return _dir == null and _pilha.is_empty()


func itens() -> Array:
	return _itens


func pastas_visitadas() -> int:
	return _pastas


## Quantos arquivos tinham extensão de ROM e não eram ROM. Vale no log: se um
## jogo não apareceu na lista, este número é o que diz se ele foi **recusado**
## (e aí o modo Pastas o alcança) ou se a varredura nem chegou nele.
func recusados() -> int:
	return _recusados


## Se a varredura parou no teto em vez de acabar. A página avisa: lista truncada
## em silêncio é indistinguível de ROM que não foi achada.
func lotou() -> bool:
	return _lotou


## Varredura inteira de uma vez. Existe para os testes e para o desktop; no
## headset quem manda é `passo()`.
func varrer_tudo(raizes: Array) -> Array:
	iniciar(raizes)
	while not passo(1 << 30):
		pass
	return _itens


## Processa uma entrada de pasta. Devolve `false` quando não há mais o que fazer.
func _uma_entrada() -> bool:
	if _lotou:
		return false

	if _dir == null:
		if _pilha.is_empty():
			return false
		var proxima: Dictionary = _pilha.pop_front()
		_dir_caminho = proxima.caminho
		_dir_nivel = proxima.nivel
		_dir = DirAccess.open(_dir_caminho)
		if _dir == null:
			# Pasta sem permissão é o caso comum em /sdcard/Android; não é erro.
			return true
		# Pedimos as ocultas para poder recusá-las nós mesmos, logo abaixo. Sem
		# isto a regra dependeria do padrão do DirAccess, que é justamente o
		# tipo de coisa que muda de versão sem ninguém notar.
		_dir.include_hidden = true
		_dir.list_dir_begin()
		_pastas += 1
		return true

	var nome := _dir.get_next()
	if nome.is_empty():
		_fechar_dir()
		return true
	if nome.begins_with("."):
		return true

	var completo := _dir_caminho.path_join(nome)
	if _dir.current_is_dir():
		if nome not in PULAR and _dir_nivel + 1 <= PROFUNDIDADE_MAX:
			_pilha.push_back({"caminho": completo, "nivel": _dir_nivel + 1})
		return true

	var ext := nome.get_extension().to_lower()
	if not NavegadorRoms.SISTEMAS.has(ext):
		return true
	# As raízes se contêm (/sdcard e /sdcard/Download são as duas oferecidas),
	# então o mesmo arquivo chega por dois caminhos e apareceria duas vezes.
	if _vistos.has(completo):
		return true
	# Visto antes de examinado: o mesmo arquivo chegando pela segunda raiz não
	# paga o exame de novo.
	_vistos[completo] = true
	if not _e_rom_mesmo(completo, ext):
		_recusados += 1
		return true
	_itens.append(BibliotecaRoms.item_de(completo, _tamanho(completo)))
	if _itens.size() >= TETO_ITENS:
		_lotou = true
		_fechar_dir()
		_pilha.clear()
	return true


func _fechar_dir() -> void:
	if _dir != null:
		_dir.list_dir_end()
		_dir = null


# ---------------------------------------------------------------------------

## Os grupos entre parênteses ou colchetes do nome, na ordem em que aparecem.
static func _grupos(nome: String) -> Array:
	var achados: Array = []
	var i := 0
	while i < nome.length():
		var abre := nome[i]
		if abre == "(" or abre == "[":
			var fecha := ")" if abre == "(" else "]"
			var j := nome.find(fecha, i + 1)
			if j < 0:
				break
			achados.append(nome.substr(i + 1, j - i - 1))
			i = j + 1
		else:
			i += 1
	return achados


## Tira os grupos do fim do nome, um a um. Só do fim: cortar em qualquer lugar
## estragaria um título que tenha parênteses de verdade no meio.
static func _sem_grupos(nome: String) -> String:
	var atual := nome.strip_edges()
	while atual.length() > 1:
		var ultimo := atual[atual.length() - 1]
		if ultimo != ")" and ultimo != "]":
			break
		var abre := "(" if ultimo == ")" else "["
		var i := atual.rfind(abre)
		if i < 0:
			break
		atual = atual.substr(0, i).strip_edges()
	return atual


static func _tamanho(caminho: String) -> int:
	var f := FileAccess.open(caminho, FileAccess.READ)
	return f.get_length() if f != null else 0


## Se um arquivo de extensão ambígua é mesmo uma ROM. Extensão que só pertence a
## console (`.sfc`, `.z64`, `.nds`…) passa direto: examinar todo arquivo custaria
## uma abertura a mais por item e não separaria nada.
static func _e_rom_mesmo(caminho: String, ext: String) -> bool:
	if not ext in AMBIGUAS:
		return true
	if ext == "md":
		return _tem_marca_sega(caminho)
	return _zip_traz_rom(caminho)


static func _tem_marca_sega(caminho: String) -> bool:
	var f := FileAccess.open(caminho, FileAccess.READ)
	if f == null or f.get_length() < MARCA_MD + 4:
		return false
	f.seek(MARCA_MD)
	return f.get_buffer(4).get_string_from_ascii() == "SEGA"


## Um `.zip` vale se traz ROM de **SNES** dentro. Só de SNES porque é só nela que
## o zip serve: o mupen exige caminho de arquivo real e não abre ROM de N64
## compactada, então aceitar um zip de `.z64` daria linha na lista e erro ao
## carregar — pior que não listar.
static func _zip_traz_rom(caminho: String) -> bool:
	var z := ZIPReader.new()
	if z.open(caminho) != OK:
		return false
	var achou := false
	for interno: String in z.get_files():
		var dentro := interno.get_extension().to_lower()
		# `zip` também mapeia para "snes", então sem excluí-lo um zip de zips se
		# aprovaria sozinho.
		if dentro != "zip" and NavegadorRoms.SISTEMAS.get(dentro, "") == "snes":
			achou = true
			break
	z.close()
	return achou
