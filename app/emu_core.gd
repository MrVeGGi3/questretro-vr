class_name EmuCore
extends Node
## Envolve LibretroHost numa unidade reutilizável: carrega core+ROM, avança um
## frame, mantém uma ImageTexture atualizada e bombeia o áudio. Usado tanto pela
## cena desktop (Fase 0) quanto pela cena VR (Fase 1).

signal iniciado(width: int, height: int, fps: float)
signal falhou(msg: String)

var texture: ImageTexture         ## textura viva com o frame atual (RGBA8)
var largura: int = 0
var altura: int = 0

var _host: LibretroHost
var _audio_player: AudioStreamPlayer
var _audio_pb: AudioStreamGeneratorPlayback
var _rodando := false


func iniciar(core_path: String, rom_path: String) -> bool:
	_host = LibretroHost.new()
	# No Android o core vive dentro do APK (res:// virtual) e o dlopen não
	# consegue abri-lo; então preparamos uma cópia num caminho real (user://).
	var core_real := _preparar_core(core_path)
	if not _host.load_core(core_real):
		falhou.emit("Falha ao carregar o core: " + core_real)
		return false
	if rom_path.is_empty():
		falhou.emit("Nenhuma ROM informada")
		return false
	if not _host.load_rom(rom_path):
		falhou.emit("Falha ao carregar a ROM: " + rom_path)
		return false

	_configurar_audio(_host.get_sample_rate())
	_rodando = true
	iniciado.emit(_host.get_frame_width(), _host.get_frame_height(), _host.get_fps())
	return true


## Avança exatamente um frame do emulador. Chame set_button() antes.
func step() -> void:
	if not _rodando:
		return
	_host.run_frame()
	_atualizar_video()
	_bombear_audio()


func set_button(port: int, id: int, pressed: bool) -> void:
	if _host != null:
		_host.set_button(port, id, pressed)


func get_fps() -> float:
	return _host.get_fps() if _host != null else 60.0


func _atualizar_video() -> void:
	var img := _host.get_frame()
	if img == null:
		return
	largura = img.get_width()
	altura = img.get_height()
	if texture == null or texture.get_width() != largura or texture.get_height() != altura:
		texture = ImageTexture.create_from_image(img)
	else:
		texture.update(img)


func _bombear_audio() -> void:
	if _audio_pb == null:
		return
	var quadros := _host.get_audio()
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


## Garante um caminho de filesystem real para o core. No desktop res:// já
## globaliza para um caminho real; no Android copiamos para user://.
func _preparar_core(core_path: String) -> String:
	if not core_path.begins_with("res://"):
		return core_path
	if not OS.has_feature("android"):
		# Desktop/editor: res:// aponta para o diretório do projeto, dlopen abre direto.
		return ProjectSettings.globalize_path(core_path)

	var destino := "user://cores/" + core_path.get_file()
	DirAccess.make_dir_recursive_absolute("user://cores")
	# Copia só se ainda não existe ou se o tamanho difere (core atualizado).
	var precisa_copiar := true
	if FileAccess.file_exists(destino):
		var a := FileAccess.open(core_path, FileAccess.READ)
		var b := FileAccess.open(destino, FileAccess.READ)
		if a != null and b != null and a.get_length() == b.get_length():
			precisa_copiar = false
	if precisa_copiar:
		var src := FileAccess.open(core_path, FileAccess.READ)
		if src == null:
			push_error("EmuCore: não abriu o core em " + core_path)
			return core_path
		var bytes := src.get_buffer(src.get_length())
		var dst := FileAccess.open(destino, FileAccess.WRITE)
		dst.store_buffer(bytes)
		dst.close()
	return ProjectSettings.globalize_path(destino)


func _exit_tree() -> void:
	if _host != null:
		_host.unload()
