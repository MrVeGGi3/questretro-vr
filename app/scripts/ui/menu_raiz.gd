class_name MenuRaiz
extends Control
## Raiz do menu: sidebar à esquerda, página ativa à direita.
##
## Sidebar em vez de abas no topo porque os alvos ficam grandes e afastados —
## a 2 m de distância mirar com o laser numa faixa de abas é uma briga contra
## o tremor da própria mão.

signal fechar_pedido
signal rom_escolhida(caminho: String)
signal centrar_pedido

const LOGO := "res://assets/logo.png"

## As abas, na ordem em que aparecem na sidebar.
##
## **Uma lista só, e é o ponto.** A sidebar e o registro de páginas eram duas
## listas escritas à mão que precisavam concordar; acrescentar uma página em
## `_criar_paginas()` sem lembrar da outra derrubava `mostrar()` num
## `_botoes[chave]` inexistente — erro que aparece no log e **não** reprova nada,
## porque a página nova simplesmente não é exercitada. Foi o que aconteceu ao
## acrescentar "Cores". Agora quem registra confere contra esta lista.
##
## **Oito é o teto com esta geometria, e a folga é zero.** Com a logo a 70 px, o
## rodapé da página fecha em exatamente 800 de 800 — uma nona aba volta a empurrar
## tudo para fora do painel. O `_conferir_rodape_visivel` do `test_ui` reprova
## quando isso acontece, então quem acrescentar a nona vai saber na hora; o que
## não dá é acrescentar e supor que coube.
const ABAS := ["ROMs", "Tela", "Sala", "Vídeo", "Áudio", "Input", "Saves", "Cores"]

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

	var tela := PagTela.new(_cfg, _emu)
	tela.centrar_pedido.connect(func() -> void: centrar_pedido.emit())

	_registrar("ROMs", roms)
	_registrar("Tela", tela)
	_registrar("Sala", PagSala.new(_cfg))
	_registrar("Vídeo", PagVideo.new(_cfg, _emu))
	_registrar("Áudio", PagAudio.new(_cfg, _emu))
	_registrar("Input", PagInput.new(_cfg, _emu))
	_registrar("Saves", PagSaves.new(_emu))
	# Depois de Saves porque é a página que se visita uma vez e esquece — ao
	# contrário das outras, que se mexe a cada sessão.
	_registrar("Cores", PagCores.new())


func _registrar(nome: String, pag: Control) -> void:
	# Sem botão na sidebar a página é inalcançável, e `mostrar()` quebra ao tentar
	# realçar um botão que não existe. Falhar aqui, alto, é melhor do que descobrir
	# no headset que uma aba não abre.
	assert(nome in ABAS, "página '%s' não está em MenuRaiz.ABAS" % nome)
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
	# Um core pode ter sido copiado à mão pelo USB desde a última vez, e a página
	# não pode contradizer a pasta.
	(_paginas["Cores"] as PagCores).atualizar()
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
	for nome in ABAS:
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


## A logo fica acima do nome, e não ao lado, porque nos 300 px da sidebar não
## sobra largura para os dois lado a lado.
##
## **70 px, e não os 120 de antes.** Aqueles 120 existiam para o D-pad da arte
## anterior continuar legível; a arte foi trocada e o motivo foi junto — o visor
## com a escada de pixels não tem gamepad nenhum, e foi conferido a 64 px, que é
## o tamanho de ícone de launcher. Os 50 px liberados são exatamente o que a
## oitava aba precisava, e é melhor gastá-los aí do que encolher alvo de laser:
## a sidebar existe justamente porque alvo grande é o que se acerta a 2 m.
func _marca() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)

	if ResourceLoader.exists(LOGO):
		var img := TextureRect.new()
		img.texture = load(LOGO)
		img.custom_minimum_size = Vector2(70, 70)
		img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		col.add_child(img)

	var nome := Label.new()
	nome.text = "QuestRetro"
	nome.add_theme_font_size_override("font_size", 28)
	col.add_child(nome)

	# Respiro menor que o dos outros blocos: é o que sobra de folga vertical na
	# sidebar depois de a nav baixar para 64 px (ver ALT_NAV).
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
