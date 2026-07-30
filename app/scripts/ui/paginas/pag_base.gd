class_name PagBase
extends Control
## Moldura comum das páginas do menu: cabeçalho fixo, conteúdo rolável e
## rodapé fixo. As subclasses só preenchem `conteudo` e `rodape`.

var titulo_lab: Label
var caminho_lab: Label      ## texto em mono à direita do título
var conteudo: VBoxContainer ## área rolável
var rodape: HBoxContainer


func _init(titulo: String) -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", 0)
	add_child(col)

	col.add_child(_cabecalho(titulo))
	col.add_child(WidgetsVR.divisoria(TemaVR.LINE))

	var rolagem := ScrollContainer.new()
	rolagem.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rolagem.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(rolagem)

	conteudo = VBoxContainer.new()
	conteudo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	conteudo.add_theme_constant_override("separation", 4)
	var env := _com_margem(conteudo, TemaVR.PAD, 20)
	env.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rolagem.add_child(env)

	col.add_child(WidgetsVR.divisoria(TemaVR.LINE))

	rodape = HBoxContainer.new()
	rodape.add_theme_constant_override("separation", 16)
	var env_rodape := _com_margem(rodape, TemaVR.PAD, 0)
	env_rodape.custom_minimum_size.y = TemaVR.ALT_RODAPE
	col.add_child(env_rodape)


func _cabecalho(titulo: String) -> Control:
	var caixa := HBoxContainer.new()
	caixa.add_theme_constant_override("separation", 24)

	titulo_lab = Label.new()
	titulo_lab.text = titulo
	titulo_lab.add_theme_font_size_override("font_size", TemaVR.TXT_TITULO)
	titulo_lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caixa.add_child(titulo_lab)

	caminho_lab = WidgetsVR.mono("")
	caminho_lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	caminho_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	caminho_lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# O fim do caminho é o que localiza você; cortar o começo preserva o útil.
	caminho_lab.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	caminho_lab.clip_text = true
	caixa.add_child(caminho_lab)

	var env := _com_margem(caixa, TemaVR.PAD, 0)
	env.custom_minimum_size.y = TemaVR.ALT_CABECALHO
	return env


## Empurra as ações do rodapé para a direita.
func espacador() -> Control:
	var e := Control.new()
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return e


## Rodapé padrão das páginas de ajuste: onde salva, à esquerda; restaurar, à direita.
func rodape_de_ajuste(cfg: ConfigEmu, secao: String) -> void:
	rodape.add_child(WidgetsVR.mono(tr("COMUM_SALVO_EM") + " " + ConfigEmu.ARQUIVO))
	rodape.add_child(espacador())
	var bt := WidgetsVR.botao("COMUM_RESTAURAR")
	bt.pressed.connect(func() -> void: cfg.restaurar(secao))
	rodape.add_child(bt)


## MarginContainer é o único container do Godot que aplica margem; sobrepor
## "margin_*" num HBox/VBox não faz nada.
func _com_margem(interno: Control, h: int, v: int) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", h)
	m.add_theme_constant_override("margin_right", h)
	m.add_theme_constant_override("margin_top", v)
	m.add_theme_constant_override("margin_bottom", v)
	m.add_child(interno)
	return m
