class_name PagRoms
extends PagBase
## Escolha da ROM, em dois modos.
##
## **Biblioteca** (padrão) lista jogos: a varredura acha as ROMs onde estiverem,
## o título sai limpo do nome do arquivo e a lista vem agrupada por console, com
## Continuar e Favoritos no topo. É o que escala para quem despejou 200 arquivos
## em /sdcard/Download e escolhe apontando um laser.
##
## **Pastas** é o navegador de arquivos de sempre. Fica como saída: se a
## varredura não achou uma ROM — pasta funda demais, extensão que não
## reconhecemos —, ainda dá para chegar nela pelo caminho.

signal rom_escolhida(caminho: String)
signal cancelado

## Linhas desenhadas por vez. `_repovoar` cria um Button por linha e não recicla
## nada; sem teto, uma coleção grande viraria centenas de nós refeitos a cada
## troca de filtro, num SubViewport que é textura de um quad.
const PAGINA := 60

## Orçamento da varredura por frame. Baixo de propósito: no headset o emulador
## continua rodando atrás do painel, e o frame inteiro são ~13,9 ms a 72 Hz.
const ORCAMENTO_MS := 3

## Quantos recentes cabem em "Continuar". O config guarda 10; mostrar todos
## empurraria os consoles para fora da primeira tela.
const CONTINUAR := 5

var _cfg: ConfigEmu
var _selecionado := ""
var _lista: VBoxContainer
var _aviso: Control
var _contagem: Label
var _bt_carregar: Button
var _bt_permitir: Button
var _bt_modo: Button
var _bt_varrer: Button
var _bt_raizes: Button
var _botoes_linha: Array[Button] = []

# --- modo Pastas ---
var _pasta := ""              ## vazio = mostrando a lista de raízes

# --- modo Biblioteca ---
var _itens: Array = []        ## o índice, já revalidado
var _filtro := ""             ## "" = todos os consoles
var _limite := PAGINA
var _barra_filtro: Control
var _varredura: BibliotecaRoms = null
var _varreu_nesta_sessao := false


func _init(cfg: ConfigEmu) -> void:
	super("ROMs")
	_cfg = cfg

	_aviso = _banner_permissao()
	conteudo.add_child(_aviso)

	_barra_filtro = _montar_filtro()
	conteudo.add_child(_barra_filtro)

	_lista = VBoxContainer.new()
	_lista.add_theme_constant_override("separation", 3)
	conteudo.add_child(_lista)

	_bt_raizes = WidgetsVR.botao("◂ Raízes")
	_bt_raizes.name = "Raizes"
	_bt_raizes.custom_minimum_size.x = 0
	_bt_raizes.pressed.connect(_mostrar_raizes)
	rodape.add_child(_bt_raizes)

	_bt_varrer = WidgetsVR.botao("Reescanear")
	_bt_varrer.name = "Reescanear"
	_bt_varrer.custom_minimum_size.x = 0
	_bt_varrer.pressed.connect(func() -> void:
		if _varredura != null:
			_parar_varredura()
		else:
			_comecar_varredura()
	)
	rodape.add_child(_bt_varrer)

	_contagem = WidgetsVR.mono("")
	_contagem.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	rodape.add_child(_contagem)

	rodape.add_child(espacador())

	_bt_permitir = WidgetsVR.botao("Permitir acesso")
	_bt_permitir.name = "PermitirAcesso"
	_bt_permitir.custom_minimum_size.x = 0
	_bt_permitir.pressed.connect(func() -> void:
		NavegadorRoms.pedir_permissao()
		# Sai do app para os Ajustes do Android; ao voltar, reabrir o menu relê
		# o estado da permissão.
		_bt_permitir.text = "Ligue em Ajustes"
	)
	rodape.add_child(_bt_permitir)

	_bt_modo = WidgetsVR.botao("Pastas")
	_bt_modo.name = "ModoLista"
	_bt_modo.custom_minimum_size.x = 0
	_bt_modo.pressed.connect(_alternar_modo)
	rodape.add_child(_bt_modo)

	var bt_cancelar := WidgetsVR.botao("Cancelar")
	bt_cancelar.custom_minimum_size.x = 0
	bt_cancelar.pressed.connect(func() -> void: cancelado.emit())
	rodape.add_child(bt_cancelar)

	_bt_carregar = WidgetsVR.botao("Carregar", true)
	_bt_carregar.name = "Carregar"
	_bt_carregar.custom_minimum_size.x = 0
	_bt_carregar.pressed.connect(func() -> void:
		if not _selecionado.is_empty():
			if _modo() == ConfigEmu.LISTA_PASTAS:
				_cfg.definir("roms/ultima_pasta", _pasta)
			rom_escolhida.emit(_selecionado)
	)
	rodape.add_child(_bt_carregar)

	NavegadorRoms.garantir_pasta_local()
	set_process(false)
	atualizar()


func _modo() -> int:
	return int(_cfg.obter("roms/modo_lista"))


## Chamada toda vez que o menu abre: a permissão pode ter sido concedida no
## diálogo do Android, e uma ROM pode ter sumido do disco desde a última vez.
func atualizar() -> void:
	if _modo() == ConfigEmu.LISTA_PASTAS:
		_atualizar_pastas()
	else:
		_atualizar_biblioteca()


func _alternar_modo() -> void:
	_parar_varredura()
	_cfg.definir("roms/modo_lista",
			ConfigEmu.LISTA_BIBLIOTECA if _modo() == ConfigEmu.LISTA_PASTAS
			else ConfigEmu.LISTA_PASTAS)
	_selecionado = ""
	atualizar()


# ---------------------------------------------------------------------------
# Biblioteca
# ---------------------------------------------------------------------------

func _atualizar_biblioteca() -> void:
	if _itens.is_empty():
		_itens = BibliotecaRoms.carregar()
	# A passada barata: só file_exists por item. Reescanear é botão, porque
	# abrir a árvore inteira a cada vez que o painel abre custaria caro.
	_itens = BibliotecaRoms.revalidar(_itens)

	# Primeira execução (ou aparelho sem índice): varre sozinho, uma vez por
	# sessão. Sem isto a biblioteca abriria vazia e pareceria quebrada.
	if _itens.is_empty() and not _varreu_nesta_sessao and _varredura == null:
		_comecar_varredura()
		return

	_limite = PAGINA
	_repovoar_biblioteca()


func _comecar_varredura() -> void:
	_varreu_nesta_sessao = true
	_varredura = BibliotecaRoms.new()
	_varredura.iniciar(NavegadorRoms.raizes())
	_bt_varrer.text = "Parar"
	_contagem.text = "varrendo…"
	set_process(true)


func _process(_delta: float) -> void:
	if _varredura == null:
		return
	if _varredura.passo(ORCAMENTO_MS):
		_terminar_varredura()
	else:
		# Só o contador anda durante a varredura. Repovoar a lista a cada frame
		# refaria centenas de botões e comeria justamente o frame que estamos
		# tentando poupar.
		_contagem.text = "varrendo… %d jogos" % _varredura.itens().size()


func _terminar_varredura() -> void:
	var achados := _varredura.itens()
	var lotou := _varredura.lotou()
	var pastas := _varredura.pastas_visitadas()
	var recusados := _varredura.recusados()
	_parar_varredura()

	_itens = achados
	BibliotecaRoms.salvar(_itens)
	# Os recusados entram no log porque são a primeira pergunta quando um jogo
	# não aparece: recusado pelo exame de conteúdo, ou nem visitado?
	print("Biblioteca: %d jogos em %d pastas (%d recusados)%s" %
			[_itens.size(), pastas, recusados, " (teto atingido)" if lotou else ""])
	_limite = PAGINA
	_repovoar_biblioteca()
	if lotou:
		_contagem.text = "%d jogos (teto)" % _itens.size()


func _parar_varredura() -> void:
	_varredura = null
	set_process(false)
	if _bt_varrer != null:
		_bt_varrer.text = "Reescanear"


func _visiveis() -> Array:
	if _filtro.is_empty():
		return _itens
	return _itens.filter(func(i: Dictionary) -> bool: return i.get("sistema", "") == _filtro)


func _repovoar_biblioteca() -> void:
	_limpar_lista()
	_barra_filtro.visible = true
	_bt_raizes.visible = false
	_bt_varrer.visible = true
	_bt_modo.text = "Pastas"
	caminho_lab.text = "biblioteca"

	var sem_permissao := not NavegadorRoms.tem_permissao()
	_aviso.visible = sem_permissao
	_bt_permitir.visible = sem_permissao

	var visiveis := _visiveis()
	var restam := _limite

	# Continuar e Favoritos ficam acima dos consoles e fora do filtro: quem abre
	# o menu para voltar ao que estava jogando não deve ter de achar o jogo na
	# seção do console dele.
	if _filtro.is_empty():
		restam = _secao("Continuar", _itens_de(_cfg.obter("roms/recentes"), CONTINUAR), restam)
		restam = _secao("Favoritos", _itens_de(_cfg.obter("roms/favoritos"), 0), restam)

	var por_sistema := BibliotecaRoms.agrupar(visiveis)
	for sistema: String in por_sistema:
		restam = _secao(NavegadorRoms.nome_sistema(sistema), por_sistema[sistema], restam)

	var total := visiveis.size()
	if total == 0:
		_contagem.text = "nenhum jogo" if NavegadorRoms.tem_permissao() else "sem acesso"
		_lista.add_child(_vazio_biblioteca())
	elif restam <= 0:
		_contagem.text = "%d de %d jogos" % [_limite, total]
		_lista.add_child(_botao_mais(total))
	else:
		_contagem.text = "%d jogos" % total

	_bt_carregar.disabled = _selecionado.is_empty()


## Desenha uma seção e devolve quantas linhas ainda cabem. Seção vazia não
## aparece — um cabeçalho "Favoritos" sem nada embaixo pareceria erro.
func _secao(titulo: String, itens: Array, restam: int) -> int:
	if itens.is_empty() or restam <= 0:
		return restam
	_lista.add_child(_cabecalho_secao(titulo, itens.size()))
	for item: Dictionary in itens:
		if restam <= 0:
			break
		_lista.add_child(_linha_biblioteca(item))
		restam -= 1
	return restam


## Converte uma lista de caminhos (recentes, favoritos) em itens, aproveitando o
## índice quando o jogo está nele. O que sumiu do disco cai fora aqui.
func _itens_de(caminhos: Variant, teto: int) -> Array:
	var achados: Array = []
	for caminho: Variant in (caminhos as Array):
		var c := str(caminho)
		if not FileAccess.file_exists(c):
			continue
		achados.append(_item_por_caminho(c))
		if teto > 0 and achados.size() >= teto:
			break
	return achados


func _item_por_caminho(caminho: String) -> Dictionary:
	for item: Dictionary in _itens:
		if item.get("caminho", "") == caminho:
			return item
	# Fora do índice: carregada pelo navegador de pastas, de um lugar que a
	# varredura não alcança. Ainda assim tem título e console.
	return BibliotecaRoms.item_de(caminho)


func _montar_filtro() -> Control:
	var caixa := HBoxContainer.new()
	caixa.add_theme_constant_override("separation", 5)

	var opcoes: Array = [{"rotulo": "Todos", "sistema": ""}]
	for sistema: String in NavegadorRoms.NOMES_SISTEMA:
		opcoes.append({"rotulo": NavegadorRoms.nome_sistema(sistema), "sistema": sistema})

	var grupo := ButtonGroup.new()
	for opcao: Dictionary in opcoes:
		var bt := Button.new()
		bt.text = opcao.rotulo
		bt.name = "Filtro_%s" % ("todos" if opcao.sistema.is_empty() else opcao.sistema)
		bt.toggle_mode = true
		bt.button_group = grupo
		bt.button_pressed = (opcao.sistema == _filtro)
		bt.custom_minimum_size.y = TemaVR.ALT_LINHA
		bt.focus_mode = Control.FOCUS_NONE
		var sistema: String = opcao.sistema
		bt.pressed.connect(func() -> void:
			_filtro = sistema
			# A janela recomeça a cada filtro: manter o "mostrar mais" de uma
			# lista de 400 ao cair numa de 12 não faria sentido nenhum.
			_limite = PAGINA
			_repovoar_biblioteca()
		)
		caixa.add_child(bt)
	return caixa


func _cabecalho_secao(titulo: String, quantos: int) -> Control:
	var caixa := HBoxContainer.new()
	caixa.custom_minimum_size.y = 56
	var lab := Label.new()
	lab.text = titulo
	lab.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	lab.add_theme_color_override("font_color", TemaVR.ACCENT)
	caixa.add_child(lab)
	var conta := WidgetsVR.mono("  %d" % quantos)
	conta.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	caixa.add_child(conta)
	return caixa


func _linha_biblioteca(item: Dictionary) -> Control:
	var caminho: String = item.get("caminho", "")
	var indice := _botoes_linha.size()
	var bt := _linha_base()
	bt.name = "Jogo_%d" % indice
	bt.text = "  ◈   %s" % item.get("titulo", caminho.get_file())
	if item.get("suspeito", false):
		# `[b]` do No-Intro: dump ruim. Trava e corrompe de formas que parecem
		# bug do emulador, e sem o aviso a investigação vai para o lugar errado.
		bt.text += "   △"
		bt.tooltip_text = "Marcada como dump ruim ([b]) — pode falhar ou corromper."
	bt.set_meta("caminho", caminho)
	bt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bt.pressed.connect(func() -> void: _selecionar(caminho))
	_botoes_linha.append(bt)

	var meta := WidgetsVR.mono(BibliotecaRoms.detalhe_de(item))
	meta.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	meta.offset_left = -340
	meta.offset_right = -18
	meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	meta.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bt.add_child(meta)

	var linha := HBoxContainer.new()
	linha.add_theme_constant_override("separation", 4)
	linha.add_child(bt)
	linha.add_child(_estrela(caminho, indice))
	return linha


## Botão de favorito. Separado do botão da linha, e não um canto clicável dele,
## porque a 2 m de distância o laser não distingue dois alvos dentro do mesmo
## retângulo — favoritar por engano ao escolher o jogo seria o normal.
func _estrela(caminho: String, indice: int) -> Button:
	var bt := Button.new()
	bt.name = "Estrela_%d" % indice
	bt.custom_minimum_size = Vector2(TemaVR.ALT_LINHA, TemaVR.ALT_LINHA)
	bt.focus_mode = Control.FOCUS_NONE
	bt.add_theme_stylebox_override("normal", TemaVR.vazio())
	bt.add_theme_stylebox_override("hover", TemaVR.caixa(TemaVR.SURFACE, 10))
	var pintar := func(ligado: bool) -> void:
		bt.text = "★" if ligado else "☆"
		bt.add_theme_color_override("font_color", TemaVR.BTN_B if ligado else TemaVR.DIM)
	pintar.call(_cfg.eh_favorito(caminho))
	bt.pressed.connect(func() -> void:
		pintar.call(_cfg.alternar_favorito(caminho))
		# A seção Favoritos muda de tamanho, então a lista inteira é refeita.
		_repovoar_biblioteca()
	)
	return bt


func _botao_mais(total: int) -> Control:
	var faltam: int = total - _limite
	var bt := WidgetsVR.botao("Mostrar mais %d" % mini(faltam, PAGINA))
	bt.name = "MostrarMais"
	bt.pressed.connect(func() -> void:
		_limite += PAGINA
		_repovoar_biblioteca()
	)
	return bt


func _vazio_biblioteca() -> Control:
	var lab := Label.new()
	lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lab.add_theme_color_override("font_color", TemaVR.DIM)
	lab.text = "Nenhum jogo encontrado. Copie ROMs para o aparelho e toque em " \
			+ "“Reescanear”, ou use “Pastas” para abrir uma ROM pelo caminho."
	return lab


# ---------------------------------------------------------------------------
# Pastas — o navegador de sempre
# ---------------------------------------------------------------------------

func _atualizar_pastas() -> void:
	var ultima: String = _cfg.obter("roms/ultima_pasta")
	if not ultima.is_empty() and DirAccess.dir_exists_absolute(ultima):
		_abrir(ultima)
	else:
		_mostrar_raizes()


func _abrir(caminho: String) -> void:
	_pasta = caminho
	_selecionado = ""
	caminho_lab.text = caminho
	_repovoar_pastas(NavegadorRoms.listar(caminho), true)


func _mostrar_raizes() -> void:
	_pasta = ""
	_selecionado = ""
	caminho_lab.text = "escolha um local"
	var itens: Array = []
	for r in NavegadorRoms.raizes():
		itens.append({"nome": r.nome, "caminho": r.caminho, "pasta": true, "tamanho": 0})
	_repovoar_pastas(itens, false)


func _repovoar_pastas(itens: Array, com_subir: bool) -> void:
	_limpar_lista()
	_barra_filtro.visible = false
	_bt_raizes.visible = true
	_bt_varrer.visible = false
	_bt_modo.text = "Biblioteca"

	var sem_permissao := not NavegadorRoms.tem_permissao()
	_aviso.visible = sem_permissao
	_bt_permitir.visible = sem_permissao

	if com_subir:
		var acima := NavegadorRoms.acima(_pasta)
		if not acima.is_empty():
			_lista.add_child(_linha({"nome": "..", "caminho": acima, "pasta": true, "tamanho": 0}))

	for item in itens:
		_lista.add_child(_linha(item))

	var roms := itens.filter(func(i: Dictionary) -> bool: return not i.pasta).size()
	if _pasta.is_empty():
		_contagem.text = "%d locais" % itens.size()
	elif itens.is_empty():
		_contagem.text = "pasta vazia" if not sem_permissao else "sem acesso"
	else:
		_contagem.text = "%d ROMs" % roms
	_bt_carregar.disabled = true


func _linha(item: Dictionary) -> Button:
	var bt := _linha_base()

	var glifo: String = "▸" if item.pasta else "◈"
	if item.nome == "..":
		glifo = "↰"
	bt.text = "  %s   %s" % [glifo, item.nome]
	if item.pasta:
		bt.add_theme_color_override("font_color", TemaVR.DIM)

	if not item.pasta:
		# O tamanho fica encostado à direita, alinhado entre linhas, com o
		# sistema na frente — agora que há mais de um core, saber se a ROM é de
		# SNES ou de N64 antes de abrir evita a troca de core à toa.
		var sistema: String = item.get("sistema", "")
		var direita := NavegadorRoms.formatar_tamanho(item.tamanho)
		if not sistema.is_empty():
			direita = "%s · %s" % [NavegadorRoms.nome_sistema(sistema), direita]
		var meta := WidgetsVR.mono(direita)
		meta.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
		meta.offset_left = -220
		meta.offset_right = -18
		meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		meta.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bt.add_child(meta)
		_botoes_linha.append(bt)

	var caminho: String = item.caminho
	var eh_pasta: bool = item.pasta
	bt.set_meta("caminho", caminho)
	bt.pressed.connect(func() -> void:
		if eh_pasta:
			_abrir(caminho)
		else:
			_selecionar(caminho)
	)
	return bt


# ---------------------------------------------------------------------------
# Comum aos dois modos
# ---------------------------------------------------------------------------

func _linha_base() -> Button:
	var bt := Button.new()
	bt.custom_minimum_size.y = TemaVR.ALT_LINHA
	bt.alignment = HORIZONTAL_ALIGNMENT_LEFT
	bt.focus_mode = Control.FOCUS_NONE
	bt.add_theme_stylebox_override("normal", TemaVR.vazio())
	bt.add_theme_stylebox_override("hover", TemaVR.caixa(TemaVR.SURFACE, 10))
	return bt


func _limpar_lista() -> void:
	_botoes_linha.clear()
	for filho in _lista.get_children():
		_lista.remove_child(filho)
		filho.queue_free()


func _selecionar(caminho: String) -> void:
	_selecionado = caminho
	_bt_carregar.disabled = false
	# Realce da linha escolhida, comparando pelo caminho guardado — dois
	# arquivos de mesmo nome em pastas diferentes não se confundem. Na
	# biblioteca o mesmo jogo pode aparecer duas vezes (em Continuar e na seção
	# do console), e as duas linhas acendem juntas, que é o correto: é o mesmo
	# arquivo.
	for bt in _botoes_linha:
		var marcada: bool = bt.get_meta("caminho", "") == caminho
		bt.add_theme_stylebox_override("normal",
				TemaVR.caixa(TemaVR.RAISED, 10, TemaVR.ACCENT) if marcada else TemaVR.vazio())


func _banner_permissao() -> Control:
	var caixa := PanelContainer.new()
	caixa.add_theme_stylebox_override("panel",
			TemaVR.caixa(Color(TemaVR.BTN_B, 0.12), TemaVR.RAIO, Color(TemaVR.BTN_B, 0.45)))
	var linha := HBoxContainer.new()
	linha.add_theme_constant_override("separation", 16)
	var glifo := Label.new()
	glifo.text = "△"
	glifo.add_theme_color_override("font_color", TemaVR.BTN_B)
	linha.add_child(glifo)
	var txt := Label.new()
	txt.text = "Sem acesso ao armazenamento: /sdcard não abre e as ROMs de lá " \
			+ "não aparecem. Toque em “Permitir acesso”, ache QuestRetro na lista " \
			+ "de Ajustes e ligue a chave. Sem isso, só a pasta do app funciona — " \
			+ "e nela dá para pôr ROMs por adb."
	txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	linha.add_child(txt)
	caixa.add_child(linha)
	caixa.visible = false
	return caixa
