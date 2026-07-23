class_name WidgetsVR
extends RefCounted
## Fábricas dos controles do painel, já ligadas ao ConfigEmu.
##
## Cada fábrica devolve o controle *e* faz a ligação de mão dupla: mexer no
## widget chama definir(), e `mudou` reflete de volta. Assim uma página inteira
## costuma ser meia dúzia de chamadas, e o analógico direito mexendo no tamanho
## da tela atualiza o slider sem código extra.


## Liga `cb` ao sinal `mudou` do config e desfaz a ligação quando `alvo` sai da
## árvore.
##
## Necessário porque estas fábricas são estáticas: um lambda criado aqui não
## pertence a nenhum objeto, então o Godot não tem o que desconectar quando o
## widget morre. Sem isto, o config guardaria callbacks apontando para nós já
## liberados e o próximo definir() falharia.
static func _refletir(cfg: ConfigEmu, alvo: Control, cb: Callable) -> void:
	cfg.mudou.connect(cb)
	alvo.tree_exiting.connect(func() -> void:
		if cfg.mudou.is_connected(cb):
			cfg.mudou.disconnect(cb)
	)


## Uma linha de configuração: rótulo (com descrição opcional) à esquerda,
## controle à direita. Espelha o `.field` do mockup.
static func campo(rotulo: String, descricao: String, controle: Control) -> Control:
	var linha := HBoxContainer.new()
	linha.add_theme_constant_override("separation", 28)
	linha.custom_minimum_size.y = 88

	var col := VBoxContainer.new()
	col.custom_minimum_size.x = 300
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_theme_constant_override("separation", 2)

	var lab := Label.new()
	lab.text = rotulo
	col.add_child(lab)

	if not descricao.is_empty():
		var desc := Label.new()
		desc.text = descricao
		desc.add_theme_font_size_override("font_size", TemaVR.TXT_DESC)
		desc.add_theme_color_override("font_color", TemaVR.DIM)
		col.add_child(desc)

	linha.add_child(col)

	controle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	linha.add_child(controle)
	return linha


## Slider ligado a uma chave float. `formato` recebe o valor e devolve o texto
## mostrado à direita (ex: func(v): return "%.2f×" % v).
static func slider(cfg: ConfigEmu, chave: String, minimo: float, maximo: float,
		passo: float, formato: Callable) -> Control:
	var caixa := HBoxContainer.new()
	caixa.add_theme_constant_override("separation", 18)

	var sl := HSlider.new()
	sl.min_value = minimo
	sl.max_value = maximo
	sl.step = passo
	sl.value = cfg.obter(chave)
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sl.custom_minimum_size.y = 44
	caixa.add_child(sl)

	var val := Label.new()
	val.text = formato.call(sl.value)
	val.custom_minimum_size.x = 140
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val.add_theme_font_size_override("font_size", TemaVR.TXT_VALOR)
	caixa.add_child(val)

	sl.value_changed.connect(func(v: float) -> void:
		val.text = formato.call(v)
		cfg.definir(chave, v)
	)
	# Reflete mudanças vindas de fora (o analógico direito também mexe nisto).
	_refletir(cfg, caixa, func(k: String, v: Variant) -> void:
		if k == chave and not is_equal_approx(sl.value, v):
			sl.set_value_no_signal(v)
			val.text = formato.call(v)
	)
	return caixa


## Interruptor ligado a uma chave bool.
static func interruptor(cfg: ConfigEmu, chave: String) -> Control:
	var caixa := HBoxContainer.new()
	var bt := CheckButton.new()
	bt.button_pressed = cfg.obter(chave)
	bt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bt.custom_minimum_size.y = TemaVR.ALT_LINHA
	caixa.add_child(bt)

	bt.toggled.connect(func(on: bool) -> void: cfg.definir(chave, on))
	_refletir(cfg, caixa, func(k: String, v: Variant) -> void:
		if k == chave and bt.button_pressed != v:
			bt.set_pressed_no_signal(v)
	)
	return caixa


## Grupo de opções mutuamente exclusivas, ligado ao índice da opção escolhida.
## Aceita chave int ou bool (bool = duas opções, falsa primeiro) e grava sempre
## no tipo que o ConfigEmu declarou — gravar int numa chave bool faria o
## carregar() descartar o valor na sessão seguinte.
static func segmentado(cfg: ConfigEmu, chave: String, opcoes: Array) -> Control:
	var caixa := HBoxContainer.new()
	caixa.add_theme_constant_override("separation", 5)
	caixa.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var eh_bool := typeof(cfg.obter(chave)) == TYPE_BOOL
	var para_indice := func(v: Variant) -> int: return (1 if v else 0) if eh_bool else int(v)

	var grupo := ButtonGroup.new()
	var botoes: Array[Button] = []
	var atual: int = para_indice.call(cfg.obter(chave))

	for i in opcoes.size():
		var bt := Button.new()
		bt.text = str(opcoes[i])
		bt.toggle_mode = true
		bt.button_group = grupo
		bt.button_pressed = (i == atual)
		bt.custom_minimum_size = Vector2(0, TemaVR.ALT_LINHA)
		bt.focus_mode = Control.FOCUS_NONE
		caixa.add_child(bt)
		botoes.append(bt)
		var indice := i
		bt.pressed.connect(func() -> void:
			cfg.definir(chave, (indice == 1) if eh_bool else indice)
		)

	_refletir(cfg, caixa, func(k: String, v: Variant) -> void:
		if k != chave:
			return
		var i: int = para_indice.call(v)
		if i >= 0 and i < botoes.size():
			botoes[i].set_pressed_no_signal(true)
	)
	return caixa


static func botao(texto: String, primario := false) -> Button:
	var bt := Button.new()
	bt.text = texto
	bt.custom_minimum_size = Vector2(180, TemaVR.ALT_LINHA)
	if primario:
		bt.add_theme_stylebox_override("normal", TemaVR.caixa_botao(TemaVR.ACCENT, TemaVR.ACCENT))
		bt.add_theme_stylebox_override("hover",
				TemaVR.caixa_botao(TemaVR.ACCENT.lightened(0.12), TemaVR.ACCENT))
		bt.add_theme_color_override("font_color", TemaVR.GROUND)
		bt.add_theme_color_override("font_hover_color", TemaVR.GROUND)
	return bt


## Rótulo em mono para caminhos, tamanhos e valores — o registro "de dado"
## do painel, separado do texto de interface.
static func mono(texto: String, cor: Color = TemaVR.DIM) -> Label:
	var lab := Label.new()
	lab.text = texto
	lab.add_theme_font_size_override("font_size", TemaVR.TXT_MONO)
	lab.add_theme_color_override("font_color", cor)
	return lab


## Chip de botão do controle (A/B/X/Y e afins) da página de Input.
static func chip(texto: String, cor: Color) -> Control:
	var lab := Label.new()
	lab.text = texto
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lab.custom_minimum_size = Vector2(120, 48)
	lab.add_theme_font_size_override("font_size", TemaVR.TXT_MONO)
	lab.add_theme_color_override("font_color", cor.lightened(0.35))
	lab.add_theme_stylebox_override("normal",
			TemaVR.caixa(TemaVR.RAISED, TemaVR.RAIO_CHIP, cor))
	return lab


## Divisória horizontal de 2 px, na cor das bordas.
static func divisoria(cor: Color = TemaVR.SURFACE) -> Control:
	var r := ColorRect.new()
	r.color = cor
	r.custom_minimum_size.y = TemaVR.BORDA
	return r
