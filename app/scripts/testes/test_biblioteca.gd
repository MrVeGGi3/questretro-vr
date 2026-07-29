extends Node
## Prova a biblioteca sem headset nenhum. É lógica de arquivo e de texto, então
## roda em `--headless`, como o test_guidao:
##
##   godot --headless --xr-mode off --path app res://cenas/test_biblioteca.tscn
##
## Roda como cena e não com `-s` pelo mesmo motivo do test_ui: script de
## MainLoop trava na inicialização com a GDExtension carregada.
##
## O que só se pega aqui: título que sai vazio, dois dumps regionais que
## desabam num só, ROM que a varredura não acha, e — o pior deles — varredura
## que perde estado ao ceder o frame. No headset esse último apareceria como
## jogo faltando na lista, sem erro nenhum no log.

const RAIZ := "user://teste_biblioteca"

## Arquivos de enchimento, para a varredura precisar de mais de um lote e a
## comparação incremental-vs-bloqueante ter o que provar.
const ENCHIMENTO := 300

var _falhas := 0
var _indice_salvo: PackedByteArray = []
var _tinha_indice := false


func _ready() -> void:
	_guardar_indice()
	_montar_arvore()

	_titulo_limpa_o_nome()
	_titulo_nunca_fica_vazio()
	_regiao_sai_do_nome()
	_dump_ruim_e_sinalizado()
	_varredura_acha_o_que_deve()
	_extensao_ambigua_nao_basta()
	_varredura_respeita_a_profundidade()
	_regionais_nao_desabam_num_so()
	_raizes_que_se_contem_nao_duplicam()
	_indice_sobrevive_ao_disco()
	_revalidar_derruba_o_que_sumiu()
	_incremental_da_o_mesmo_que_bloqueante()
	_todo_sistema_tem_core_e_nome()

	_limpar_arvore()
	_devolver_indice()
	print("=== %s ===" % ("TUDO OK" if _falhas == 0 else "%d FALHA(S)" % _falhas))
	get_tree().quit(1 if _falhas > 0 else 0)


# ---------------------------------------------------------------------------
# Título, região, sinalização
# ---------------------------------------------------------------------------

## Cada linha desta tabela é um arquivo real da coleção. Elas não são exemplos:
## são as regras, e mexer na limpeza sem mexer aqui é o jeito de quebrar a lista
## inteira em silêncio.
func _titulo_limpa_o_nome() -> void:
	var tabela := {
		"Chrono Trigger (USA).sfc": "Chrono Trigger",
		"5478 - Ghost Trick - Phantom Detective (USA) (En,Fr,De,Es,It).nds":
				"Ghost Trick - Phantom Detective",
		"Legend of Zelda, The - Ocarina of Time (USA).z64":
				"The Legend of Zelda - Ocarina of Time",
		"Super Mario World (Japan) (En) (Arcade) [b].sfc": "Super Mario World",
		"DonkeyKongClassic (Shiru).smc": "DonkeyKongClassic",
		"Sonic CD (USA).chd": "Sonic CD",
		# Sem tag nenhuma: o nome já é o título.
		"Trauma Center.nds": "Trauma Center",
		# Artigo no fim, sem subtítulo.
		"Adventures of Batman & Robin, The (USA).md": "The Adventures of Batman & Robin",
		# Número sem hífen é parte do nome, e não numeração de coleção.
		"1080 Snowboarding (USA).z64": "1080 Snowboarding",
	}
	for arquivo: String in tabela:
		var deu := BibliotecaRoms.titulo_de(arquivo)
		_igual(deu, tabela[arquivo], "título de %s" % arquivo)


## Um nome que é só tag viraria linha em branco na lista — clicável, sem dizer
## em que jogo se está clicando.
func _titulo_nunca_fica_vazio() -> void:
	for arquivo: String in ["(USA).sfc", "[b].md", "(Japan) (En).nds"]:
		_verdade(not BibliotecaRoms.titulo_de(arquivo).strip_edges().is_empty(),
				"título de %s não fica vazio" % arquivo)


func _regiao_sai_do_nome() -> void:
	_igual(BibliotecaRoms.regiao_de("Chrono Trigger (USA).sfc"), "USA", "região USA")
	_igual(BibliotecaRoms.regiao_de("Super Mario World (Japan) (En).sfc"), "Japan", "região Japan")
	_igual(BibliotecaRoms.regiao_de("Sonic (USA, Europe).md"), "USA", "região multipla vira a primeira")
	# O grupo de idioma não é região; sem a lista de regiões viraria "região En".
	_igual(BibliotecaRoms.regiao_de("Jogo (En,Fr,De).nds"), "", "grupo de idioma não vira região")
	_igual(BibliotecaRoms.regiao_de("DonkeyKongClassic (Shiru).smc"), "", "autor não vira região")


func _dump_ruim_e_sinalizado() -> void:
	_verdade(BibliotecaRoms.suspeito_de("Super Mario World (Japan) [b].sfc"),
			"[b] é sinalizado como dump ruim")
	_verdade(not BibliotecaRoms.suspeito_de("Chrono Trigger (USA).sfc"),
			"dump bom não é sinalizado")


# ---------------------------------------------------------------------------
# Varredura
# ---------------------------------------------------------------------------

func _varredura_acha_o_que_deve() -> void:
	var itens := BibliotecaRoms.new().varrer_tudo([RAIZ])
	var nomes := _nomes(itens)

	_verdade("Chrono Trigger (USA).sfc" in nomes, "acha ROM em subpasta")
	_verdade("Perdido (Europe).sfc" in nomes, "acha ROM em pasta funda")
	# A premissa da asserção seguinte: a pasta oculta *é* listada pelo DirAccess
	# (a varredura pede `include_hidden`), e quem a recusa somos nós. Sem isto,
	# "pula pasta oculta" passaria à toa no dia em que o padrão do motor
	# escondesse a pasta sozinho — e ninguém saberia que a regra sumiu.
	var dir := DirAccess.open(RAIZ)
	dir.include_hidden = true
	dir.list_dir_begin()
	var viu_oculta := false
	var nome := dir.get_next()
	while not nome.is_empty():
		viu_oculta = viu_oculta or nome == ".oculta"
		nome = dir.get_next()
	dir.list_dir_end()
	_verdade(viu_oculta, "a pasta oculta aparece na listagem (premissa)")
	_verdade(not ("Escondido (USA).sfc" in nomes), "e a varredura é que a recusa")
	_verdade(not ("leiame.txt" in nomes), "ignora extensão que não é ROM")
	_verdade(not ("notas.sav" in nomes), "ignora arquivo de save solto")

	# O tamanho é medido na varredura e guardado; a listagem não reabre o
	# arquivo. Zero aqui significaria que a lista mostraria "0 B" para tudo.
	for item: Dictionary in itens:
		if item.arquivo == "Chrono Trigger (USA).sfc":
			_verdade(int(item.tamanho) > 0, "tamanho é medido na varredura")
			_igual(str(item.sistema), "snes", "sistema sai da extensão")


## O erro que só a varredura tem: o navegador de pastas mostrava um `.md` só se
## a pessoa abrisse a pasta dele, e ninguém abre a pasta de documentação
## procurando jogo. Varrendo o aparelho inteiro, extensão deixou de bastar —
## varrer o /home desta máquina achou 1161 "jogos de Mega Drive", todos README.
func _extensao_ambigua_nao_basta() -> void:
	var v := BibliotecaRoms.new()
	var nomes := _nomes(v.varrer_tudo([RAIZ]))

	_verdade(not ("arquitetura.md" in nomes), "Markdown não entra como Mega Drive")
	_verdade("Sonic (USA).md" in nomes, "e o cartucho .md de verdade continua entrando")
	_verdade(not ("fotos.zip" in nomes), "zip sem ROM dentro não entra")
	_verdade("Coletanea (USA).zip" in nomes, "e zip com ROM de SNES dentro entra")
	# Sem o contador, "meu jogo sumiu" não se distingue de "a varredura nem
	# chegou lá" — e as duas respostas mandam para lados opostos.
	_igual(str(v.recusados()), "2", "os recusados são contados")


func _varredura_respeita_a_profundidade() -> void:
	var nomes := _nomes(BibliotecaRoms.new().varrer_tudo([RAIZ]))
	_verdade(not ("Fundo demais (USA).sfc" in nomes),
			"não desce além de PROFUNDIDADE_MAX")


func _regionais_nao_desabam_num_so() -> void:
	var itens := BibliotecaRoms.new().varrer_tudo([RAIZ])
	var sonics := itens.filter(func(i: Dictionary) -> bool: return i.titulo == "Sonic")
	_igual(str(sonics.size()), "2", "dois dumps regionais continuam duas linhas")
	var regioes: Array = []
	for s: Dictionary in sonics:
		regioes.append(s.regiao)
	regioes.sort()
	_igual(str(regioes), '["Japan", "USA"]', "e a região é o que as separa")


## As raízes oferecidas se contêm: no Android, /sdcard e /sdcard/Download são as
## duas. Sem deduplicação o mesmo jogo apareceria duas vezes na lista.
func _raizes_que_se_contem_nao_duplicam() -> void:
	var itens := BibliotecaRoms.new().varrer_tudo([RAIZ, RAIZ.path_join("SNES")])
	var quantos := 0
	for item: Dictionary in itens:
		if item.arquivo == "Chrono Trigger (USA).sfc":
			quantos += 1
	_igual(str(quantos), "1", "raízes que se contêm não duplicam o jogo")


func _incremental_da_o_mesmo_que_bloqueante() -> void:
	var bloqueante := _caminhos(BibliotecaRoms.new().varrer_tudo([RAIZ]))

	var v := BibliotecaRoms.new()
	v.iniciar([RAIZ])
	var chamadas := 0
	# Orçamento zero: cada chamada faz um lote e cede, que é o pior caso de
	# retomada — o estado tem de sobreviver a parar no meio de uma pasta.
	while not v.passo(0):
		chamadas += 1
		if chamadas > 10000:
			break
	var incremental := _caminhos(v.itens())

	_verdade(chamadas > 1, "a varredura de fato cedeu o frame (%d chamadas)" % chamadas)
	_igual(str(incremental.size()), str(bloqueante.size()),
			"incremental acha a mesma quantidade que bloqueante")
	bloqueante.sort()
	incremental.sort()
	_verdade(incremental == bloqueante, "e exatamente os mesmos arquivos")


func _todo_sistema_tem_core_e_nome() -> void:
	var sistemas: Dictionary = {}
	for item: Dictionary in BibliotecaRoms.new().varrer_tudo([RAIZ]):
		sistemas[item.sistema] = true
	_verdade(sistemas.size() >= 4, "a árvore de teste cobre os consoles (%d)" % sistemas.size())
	for sistema: String in sistemas:
		_verdade(EmuCore.CORES.has(sistema), "%s tem core" % sistema)
		_verdade(NavegadorRoms.NOMES_SISTEMA.has(sistema), "%s tem nome de tela" % sistema)


# ---------------------------------------------------------------------------
# Índice em disco
# ---------------------------------------------------------------------------

func _indice_sobrevive_ao_disco() -> void:
	var antes := BibliotecaRoms.new().varrer_tudo([RAIZ])
	BibliotecaRoms.salvar(antes)
	var depois := BibliotecaRoms.carregar()

	_igual(str(depois.size()), str(antes.size()), "o índice volta com todos os itens")
	var por_caminho: Dictionary = {}
	for item: Dictionary in depois:
		por_caminho[item.caminho] = item
	for item: Dictionary in antes:
		var voltou: Dictionary = por_caminho.get(item.caminho, {})
		if voltou.is_empty():
			_verdade(false, "item %s voltou do índice" % item.arquivo)
			continue
		for campo: String in ["arquivo", "titulo", "sistema", "regiao", "suspeito", "tamanho"]:
			if voltou[campo] != item[campo]:
				_verdade(false, "campo %s de %s: %s != %s" %
						[campo, item.arquivo, voltou[campo], item[campo]])
				return
	_verdade(true, "todo campo volta igual, inclusive o tamanho como inteiro")

	# JSON não distingue int de float. Se o tamanho voltasse float,
	# formatar_tamanho daria "4.0 MB" onde deve dar "4.0 MB" por outra conta —
	# e a divisão inteira de KB sairia errada.
	for item: Dictionary in depois:
		if typeof(item.tamanho) != TYPE_INT:
			_verdade(false, "tamanho voltou como %d, não int" % typeof(item.tamanho))
			return
	_verdade(true, "tamanho volta como int, não float")


func _revalidar_derruba_o_que_sumiu() -> void:
	var itens := BibliotecaRoms.new().varrer_tudo([RAIZ])
	var alvo := RAIZ.path_join("SNES/Chrono Trigger (USA).sfc")
	_verdade(alvo in _caminhos(itens), "o alvo está no índice antes")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(alvo))
	var sobrou := BibliotecaRoms.revalidar(itens)

	_verdade(not (alvo in _caminhos(sobrou)), "revalidar derruba o que sumiu do disco")
	_igual(str(sobrou.size()), str(itens.size() - 1), "e não derruba mais nada junto")
	_escrever(alvo, 4096)


# ---------------------------------------------------------------------------
# A árvore de teste
# ---------------------------------------------------------------------------

func _montar_arvore() -> void:
	_limpar_arvore()
	for arquivo: String in [
		"SNES/Chrono Trigger (USA).sfc",
		"SNES/Super Mario World (Japan) (En) (Arcade) [b].sfc",
		"N64/Legend of Zelda, The - Ocarina of Time (USA).z64",
		"NDS/5478 - Ghost Trick - Phantom Detective (USA) (En,Fr,De,Es,It).nds",
		"Mega Drive/Sonic (USA).md",
		"Mega Drive/Sonic (Japan).md",
		"fundo/a/b/c/Perdido (Europe).sfc",
		"fundo/a/b/c/d/e/f/Fundo demais (USA).sfc",
		".oculta/Escondido (USA).sfc",
		"leiame.txt",
		"SNES/notas.sav",
	]:
		_escrever(RAIZ.path_join(arquivo), 4096)
	for i in ENCHIMENTO:
		_escrever(RAIZ.path_join("SNES/Enchimento %03d (USA).sfc" % i), 64)

	# Os dois lados da extensão ambígua, lado a lado na mesma árvore.
	_escrever_texto(RAIZ.path_join("docs/arquitetura.md"),
			"# Arquitetura\n\nIsto é documentação, não um cartucho.\n")
	_zipar(RAIZ.path_join("SNES/Coletanea (USA).zip"), "Coletanea (USA).sfc")
	_zipar(RAIZ.path_join("docs/fotos.zip"), "foto.jpg")


func _escrever(caminho: String, bytes: int) -> void:
	DirAccess.make_dir_recursive_absolute(caminho.get_base_dir())
	var f := FileAccess.open(caminho, FileAccess.WRITE)
	if f == null:
		printerr("  FALHA não criei %s" % caminho)
		_falhas += 1
		return
	var lixo := PackedByteArray()
	lixo.resize(bytes)
	# Cartucho de Mega Drive diz o console em 0x100, e a varredura confere. Sem a
	# marca aqui os `.md` da árvore seriam recusados como Markdown — e essa é
	# justamente a regra que eles existem para exercitar do lado certo.
	if caminho.get_extension().to_lower() == "md":
		var marca := "SEGA GENESIS    ".to_ascii_buffer()
		for i in marca.size():
			lixo[BibliotecaRoms.MARCA_MD + i] = marca[i]
	f.store_buffer(lixo)


func _escrever_texto(caminho: String, texto: String) -> void:
	DirAccess.make_dir_recursive_absolute(caminho.get_base_dir())
	var f := FileAccess.open(caminho, FileAccess.WRITE)
	if f == null:
		printerr("  FALHA não criei %s" % caminho)
		_falhas += 1
		return
	f.store_string(texto)


## Um zip de verdade, com um arquivo só dentro — o que decide se ele é jogo.
func _zipar(caminho: String, dentro: String) -> void:
	DirAccess.make_dir_recursive_absolute(caminho.get_base_dir())
	var z := ZIPPacker.new()
	if z.open(caminho) != OK:
		printerr("  FALHA não criei %s" % caminho)
		_falhas += 1
		return
	z.start_file(dentro)
	var conteudo := PackedByteArray()
	conteudo.resize(2048)
	z.write_file(conteudo)
	z.close_file()
	z.close()


func _limpar_arvore() -> void:
	_apagar_recursivo(RAIZ)


func _apagar_recursivo(caminho: String) -> void:
	var dir := DirAccess.open(caminho)
	if dir == null:
		return
	dir.include_hidden = true
	dir.list_dir_begin()
	var nome := dir.get_next()
	while not nome.is_empty():
		var completo := caminho.path_join(nome)
		if dir.current_is_dir():
			_apagar_recursivo(completo)
		else:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(completo))
		nome = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(caminho))


## O índice de verdade de quem roda o teste não pode ser vítima dele. Mesma
## precaução do test_sram com o `.srm`: testar a biblioteca destruindo a
## biblioteca seria irônico demais.
func _guardar_indice() -> void:
	_tinha_indice = FileAccess.file_exists(BibliotecaRoms.ARQUIVO)
	if _tinha_indice:
		_indice_salvo = FileAccess.get_file_as_bytes(BibliotecaRoms.ARQUIVO)


func _devolver_indice() -> void:
	if _tinha_indice:
		var f := FileAccess.open(BibliotecaRoms.ARQUIVO, FileAccess.WRITE)
		if f != null:
			f.store_buffer(_indice_salvo)
	elif FileAccess.file_exists(BibliotecaRoms.ARQUIVO):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(BibliotecaRoms.ARQUIVO))


# ---------------------------------------------------------------------------
# Asserções
# ---------------------------------------------------------------------------

func _nomes(itens: Array) -> Array:
	var lista: Array = []
	for item: Dictionary in itens:
		lista.append(item.arquivo)
	return lista


func _caminhos(itens: Array) -> Array:
	var lista: Array = []
	for item: Dictionary in itens:
		lista.append(item.caminho)
	return lista


func _igual(deu: String, esperado: String, o_que: String) -> void:
	if deu == esperado:
		print("  ok   %s" % o_que)
	else:
		printerr("  FALHA %s — esperava «%s», deu «%s»" % [o_que, esperado, deu])
		_falhas += 1


func _verdade(ok: bool, o_que: String) -> void:
	if ok:
		print("  ok   %s" % o_que)
	else:
		printerr("  FALHA %s" % o_que)
		_falhas += 1
