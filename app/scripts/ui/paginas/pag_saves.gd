class_name PagSaves
extends PagBase
## Save states em quatro slots, por ROM.
##
## O estado bruto vem do core (LibretroHost.save_state); o arquivo, a miniatura
## e o carimbo de tempo são responsabilidade daqui. A miniatura é o próprio
## frame que estava na tela no momento da gravação.

const SLOTS := 4
const PASTA := "user://states"

## Altura do slot, escolhida para os quatro caberem sem rolar: sobram 556 px de
## área rolável, e 4×112 mais as separações e a linha da bateria fecham em 550.
## Um save que só aparece depois de rolar é um save que o jogador esquece.
const ALT_SLOT := 112

## Largura da miniatura. Cabe um frame 4:3 na altura interna do slot (80 px) com
## folga de sobra.
const LARG_MINIATURA := 120

var _emu: EmuCore
var _grade: GridContainer
var _bateria: Label


func _init(emu: EmuCore) -> void:
	super("Saves")
	_emu = emu

	# A SRAM se grava sozinha, sem o jogador pedir; esta linha é o único lugar
	# onde dá para conferir que o progresso do jogo foi mesmo para o disco.
	_bateria = WidgetsVR.mono("")
	_bateria.custom_minimum_size.y = 44
	_bateria.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	conteudo.add_child(_bateria)

	# Uma coluna, e não duas. Em duas, um slot ocupado precisa de miniatura mais
	# "Carregar" mais "Gravar" — larguras que somadas passam da metade do painel,
	# e a coluna da direita saía pela borda com os botões cortados. Como a rolagem
	# horizontal é desligada no PagBase, aquilo ficava inalcançável.
	_grade = GridContainer.new()
	_grade.columns = 1
	_grade.add_theme_constant_override("v_separation", 18)
	_grade.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	conteudo.add_child(_grade)

	rodape.add_child(WidgetsVR.mono(PASTA + "/"))
	rodape.add_child(espacador())

	atualizar()


## Rechamada sempre que o menu abre ou a ROM troca.
func atualizar() -> void:
	for filho in _grade.get_children():
		filho.queue_free()

	caminho_lab.text = _emu.rom_atual.get_file() if not _emu.rom_atual.is_empty() else "sem jogo"
	_bateria.text = _texto_bateria()

	if not _emu.suporta_estado():
		var aviso := Label.new()
		aviso.text = "Este core não implementa save states."
		aviso.add_theme_color_override("font_color", TemaVR.DIM)
		_grade.add_child(aviso)
		return

	for i in SLOTS:
		_grade.add_child(_slot(i + 1))


## Estado do save de bateria: se este jogo tem SRAM e quando ela foi gravada.
func _texto_bateria() -> String:
	if _emu.rom_atual.is_empty():
		return ""
	var bytes := _emu.tamanho_sram()
	if bytes <= 0:
		return "Bateria: este cartucho não tem"

	var tam := String.humanize_size(bytes)
	var caminho := _emu.caminho_sram()
	if not FileAccess.file_exists(caminho):
		return "Bateria: %s · ainda não gravada" % tam
	var d := Time.get_datetime_dict_from_unix_time(FileAccess.get_modified_time(caminho))
	return "Bateria: %s · gravada %02d/%02d · %02d:%02d" % [tam, d.day, d.month, d.hour, d.minute]


func _slot(numero: int) -> Control:
	var caminho := _emu.caminho_estado(numero)
	var existe := FileAccess.file_exists(caminho)

	var estilo := TemaVR.caixa(TemaVR.SURFACE, 14, TemaVR.LINE)
	estilo.set_content_margin_all(16)

	var caixa := PanelContainer.new()
	caixa.add_theme_stylebox_override("panel", estilo)
	caixa.custom_minimum_size.y = ALT_SLOT
	# Sem isto o GridContainer encolhe a coluna ao conteúdo e os slots ficam
	# amontoados à esquerda em vez de ocupar a largura.
	caixa.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Tudo numa linha só: miniatura, identificação, e as ações à direita. Empilhar
	# os botões debaixo do texto é o que exigia um slot alto, e quatro deles altos
	# não cabiam na página sem rolar.
	var linha := HBoxContainer.new()
	linha.add_theme_constant_override("separation", 20)
	caixa.add_child(linha)

	linha.add_child(_miniatura(numero, existe))

	var info := VBoxContainer.new()
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info.add_theme_constant_override("separation", 2)
	linha.add_child(info)

	var titulo := Label.new()
	titulo.text = "Slot %d" % numero
	info.add_child(titulo)

	var quando := WidgetsVR.mono("—")
	if existe:
		var t := FileAccess.get_modified_time(caminho)
		var d := Time.get_datetime_dict_from_unix_time(t)
		quando.text = "%02d/%02d · %02d:%02d" % [d.day, d.month, d.hour, d.minute]
	info.add_child(quando)

	linha.add_child(espacador())

	var acoes := HBoxContainer.new()
	acoes.add_theme_constant_override("separation", 10)
	acoes.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	linha.add_child(acoes)

	if existe:
		var bt_carregar := WidgetsVR.botao("Carregar")
		bt_carregar.custom_minimum_size = Vector2(0, 52)
		bt_carregar.pressed.connect(func() -> void:
			_emu.carregar_estado(numero)
		)
		acoes.add_child(bt_carregar)

	var bt_gravar := WidgetsVR.botao("Gravar")
	bt_gravar.custom_minimum_size = Vector2(0, 52)
	bt_gravar.disabled = _emu.rom_atual.is_empty()
	bt_gravar.pressed.connect(func() -> void:
		if _emu.gravar_estado(numero):
			atualizar()
	)
	acoes.add_child(bt_gravar)

	if existe:
		acoes.add_child(_botao_apagar(numero))

	return caixa


## Apagar pede duas batidas: a primeira arma e o botão passa a perguntar. Não é
## cerimônia — apagar um save state não tem desfazer, e no headset o clique sai
## de um laser apontado à distância, que erra o alvo com mais facilidade que um
## mouse. O estado mora no próprio botão, então sair da página desarma sozinho.
func _botao_apagar(numero: int) -> Button:
	var bt := WidgetsVR.botao("Apagar")
	bt.custom_minimum_size = Vector2(0, 52)
	# Nomeado porque quatro botões iguais só se distinguem pelo slot, e quem
	# procura por texto acha o primeiro — que foi como o teste deste botão
	# nasceu errado, armando um slot e conferindo outro.
	bt.name = "ApagarSlot%d" % numero
	bt.pressed.connect(func() -> void:
		if not bt.get_meta("armado", false):
			bt.set_meta("armado", true)
			bt.text = "Confirmar?"
			bt.add_theme_color_override("font_color", TemaVR.BTN_A)
			return
		if _emu.apagar_estado(numero):
			atualizar()
	)
	return bt


func _miniatura(numero: int, existe: bool) -> Control:
	var tr := TextureRect.new()
	tr.custom_minimum_size = Vector2(LARG_MINIATURA, 0)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	if existe:
		var png := _emu.caminho_miniatura(numero)
		if FileAccess.file_exists(png):
			var img := Image.new()
			if img.load(png) == OK:
				tr.texture = ImageTexture.create_from_image(img)
				return tr

	var vazio := Label.new()
	vazio.text = "vazio" if not existe else "sem imagem"
	vazio.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vazio.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	vazio.custom_minimum_size = Vector2(LARG_MINIATURA, 0)
	vazio.add_theme_font_size_override("font_size", TemaVR.TXT_DESC)
	vazio.add_theme_color_override("font_color", TemaVR.DIM)
	return vazio
