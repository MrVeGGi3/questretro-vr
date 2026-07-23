class_name PagSaves
extends PagBase
## Save states em quatro slots, por ROM.
##
## O estado bruto vem do core (LibretroHost.save_state); o arquivo, a miniatura
## e o carimbo de tempo são responsabilidade daqui. A miniatura é o próprio
## frame que estava na tela no momento da gravação.

const SLOTS := 4
const PASTA := "user://states"

var _emu: EmuCore
var _grade: GridContainer


func _init(emu: EmuCore) -> void:
	super("Saves")
	_emu = emu

	_grade = GridContainer.new()
	_grade.columns = 2
	_grade.add_theme_constant_override("h_separation", 18)
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

	if not _emu.suporta_estado():
		var aviso := Label.new()
		aviso.text = "Este core não implementa save states."
		aviso.add_theme_color_override("font_color", TemaVR.DIM)
		_grade.add_child(aviso)
		return

	for i in SLOTS:
		_grade.add_child(_slot(i + 1))


func _slot(numero: int) -> Control:
	var caminho := _emu.caminho_estado(numero)
	var existe := FileAccess.file_exists(caminho)

	var estilo := TemaVR.caixa(TemaVR.SURFACE, 14, TemaVR.LINE)
	estilo.set_content_margin_all(16)

	var caixa := PanelContainer.new()
	caixa.add_theme_stylebox_override("panel", estilo)
	caixa.custom_minimum_size.y = 148
	# Sem isto o GridContainer encolhe as colunas ao conteúdo e os slots ficam
	# amontoados à esquerda em vez de dividir a largura.
	caixa.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var linha := HBoxContainer.new()
	linha.add_theme_constant_override("separation", 20)
	caixa.add_child(linha)

	linha.add_child(_miniatura(numero, existe))

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 4)
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

	var acoes := HBoxContainer.new()
	acoes.add_theme_constant_override("separation", 10)
	acoes.size_flags_vertical = Control.SIZE_SHRINK_END
	info.add_child(acoes)

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

	return caixa


func _miniatura(numero: int, existe: bool) -> Control:
	var tr := TextureRect.new()
	tr.custom_minimum_size = Vector2(172, 0)
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
	vazio.custom_minimum_size = Vector2(172, 0)
	vazio.add_theme_font_size_override("font_size", TemaVR.TXT_DESC)
	vazio.add_theme_color_override("font_color", TemaVR.DIM)
	return vazio
