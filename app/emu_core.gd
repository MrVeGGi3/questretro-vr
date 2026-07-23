class_name EmuCore
extends Node
## Envolve LibretroHost numa unidade reutilizável: carrega core+ROM, avança um
## frame, mantém uma ImageTexture atualizada e bombeia o áudio. Usado tanto pela
## cena desktop (Fase 0) quanto pela cena VR (Fase 1).

signal iniciado(width: int, height: int, fps: float)
signal falhou(msg: String)

## Bus próprio para o áudio do emulador: o volume do menu mexe aqui, e não no
## Master, para não silenciar junto sons de interface que venham depois.
const BUS_AUDIO := "Emu"
const PASTA_ESTADOS := "user://states"

var texture: ImageTexture         ## textura viva com o frame atual (RGBA8)
var largura: int = 0
var altura: int = 0
var rom_atual := ""               ## caminho da ROM em execução ("" = nenhuma)

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

	rom_atual = rom_path
	_configurar_audio(_host.get_sample_rate())
	_rodando = true
	iniciado.emit(_host.get_frame_width(), _host.get_frame_height(), _host.get_fps())
	return true


## Troca o jogo mantendo o core carregado — o dlopen custa caro e o core não
## muda enquanto for o mesmo sistema.
func trocar_rom(rom_path: String) -> bool:
	if _host == null or not _host.is_core_loaded():
		falhou.emit("Sem core carregado")
		return false

	_rodando = false
	if not _host.load_rom(rom_path):
		# load_rom já descarregou o jogo anterior, então não há para onde voltar.
		rom_atual = ""
		falhou.emit("Falha ao carregar a ROM: " + rom_path.get_file())
		return false

	rom_atual = rom_path
	# O novo jogo pode ter outra taxa de amostragem; recria a cadeia de áudio.
	_configurar_audio(_host.get_sample_rate())
	_rodando = true
	iniciado.emit(_host.get_frame_width(), _host.get_frame_height(), _host.get_fps())
	return true


func get_sample_rate() -> float:
	return _host.get_sample_rate() if _host != null else 32040.0


# ---------------------------------------------------------------------------
# Save states
# ---------------------------------------------------------------------------
func suporta_estado() -> bool:
	return _host != null and _host.supports_state()


func caminho_estado(slot: int) -> String:
	return "%s/%s_%d.state" % [PASTA_ESTADOS, _base_rom(), slot]


func caminho_miniatura(slot: int) -> String:
	return "%s/%s_%d.png" % [PASTA_ESTADOS, _base_rom(), slot]


func gravar_estado(slot: int) -> bool:
	if not _rodando or not suporta_estado():
		return false
	var dados := _host.save_state()
	if dados.is_empty():
		falhou.emit("Não consegui gravar o estado")
		return false

	DirAccess.make_dir_recursive_absolute(PASTA_ESTADOS)
	var f := FileAccess.open(caminho_estado(slot), FileAccess.WRITE)
	if f == null:
		falhou.emit("Não consegui escrever em " + PASTA_ESTADOS)
		return false
	f.store_buffer(dados)
	f.close()

	# Miniatura: o frame que está na tela agora é exatamente o que o jogador
	# vai reconhecer ao voltar. Falhar aqui não invalida o save.
	var img := _host.get_frame()
	if img != null:
		img.save_png(caminho_miniatura(slot))
	return true


func carregar_estado(slot: int) -> bool:
	if not _rodando or not suporta_estado():
		return false
	var f := FileAccess.open(caminho_estado(slot), FileAccess.READ)
	if f == null:
		falhou.emit("Slot %d vazio" % slot)
		return false
	var dados := f.get_buffer(f.get_length())
	f.close()
	if not _host.load_state(dados):
		falhou.emit("Estado do slot %d não serve para esta ROM" % slot)
		return false
	return true


## Nome de arquivo seguro derivado da ROM, para os slots de um jogo não
## colidirem com os de outro.
func _base_rom() -> String:
	if rom_atual.is_empty():
		return "sem_rom"
	return rom_atual.get_file().get_basename().validate_filename()


# ---------------------------------------------------------------------------
# Áudio
# ---------------------------------------------------------------------------
## Aplica volume (0..1) e mudo ao bus do emulador.
func aplicar_audio(volume: float, mudo: bool) -> void:
	var idx := AudioServer.get_bus_index(BUS_AUDIO)
	if idx < 0:
		return
	AudioServer.set_bus_mute(idx, mudo)
	# linear_to_db(0) é -inf, que o AudioServer aceita, mas mudo é mais claro.
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(volume, 0.0001)))


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


## Solta todos os botões. Usado ao abrir o menu, para o jogo não ficar com uma
## direção presa enquanto o gatilho vira clique de interface.
func limpar_input() -> void:
	if _host != null:
		_host.clear_input()


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
	# Trocar de ROM pode mudar a taxa; o player antigo não serve mais.
	if _audio_player != null:
		_audio_player.queue_free()
		_audio_player = null
		_audio_pb = null

	var gen := AudioStreamGenerator.new()
	gen.mix_rate = sample_rate
	gen.buffer_length = 0.1
	_audio_player = AudioStreamPlayer.new()
	_audio_player.stream = gen
	_audio_player.bus = _garantir_bus()
	add_child(_audio_player)
	_audio_player.play()
	_audio_pb = _audio_player.get_stream_playback()


## Cria o bus "Emu" na primeira vez. Devolve o nome usável — se a criação
## falhar por algum motivo, cair no Master é melhor que ficar mudo.
func _garantir_bus() -> String:
	if AudioServer.get_bus_index(BUS_AUDIO) >= 0:
		return BUS_AUDIO
	var idx := AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, BUS_AUDIO)
	AudioServer.set_bus_send(idx, &"Master")
	return BUS_AUDIO if AudioServer.get_bus_index(BUS_AUDIO) >= 0 else "Master"


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
