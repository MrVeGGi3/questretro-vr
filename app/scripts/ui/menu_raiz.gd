class_name MenuRaiz
extends Control
## Raiz do menu: sidebar à esquerda, página ativa à direita.
##
## Sidebar em vez de abas no topo porque os alvos ficam grandes e afastados —
## a 2 m de distância mirar com o laser numa faixa de abas é uma briga contra
## o tremor da própria mão.

signal fechar_pedido
signal rom_escolhida(caminho: String)

const LOGO := "res://assets/logo.png"

var _cfg: ConfigEmu
var _emu: EmuCore
var _paginas: Dictionary = {}      ## nome -> Control
var _botoes: Dictionary = {}       ## nome -> Button
var _area: Control
var _rom_lab: Label
var _ativa := ""


func _init(cfg: ConfigEmu, emu: EmuCore) -> void:
	_cfg = cfg
	_emu = emu

	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = TemaVR.criar()

	var fundo := PanelContainer.new()
	fundo.set_anchors_preset(Control.PRESET_FULL_RECT)
	fundo.add_theme_stylebox_override("panel",
			TemaVR.caixa(TemaVR.GROUND, TemaVR.RAIO_PAINEL, TemaVR.LINE))
	add_child(fundo)

	var linha := HBoxContainer.new()
	linha.add_theme_constant_override("separation", 0)
	fundo.add_child(linha)

	linha.add_child(_sidebar())
	linha.add_child(_divisoria_vertical())

	_area = Control.new()
	_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	linha.add_child(_area)

	_criar_paginas()
	mostrar("ROMs")


func _criar_paginas() -> void:
	var roms := PagRoms.new(_cfg)
	roms.rom_escolhida.connect(func(caminho: String) -> void: rom_escolhida.emit(caminho))
	roms.cancelado.connect(func() -> void: fechar_pedido.emit())

	_registrar("ROMs", roms)
	_registrar("Tela", PagTela.new(_cfg, _emu))
	_registrar("Sala", PagSala.new(_cfg))
	_registrar("Vídeo", PagVideo.new(_cfg, _emu))
	_registrar("Áudio", PagAudio.new(_cfg, _emu))
	_registrar("Input", PagInput.new(_cfg, _emu))
	_registrar("Saves", PagSaves.new(_emu))


func _registrar(nome: String, pag: Control) -> void:
	pag.visible = false
	_paginas[nome] = pag
	_area.add_child(pag)


func mostrar(nome: String) -> void:
	if not _paginas.has(nome):
		return
	_ativa = nome
	for chave in _paginas:
		_paginas[chave].visible = (chave == nome)
		_realcar(_botoes[chave], chave == nome)


## Chamada quando o painel abre: relê o que pode ter mudado por fora
## (permissão concedida no diálogo do Android, ROM trocada, novos saves).
func ao_abrir() -> void:
	(_paginas["ROMs"] as PagRoms).atualizar()
	(_paginas["Saves"] as PagSaves).atualizar()
	# O mapa de controle muda com o sistema da ROM, e a ROM pode ter trocado
	# desde a última vez que o painel abriu. A página de Tela pela mesma razão:
	# os ajustes da segunda tela só existem nos sistemas que têm duas.
	(_paginas["Input"] as PagInput).atualizar()
	(_paginas["Tela"] as PagTela).atualizar()
	_atualizar_rodape()


func _sidebar() -> Control:
	var painel := PanelContainer.new()
	painel.custom_minimum_size.x = TemaVR.SIDEBAR
	painel.add_theme_stylebox_override("panel", TemaVR.caixa(TemaVR.SURFACE, 0))

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	painel.add_child(col)

	col.add_child(_marca())

	var nav := VBoxContainer.new()
	nav.add_theme_constant_override("separation", 4)
	for nome in ["ROMs", "Tela", "Sala", "Vídeo", "Áudio", "Input", "Saves"]:
		var bt := _item_nav(nome)
		_botoes[nome] = bt
		nav.add_child(bt)
	col.add_child(_margem(nav, 16, 0))

	var espaco := Control.new()
	espaco.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(espaco)

	col.add_child(WidgetsVR.divisoria(TemaVR.LINE))
	col.add_child(_margem(_rodape_sidebar(), TemaVR.PAD_SIDEBAR, 18))
	return painel


## A logo empilha visor e controle, então precisa de ~120 px para o D-pad
## continuar legível — nessa altura não cabe ao lado do nome nos 300 px da
## sidebar, daí ela ficar acima.
func _marca() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)

	if ResourceLoader.exists(LOGO):
		var img := TextureRect.new()
		img.texture = load(LOGO)
		img.custom_minimum_size = Vector2(120, 120)
		img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		col.add_child(img)

	var nome := Label.new()
	nome.text = "QuestRetro"
	nome.add_theme_font_size_override("font_size", 28)
	col.add_child(nome)

	# Respiro menor que o dos outros blocos: é o que sobra de folga vertical na
	# sidebar depois de a nav baixar para 64 px (ver ALT_NAV). Os 120 px da logo
	# ficam onde estão — encolhê-la é que apagaria o D-pad.
	return _margem(col, TemaVR.PAD_SIDEBAR, 0, 20, 16)


func _item_nav(nome: String) -> Button:
	var bt := Button.new()
	bt.text = nome
	bt.alignment = HORIZONTAL_ALIGNMENT_LEFT
	bt.custom_minimum_size.y = TemaVR.ALT_NAV
	bt.focus_mode = Control.FOCUS_NONE
	bt.add_theme_font_size_override("font_size", TemaVR.TXT_NAV)
	bt.pressed.connect(func() -> void: mostrar(nome))
	_realcar(bt, false)
	return bt


func _realcar(bt: Button, ativo: bool) -> void:
	bt.add_theme_stylebox_override("normal", _estilo_nav(ativo))
	bt.add_theme_stylebox_override("hover", _estilo_nav(ativo))
	bt.add_theme_color_override("font_color", TemaVR.INK if ativo else TemaVR.DIM)


## Item ativo: fundo elevado com uma barra de acento à esquerda. A barra é o
## que dá para ler de relance sem depender só da diferença de fundo.
func _estilo_nav(ativo: bool) -> StyleBox:
	var sb := StyleBoxFlat.new()
	sb.bg_color = TemaVR.RAISED if ativo else Color.TRANSPARENT
	sb.set_corner_radius_all(TemaVR.RAIO)
	if ativo:
		sb.border_width_left = 4
		sb.border_color = TemaVR.ACCENT
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	return sb


func _rodape_sidebar() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 5)

	var lab := WidgetsVR.mono("RODANDO")
	col.add_child(lab)

	_rom_lab = Label.new()
	_rom_lab.add_theme_font_size_override("font_size", TemaVR.TXT_MONO)
	_rom_lab.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_rom_lab.clip_text = true
	col.add_child(_rom_lab)

	_atualizar_rodape()
	return col


func _atualizar_rodape() -> void:
	if _rom_lab == null:
		return
	_rom_lab.text = _emu.rom_atual.get_file() if not _emu.rom_atual.is_empty() else "nenhuma ROM"


func _divisoria_vertical() -> Control:
	var r := ColorRect.new()
	r.color = TemaVR.LINE
	r.custom_minimum_size.x = TemaVR.BORDA
	return r


func _margem(interno: Control, h: int, v: int, topo := -1, base := -1) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", h)
	m.add_theme_constant_override("margin_right", h)
	m.add_theme_constant_override("margin_top", topo if topo >= 0 else v)
	m.add_theme_constant_override("margin_bottom", base if base >= 0 else v)
	m.add_child(interno)
	return m
