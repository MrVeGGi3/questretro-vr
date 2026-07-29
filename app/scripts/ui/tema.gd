class_name TemaVR
extends RefCounted
## Theme do painel VR — transcrição literal do mockup de design.
##
## Construído em código (e não num .tres) porque o resto do projeto monta UI
## assim, e porque estes números são decisões documentadas: um .tres binário
## esconderia num diff o que aqui está explícito.
##
## Os tamanhos são em pixels do SubViewport de 1280x800, que vira um quad de
## ~1 m visto a ~2 m. Daí os alvos grandes: a essa distância o tremor da mão
## move o laser alguns centímetros, e alvo menor que ~64 px vira disputa
## contra a própria mão.

# --- cores ---
const GROUND  := Color("16141b")   ## fundo do painel
const SURFACE := Color("1f1c26")   ## sidebar, segmentado, slots
const RAISED  := Color("2a2534")   ## item ativo, botão, trilho de slider
const LINE    := Color("383243")   ## bordas e divisórias
const INK     := Color("efecf4")   ## texto principal
const DIM     := Color("9992a6")   ## texto secundário, itens inativos
const ACCENT  := Color("9a85e8")   ## seleção, botão primário, foco

# Cores dos botões do Super Famicom. Só aparecem nos chips A/B/X/Y da página
# de Input, onde codificam qual botão é qual — nunca como enfeite.
const BTN_A := Color("c4514a")
const BTN_B := Color("d4a43c")
const BTN_X := Color("4c8cc4")
const BTN_Y := Color("5d9b62")

# --- medidas ---
const PAINEL := Vector2i(1280, 800)
const SIDEBAR := 300
## Item da sidebar: o menor alvo do painel, e por isso no piso dos 64 px que o
## comentário acima justifica — abaixo disso o tremor da mão ganha do laser.
##
## Era 72 e **não cabia**: com sete páginas, a sidebar pedia 852 px de altura num
## painel de 800 (marca 221 + nav 528 + divisória 2 + rodapé 101). Um Control
## ancorado nunca encolhe abaixo do próprio mínimo, então o painel inteiro
## nascia 56 px mais alto que o viewport e o que estava embaixo caía fora — o
## rodapé de *toda* página, o que na de ROMs é o botão "Carregar". A oitava
## página volta a estourar; quem segura isso agora é a asserção em `test_ui`.
const ALT_NAV := 64
const ALT_LINHA := 64      ## linha de lista e botão
const ALT_CABECALHO := 96
const ALT_RODAPE := 104
const PAD := 36
const PAD_SIDEBAR := 28
const RAIO_PAINEL := 20
const RAIO := 12
const RAIO_CHIP := 8
const BORDA := 2

# --- tipografia ---
const TXT_TITULO := 34
const TXT_NAV := 26
const TXT_ITEM := 25
const TXT_MONO := 21
const TXT_VALOR := 23
const TXT_DESC := 18


static func criar() -> Theme:
	var t := Theme.new()
	t.default_font_size = TXT_ITEM

	_botoes(t)
	_rotulos(t)
	_sliders(t)
	_scroll(t)
	return t


static func caixa(cor: Color, raio: int = RAIO, borda_cor: Variant = null,
		borda: int = BORDA) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = cor
	sb.set_corner_radius_all(raio)
	if borda_cor != null:
		sb.set_border_width_all(borda)
		sb.border_color = borda_cor
	return sb


## Igual a caixa(), mas com respiro interno — o mínimo do botão passa a
## considerar o texto, então rótulo comprido alarga o botão em vez de vazar.
static func caixa_botao(cor: Color, borda_cor: Variant = null) -> StyleBoxFlat:
	var sb := caixa(cor, RAIO, borda_cor)
	sb.content_margin_left = 26
	sb.content_margin_right = 26
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	return sb


static func vazio() -> StyleBoxEmpty:
	return StyleBoxEmpty.new()


static func _botoes(t: Theme) -> void:
	var normal := caixa_botao(RAISED, LINE)
	var hover := caixa_botao(LINE, ACCENT)
	var press := caixa_botao(ACCENT, ACCENT)
	var foco := caixa_botao(Color.TRANSPARENT, ACCENT)

	for tipo in ["Button", "CheckButton", "OptionButton"]:
		t.set_stylebox("normal", tipo, normal)
		t.set_stylebox("hover", tipo, hover)
		t.set_stylebox("pressed", tipo, press)
		t.set_stylebox("focus", tipo, foco)
		t.set_stylebox("disabled", tipo, caixa_botao(SURFACE, LINE))
		t.set_color("font_color", tipo, INK)
		t.set_color("font_hover_color", tipo, INK)
		t.set_color("font_pressed_color", tipo, GROUND)
		t.set_color("font_disabled_color", tipo, DIM)
		t.set_font_size("font_size", tipo, TXT_ITEM)
		t.set_constant("h_separation", tipo, 12)


static func _rotulos(t: Theme) -> void:
	t.set_color("font_color", "Label", INK)
	t.set_font_size("font_size", "Label", TXT_ITEM)
	t.set_color("default_color", "RichTextLabel", INK)
	t.set_font_size("normal_font_size", "RichTextLabel", TXT_ITEM)


static func _sliders(t: Theme) -> void:
	var trilho := StyleBoxFlat.new()
	trilho.bg_color = RAISED
	trilho.set_corner_radius_all(6)
	trilho.content_margin_top = 6
	trilho.content_margin_bottom = 6

	var preenchido := StyleBoxFlat.new()
	preenchido.bg_color = ACCENT
	preenchido.set_corner_radius_all(6)

	t.set_stylebox("slider", "HSlider", trilho)
	t.set_stylebox("grabber_area", "HSlider", preenchido)
	t.set_stylebox("grabber_area_highlight", "HSlider", preenchido)
	# O "grabber" é uma textura no tema padrão; sem uma, o Godot desenha nada.
	# Um círculo gerado é mais barato que carregar um PNG só para isso.
	var pegador := _circulo(34, INK)
	t.set_icon("grabber", "HSlider", pegador)
	t.set_icon("grabber_highlight", "HSlider", pegador)
	t.set_constant("center_grabber", "HSlider", 1)


static func _scroll(t: Theme) -> void:
	t.set_stylebox("panel", "ScrollContainer", vazio())
	var barra := StyleBoxFlat.new()
	barra.bg_color = RAISED
	barra.set_corner_radius_all(6)
	var pega := StyleBoxFlat.new()
	pega.bg_color = LINE
	pega.set_corner_radius_all(6)
	t.set_stylebox("scroll", "VScrollBar", barra)
	t.set_stylebox("grabber", "VScrollBar", pega)
	t.set_stylebox("grabber_highlight", "VScrollBar", caixa(ACCENT, 6))
	t.set_stylebox("grabber_pressed", "VScrollBar", caixa(ACCENT, 6))


## Círculo preenchido como ImageTexture — o grabber do HSlider precisa de um
## ícone, e gerar evita carregar um asset de 34 px.
static func _circulo(diametro: int, cor: Color) -> ImageTexture:
	var img := Image.create(diametro, diametro, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var r := diametro * 0.5
	for y in diametro:
		for x in diametro:
			var d := Vector2(x + 0.5 - r, y + 0.5 - r).length()
			if d <= r - 1.0:
				img.set_pixel(x, y, cor)
			elif d <= r:
				# Uma faixa de 1 px de alpha parcial tira o serrilhado da borda.
				img.set_pixel(x, y, Color(cor.r, cor.g, cor.b, r - d))
	return ImageTexture.create_from_image(img)
