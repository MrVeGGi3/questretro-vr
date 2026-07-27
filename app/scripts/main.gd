extends Control
## Fase 0 — teste desktop do pipeline libretro (sem VR).
## Carrega um core + ROM, roda frame a frame, exibe o vídeo numa textura e
## toca o áudio. Input pelo teclado. Prova que a GDExtension funciona antes
## de levar pro headset na Fase 1.
##
## Rodar:  godot --path app -- --core res://cores/snes9x_libretro.so --rom /caminho/jogo.sfc
## Ou edite CORE_PADRAO / ROM_PADRAO abaixo e dê play no editor.

const CORE_PADRAO := "res://cores/snes9x_libretro.so"
const ROM_PADRAO := ""  # deixe vazio para exigir --rom na linha de comando

# Mapa teclado -> botão SNES (RETRO_DEVICE_ID_JOYPAD_*)
const MAPA_TECLADO := {
	KEY_X: LibretroHost.JOYPAD_A,
	KEY_Z: LibretroHost.JOYPAD_B,
	KEY_S: LibretroHost.JOYPAD_X,
	KEY_A: LibretroHost.JOYPAD_Y,
	KEY_Q: LibretroHost.JOYPAD_L,
	KEY_W: LibretroHost.JOYPAD_R,
	KEY_ENTER: LibretroHost.JOYPAD_START,
	KEY_SHIFT: LibretroHost.JOYPAD_SELECT,
	KEY_UP: LibretroHost.JOYPAD_UP,
	KEY_DOWN: LibretroHost.JOYPAD_DOWN,
	KEY_LEFT: LibretroHost.JOYPAD_LEFT,
	KEY_RIGHT: LibretroHost.JOYPAD_RIGHT,
}

var _host: LibretroHost
var _tela: TextureRect
var _tex: ImageTexture
var _audio_player: AudioStreamPlayer
var _audio_pb: AudioStreamGeneratorPlayback
var _status: Label


func _ready() -> void:
	_montar_ui()

	_host = LibretroHost.new()

	var core_path := _arg("--core", CORE_PADRAO)
	var rom_path := _arg("--rom", ROM_PADRAO)

	if not _host.load_core(core_path):
		_falhar("Falhou ao carregar o core: " + core_path)
		return
	if rom_path.is_empty():
		_falhar("Nenhuma ROM informada. Use -- --rom /caminho/jogo.sfc")
		return
	if not _host.load_rom(rom_path):
		_falhar("Falhou ao carregar a ROM: " + rom_path)
		return

	_configurar_audio(_host.get_sample_rate())
	_status.text = "Rodando: %s\n%d x %d @ %.1ffps" % [
		rom_path.get_file(), _host.get_frame_width(), _host.get_frame_height(), _host.get_fps()]


func _process(_delta: float) -> void:
	if _host == null or not _host.is_game_loaded():
		return

	_ler_input()
	_host.run_frame()
	_atualizar_video()
	_bombear_audio()


func _ler_input() -> void:
	for tecla in MAPA_TECLADO:
		_host.set_button(0, MAPA_TECLADO[tecla], Input.is_key_pressed(tecla))


func _atualizar_video() -> void:
	var img := _host.get_frame()
	if img == null:
		return
	if _tex == null or _tex.get_width() != img.get_width() or _tex.get_height() != img.get_height():
		_tex = ImageTexture.create_from_image(img)
		_tela.texture = _tex
	else:
		_tex.update(img)


func _bombear_audio() -> void:
	if _audio_pb == null:
		return
	var quadros := _host.get_audio()  # PackedVector2Array (L,R) em [-1,1]
	if quadros.size() == 0:
		return
	var espaco := _audio_pb.get_frames_available()
	if quadros.size() > espaco:
		quadros = quadros.slice(0, espaco)
	if quadros.size() > 0:
		_audio_pb.push_buffer(quadros)


func _configurar_audio(sample_rate: float) -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = sample_rate
	gen.buffer_length = 0.1
	_audio_player = AudioStreamPlayer.new()
	_audio_player.stream = gen
	add_child(_audio_player)
	_audio_player.play()
	_audio_pb = _audio_player.get_stream_playback()


func _montar_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_tela = TextureRect.new()
	_tela.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tela.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_tela.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_tela.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_tela)

	_status = Label.new()
	_status.position = Vector2(8, 8)
	_status.add_theme_color_override("font_color", Color.WHITE)
	_status.add_theme_color_override("font_outline_color", Color.BLACK)
	_status.add_theme_constant_override("outline_size", 4)
	add_child(_status)


func _arg(nome: String, padrao: String) -> String:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size() - 1):
		if args[i] == nome:
			return args[i + 1]
	return padrao


func _falhar(msg: String) -> void:
	push_error(msg)
	_status.text = msg
	set_process(false)


func _exit_tree() -> void:
	if _host != null:
		_host.unload()
