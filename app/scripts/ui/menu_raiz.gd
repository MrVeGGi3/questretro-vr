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
## São as **chaves de tradução**, e não rótulos: o `.text` do botão recebe a
## chave e o motor traduz ao desenhar. Usá-las também como identificador interno
## evita um segundo mapa "id -> rótulo" que teria de concordar com este — e lista
## paralela que precisa concordar já quebrou este menu uma vez.
const ABAS := ["MENU_ROMS", "MENU_TELA", "MENU_SALA", "MENU_VIDEO", "MENU_AUDIO",
		"MENU_INPUT", "MENU_SAVES", "MENU_CORES"]

## Fundo "vidro" (Vídeo → Vidro): o frame do jogo, borrado e escurecido, atrás
## do menu.
##
## **Não é blur do que está atrás do painel**, e é de propósito. O blur de verdade
## precisaria copiar a tela de cada olho no meio do frame (`hint_screen_texture`),
## que no Compatibility vem sem mipmaps, em multiview é incerto e numa GPU tiler
## é o padrão caro por banda; e no Passthrough sairia preto, porque o quarto é
## composto pelo runtime depois do Godot. Borrar a textura do emulador, que já
## existe, custa uma passada 2D no SubViewport do menu: uma vez por frame, e não
## uma por olho, e só com o painel aberto (fechado, ele não redesenha). Medido no
## Quest 3S: 79 amostras com o vidro e o menu aberto, mediana 72 fps.
##
## Com jogo, o painel continua **opaco** no 3D: o véu é aplicado no shader. Sem
## jogo não há o que borrar, e o vidro vira só translucidez (`VIDRO_SEM_JOGO`):
## a sala aparece atrás, escurecida e nítida. Também de graça, porque o quad do
## painel já é desenhado com alpha, e vale no Passthrough, onde o runtime compõe
## o quarto por baixo do que o Godot deixou translúcido.
##
## Quanto do véu cobre o jogo. Menos que isso e o texto pequeno (`TXT_DESC`)
## começa a disputar com o que se mexe atrás: em VR, legibilidade é conforto.
const VIDRO_VEU := 0.78
## Raio do borrão, em fração da largura da imagem do jogo.
const VIDRO_ALCANCE := 0.035
## Opacidade do fundo quando o vidro está ligado e não há jogo. Mais alta que a
## do véu porque aqui nada é borrado: a sala atrás chega nítida, e detalhe nítido
## atrás de texto disputa mais que mancha de cor.
const VIDRO_SEM_JOGO := 0.82
## A sidebar sobre o vidro: translúcida para não tapá-lo, e ainda assim mais
## clara que o resto, como no painel opaco.
const VIDRO_SIDEBAR := 0.55
## Nove amostras por pixel com filtro linear. Poucas para um blur "de livro",
## mas debaixo de 78 % de véu o que sobra é a mancha de cor, que é o efeito
## inteiro, e o custo fica no nível de uma camada de UI a mais.
const VIDRO_SHADER := """
shader_type canvas_item;

uniform vec2 uv_inicio = vec2(0.0);
uniform vec2 uv_escala = vec2(1.0);
uniform vec2 tamanho = vec2(1280.0, 800.0);
uniform float raio_canto = 20.0;
uniform float alcance = 0.035;
uniform vec4 veu : source_color;

// `TEXTURE` só existe dentro de `fragment()`, então o sampler vem por parâmetro.
vec3 amostra(sampler2D t, vec2 uv) {
	return texture(t, clamp(uv, uv_inicio, uv_inicio + uv_escala)).rgb;
}

void fragment() {
	vec2 uv = uv_inicio + UV * uv_escala;
	vec2 d = vec2(alcance, alcance * tamanho.x / tamanho.y) * uv_escala;
	vec2 m = d * 0.5;
	vec3 c = amostra(TEXTURE, uv) * 0.2;
	c += (amostra(TEXTURE, uv + vec2(m.x, 0.0)) + amostra(TEXTURE, uv - vec2(m.x, 0.0))
		+ amostra(TEXTURE, uv + vec2(0.0, m.y)) + amostra(TEXTURE, uv - vec2(0.0, m.y))) * 0.1;
	c += (amostra(TEXTURE, uv + d) + amostra(TEXTURE, uv - d)
		+ amostra(TEXTURE, uv + vec2(d.x, -d.y)) + amostra(TEXTURE, uv + vec2(-d.x, d.y))) * 0.1;
	c = mix(c, veu.rgb, veu.a);

	// Recorte com cantos arredondados, igual ao do StyleBox do fundo: o
	// TextureRect é retangular e vazaria o jogo nas quinas.
	vec2 p = abs(UV * tamanho - tamanho * 0.5) - (tamanho * 0.5 - vec2(raio_canto));
	float dist = length(max(p, 0.0)) + min(max(p.x, p.y), 0.0) - raio_canto;
	COLOR = vec4(c, clamp(0.5 - dist, 0.0, 1.0));
}
"""

var _cfg: ConfigEmu
var _emu: EmuCore
var _paginas: Dictionary = {}      ## nome -> Control
var _botoes: Dictionary = {}       ## nome -> Button
var _area: Control
var _rom_lab: Label
var _ativa := ""

var _vidro: TextureRect
var _vidro_ligado := false         ## a preferência; o vidro só aparece com jogo
var _vidro_ds := false
var _vidro_aplicado := false       ## a preferência que `_atualizar_vidro` já pintou
var _fundo_sb: StyleBoxFlat
var _sidebar_sb: StyleBoxFlat


func _init(cfg: ConfigEmu, emu: EmuCore) -> void:
	_cfg = cfg
	_emu = emu

	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = TemaVR.criar()

	_vidro = _criar_vidro()
	add_child(_vidro)

	var fundo := PanelContainer.new()
	fundo.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fundo_sb = TemaVR.caixa(TemaVR.GROUND, TemaVR.RAIO_PAINEL, TemaVR.LINE)
	fundo.add_theme_stylebox_override("panel", _fundo_sb)
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
	mostrar("MENU_ROMS")

	# `auto_translate_mode` refaz sozinho todo `.text` que é uma chave, mas **não**
	# alcança string montada com `%` — aquilo já é String comum quando chega ao
	# Label. Remontar as páginas conserta essas, e é barato: acontece uma vez por
	# troca de idioma, não por frame.
	_cfg.mudou.connect(func(k: String, v: Variant) -> void:
		if k != "app/idioma":
			return
		Idioma.aplicar(Idioma.indice_valido(v))
		ao_abrir()
	)

	_vidro_ligado = _cfg.obter("video/painel_vidro")
	_cfg.mudou.connect(func(k: String, v: Variant) -> void:
		if k == "video/painel_vidro":
			_vidro_ligado = v
	)
	_atualizar_vidro()


## Confere a cada frame, e não por sinal, porque a textura do emulador é
## **trocada** (e não só atualizada) quando a resolução muda, e o `iniciado`
## chega antes do primeiro frame que a cria. É o mesmo que `xr_main._atualizar_tela()`
## faz pelo mesmo motivo. Fora a comparação, não custa nada quando nada mudou.
func _process(_delta: float) -> void:
	_atualizar_vidro()


func _criar_vidro() -> TextureRect:
	var r := TextureRect.new()
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.visible = false

	var shader := Shader.new()
	shader.code = VIDRO_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("tamanho", Vector2(TemaVR.PAINEL))
	mat.set_shader_parameter("raio_canto", float(TemaVR.RAIO_PAINEL))
	mat.set_shader_parameter("alcance", VIDRO_ALCANCE)
	mat.set_shader_parameter("veu", Color(TemaVR.GROUND, VIDRO_VEU))
	r.material = mat
	return r


func vidro_visivel() -> bool:
	return _vidro.visible


func _atualizar_vidro() -> void:
	var tex: Texture2D = _emu.texture if _vidro_ligado else null
	var ds := tex != null and NavegadorRoms.tem_duas_telas(_emu.sistema)
	if tex == _vidro.texture and ds == _vidro_ds and _vidro_ligado == _vidro_aplicado:
		return
	_vidro_aplicado = _vidro_ligado
	_vidro.texture = tex
	_vidro_ds = ds
	_vidro.visible = tex != null

	# No DS a textura é as duas telas empilhadas; o fundo usa só a de cima, com
	# o mesmo recorte que a tela 3D usa (`CanetaDS`).
	var mat := _vidro.material as ShaderMaterial
	mat.set_shader_parameter("uv_inicio",
			Vector2(CanetaDS.UV_CIMA.x, CanetaDS.UV_CIMA.y) if ds else Vector2.ZERO)
	mat.set_shader_parameter("uv_escala",
			Vector2(CanetaDS.UV_ESCALA.x, CanetaDS.UV_ESCALA.y) if ds else Vector2.ONE)

	# Com o jogo borrado, o véu já vem do shader e o fundo vira só a borda. Sem
	# jogo, o próprio fundo é o vidro, translúcido.
	var fundo := TemaVR.GROUND
	var lateral := TemaVR.SURFACE
	if _vidro_ligado:
		fundo.a = 0.0 if _vidro.visible else VIDRO_SEM_JOGO
		lateral.a = VIDRO_SIDEBAR
	_fundo_sb.bg_color = fundo
	_sidebar_sb.bg_color = lateral


func _criar_paginas() -> void:
	var roms := PagRoms.new(_cfg)
	roms.rom_escolhida.connect(func(caminho: String) -> void: rom_escolhida.emit(caminho))
	roms.cancelado.connect(func() -> void: fechar_pedido.emit())

	var tela := PagTela.new(_cfg, _emu)
	tela.centrar_pedido.connect(func() -> void: centrar_pedido.emit())

	_registrar("MENU_ROMS", roms)
	_registrar("MENU_TELA", tela)
	_registrar("MENU_SALA", PagSala.new(_cfg))
	_registrar("MENU_VIDEO", PagVideo.new(_cfg, _emu))
	_registrar("MENU_AUDIO", PagAudio.new(_cfg, _emu))
	_registrar("MENU_INPUT", PagInput.new(_cfg, _emu))
	_registrar("MENU_SAVES", PagSaves.new(_emu))
	# Depois de Saves porque é a página que se visita uma vez e esquece — ao
	# contrário das outras, que se mexe a cada sessão.
	_registrar("MENU_CORES", PagCores.new())


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
	(_paginas["MENU_ROMS"] as PagRoms).atualizar()
	(_paginas["MENU_SAVES"] as PagSaves).atualizar()
	# O mapa de controle muda com o sistema da ROM, e a ROM pode ter trocado
	# desde a última vez que o painel abriu. A página de Tela pela mesma razão:
	# os ajustes da segunda tela só existem nos sistemas que têm duas.
	(_paginas["MENU_INPUT"] as PagInput).atualizar()
	(_paginas["MENU_TELA"] as PagTela).atualizar()
	# Um core pode ter sido copiado à mão pelo USB desde a última vez, e a página
	# não pode contradizer a pasta.
	(_paginas["MENU_CORES"] as PagCores).atualizar()
	_atualizar_rodape()


func _sidebar() -> Control:
	var painel := PanelContainer.new()
	painel.custom_minimum_size.x = TemaVR.SIDEBAR
	_sidebar_sb = TemaVR.caixa(TemaVR.SURFACE, 0)
	painel.add_theme_stylebox_override("panel", _sidebar_sb)

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

	var lab := WidgetsVR.mono("MENU_RODANDO")
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
	_rom_lab.text = _emu.rom_atual.get_file() if not _emu.rom_atual.is_empty() else tr("MENU_SEM_ROM")


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
