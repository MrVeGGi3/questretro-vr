class_name PagRoms
extends PagBase
## Navegador de ROMs no armazenamento do headset.

signal rom_escolhida(caminho: String)
signal cancelado

var _cfg: ConfigEmu
var _pasta := ""              ## vazio = mostrando a lista de raízes
var _selecionado := ""
var _lista: VBoxContainer
var _aviso: Control
var _contagem: Label
var _bt_carregar: Button
var _bt_permitir: Button


func _init(cfg: ConfigEmu) -> void:
	super("ROMs")
	_cfg = cfg

	_aviso = _banner_permissao()
	conteudo.add_child(_aviso)

	_lista = VBoxContainer.new()
	_lista.add_theme_constant_override("separation", 3)
	conteudo.add_child(_lista)

	var bt_raizes := WidgetsVR.botao("◂ Raízes")
	bt_raizes.custom_minimum_size.x = 0
	bt_raizes.pressed.connect(_mostrar_raizes)
	rodape.add_child(bt_raizes)

	_contagem = WidgetsVR.mono("")
	_contagem.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	rodape.add_child(_contagem)

	rodape.add_child(espacador())

	_bt_permitir = WidgetsVR.botao("Permitir acesso")
	_bt_permitir.pressed.connect(func() -> void:
		NavegadorRoms.pedir_permissao()
		# Sai do app para os Ajustes do Android; ao voltar, reabrir o menu relê
		# o estado da permissão.
		_bt_permitir.text = "Ligue em Ajustes"
	)
	rodape.add_child(_bt_permitir)

	var bt_cancelar := WidgetsVR.botao("Cancelar")
	bt_cancelar.pressed.connect(func() -> void: cancelado.emit())
	rodape.add_child(bt_cancelar)

	_bt_carregar = WidgetsVR.botao("Carregar", true)
	_bt_carregar.pressed.connect(func() -> void:
		if not _selecionado.is_empty():
			_cfg.definir("roms/ultima_pasta", _pasta)
			rom_escolhida.emit(_selecionado)
	)
	rodape.add_child(_bt_carregar)

	NavegadorRoms.garantir_pasta_local()
	atualizar()


## Chamada toda vez que o menu abre: a permissão pode ter sido concedida no
## diálogo do Android desde a última vez.
func atualizar() -> void:
	var ultima: String = _cfg.obter("roms/ultima_pasta")
	if not ultima.is_empty() and DirAccess.dir_exists_absolute(ultima):
		_abrir(ultima)
	else:
		_mostrar_raizes()


func _abrir(caminho: String) -> void:
	_pasta = caminho
	_selecionado = ""
	caminho_lab.text = caminho
	_repovoar(NavegadorRoms.listar(caminho), true)


func _mostrar_raizes() -> void:
	_pasta = ""
	_selecionado = ""
	caminho_lab.text = "escolha um local"
	var itens: Array = []
	for r in NavegadorRoms.raizes():
		itens.append({"nome": r.nome, "caminho": r.caminho, "pasta": true, "tamanho": 0})
	_repovoar(itens, false)


func _repovoar(itens: Array, com_subir: bool) -> void:
	for filho in _lista.get_children():
		filho.queue_free()

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
	var bt := Button.new()
	bt.custom_minimum_size.y = TemaVR.ALT_LINHA
	bt.alignment = HORIZONTAL_ALIGNMENT_LEFT
	bt.focus_mode = Control.FOCUS_NONE
	bt.add_theme_stylebox_override("normal", TemaVR.vazio())
	bt.add_theme_stylebox_override("hover", TemaVR.caixa(TemaVR.SURFACE, 10))

	var glifo: String = "▸" if item.pasta else "◈"
	if item.nome == "..":
		glifo = "↰"
	bt.text = "  %s   %s" % [glifo, item.nome]
	if item.pasta:
		bt.add_theme_color_override("font_color", TemaVR.DIM)

	if not item.pasta:
		# O tamanho fica encostado à direita, alinhado entre linhas.
		var meta := WidgetsVR.mono(NavegadorRoms.formatar_tamanho(item.tamanho))
		meta.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
		meta.offset_left = -220
		meta.offset_right = -18
		meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		meta.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bt.add_child(meta)

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


func _selecionar(caminho: String) -> void:
	_selecionado = caminho
	_bt_carregar.disabled = false
	# Realce da linha escolhida, comparando pelo caminho guardado — dois
	# arquivos de mesmo nome em pastas diferentes não se confundem.
	for filho in _lista.get_children():
		var bt := filho as Button
		if bt == null:
			continue
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
