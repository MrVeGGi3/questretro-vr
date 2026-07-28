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
## Mesma pasta que o LibretroHost entrega ao core via GET_SAVE_DIRECTORY.
const PASTA_SAVES := "user://saves"

## Intervalo entre checagens da SRAM. O jogo escreve na bateria sem avisar
## ninguém, então a única forma de saber é comparar de tempos em tempos — este
## número é o teto do progresso que se perde num crash.
##
## Um segundo, e não cinco, porque no Quest o app **morre** ao ser pausado (o
## Godot segfalta em `onActivityPaused`, ver docs/EXPORT.md) e tirar o headset é
## como quase toda sessão termina. Checar mais vezes é quase de graça: quando
## nada mudou a função sai na comparação de buffer, sem tocar no disco. Medido em
## `test_sram`: com 5 s a gravação saía 4,9 s depois de salvar.
const INTERVALO_SRAM := 1.0

## Core por sistema e plataforma: `android` é o binário aarch64 do Quest,
## `desktop` o x86_64. Os nomes não seguem um padrão comum — o mupen do
## buildbot vem separado por versão de GL no Android e sem sufixo no desktop —,
## então cada um é escrito por extenso. Ver `core_para_rom()`.
const CORES := {
	"snes": {
		"desktop": "res://cores/snes9x_libretro.so",
		"android": "res://cores/snes9x_libretro_android.so",
	},
	"n64": {
		"desktop": "res://cores/mupen64plus_next_libretro.so",
		"android": "res://cores/mupen64plus_next_gles3_libretro_android.so",
	},
}

## Opções aplicadas ao core assim que ele carrega e antes da ROM — várias só
## valem no load_rom. Só o que difere do padrão do core.
##
## O `gliden64` desenha pela GPU, no FBO que o LibretroHost empresta ao core.
## O `angrylion` é o renderizador por software e serve de rede de segurança —
## dá imagem sem GL nenhum, mas foi medido em 65 fps num x86_64 de desktop, o
## que no ARM do Quest não fecharia os 60.
## O renderizador do N64 **difere por plataforma**, e não por gosto:
##
## - No desktop, `gliden64` desenha pela GPU no FBO que emprestamos ao core.
## - No Quest, esse mesmo caminho derruba o app: SIGSEGV no primeiro frame,
##   dentro do `libGLESv2_adreno.so`, chamado pelo core. Nossa parte já passou
##   quando isso acontece — o FBO sobe e o `context_reset()` do core retorna
##   limpo —, então o problema mora no GLideN64 sobre o driver da Adreno.
##   `angrylion` é software puro, não toca em GL, e roda fluido no headset.
##
## Trocar o Android para gliden64 é o objetivo; enquanto não for, isto é o que
## faz o N64 funcionar no Quest hoje.
const OPCOES := {
	"n64": {
		# Resolução interna. 640x480 é o dobro da nativa e é o que sobra
		# legível numa tela grande dentro do headset.
		"mupen64plus-43screensize": "640x480",
		# O GLideN64 guarda shaders compilados em disco e os recarrega.
		# Recompilar toda vez custa um arranque mais lento e nada mais, e tira
		# uma variável do caminho enquanto o crash acima não estiver resolvido.
		"mupen64plus-EnableShadersStorage": "False",
		# Cópia assíncrona do framebuffer usa PBO; síncrona é mais lenta e
		# muito menos exigente com o driver.
		"mupen64plus-EnableCopyColorToRDRAM": "Sync",
	},
}

## Renderizador do N64, que depende da plataforma e por isso não cabe numa
## `const` — ela exige expressão constante.
static func rdp_do_n64() -> String:
	return "angrylion" if OS.has_feature("android") else "gliden64"


## Sobrescreve `OPCOES` sem rebuild: um ConfigFile com uma seção por sistema.
## Existe para o ciclo de teste no headset, onde cada rebuild custa dez minutos
## e escrever este arquivo custa segundos. No Android o `user://` é a pasta
## **interna** do app, alcançável só por `run-as` (e só em build de debug):
##
##     adb shell "run-as com.questretro.vr sh -c \
##         'printf \"[n64]\nmupen64plus-rdp-plugin=\\\"gliden64\\\"\n\" \
##          > files/opcoes_core.cfg'"
##
## Foi assim que se descobriu, em segundos, que o crash do N64 no Quest é do
## GLideN64 e não do nosso empréstimo de contexto.
const ARQUIVO_OPCOES := "user://opcoes_core.cfg"

## Chave reservada dentro da seção do sistema: escolhe o `.so` do core em vez de
## uma opção dele. Ver `_core_do_arquivo`.
const CHAVE_CORE := "core"

var texture: ImageTexture         ## textura viva com o frame atual (RGBA8)
var largura: int = 0
var altura: int = 0
var rom_atual := ""               ## caminho da ROM em execução ("" = nenhuma)
var sistema := ""                 ## sistema da ROM em execução ("snes", "n64", …)

## Contadores de diagnóstico do áudio. Descarte contínuo > 0 significa que a
## emulação está adiantada em relação ao consumo do AudioStreamGenerator.
var diag_audio_gerado := 0
var diag_audio_descartado := 0

var _host: LibretroHost
var _audio_player: AudioStreamPlayer
var _audio_pb: AudioStreamGeneratorPlayback
var _rodando := false

var _sram_disco := PackedByteArray()   ## o que já está gravado, para comparar
var _desde_sram := 0.0


## Core que roda uma ROM, pela extensão dela. "" se não reconhecemos o arquivo
## ou se ainda não temos core para o sistema.
static func core_para_rom(rom_path: String) -> String:
	var sis := NavegadorRoms.sistema_de(rom_path)
	if not CORES.has(sis):
		return ""
	var escolhido := _core_do_arquivo(sis)
	if not escolhido.is_empty():
		return escolhido
	return CORES[sis]["android" if OS.has_feature("android") else "desktop"]


## Troca o `.so` do core sem rebuild, pelo mesmo arquivo que já sobrescreve as
## opções: `core = "nome_do_arquivo.so"` na seção do sistema.
##
## Existe pelo mesmo motivo que a sobrescrita de opções: no headset cada
## export+install custa dez minutos, e descobrir se o crash do GLideN64 muda
## entre as variantes `gles2` e `gles3` do mupen não vale esse preço por
## tentativa. As duas variantes já vão no APK — o `include_filter` do preset
## leva `cores/*_android.so` inteiro.
static func _core_do_arquivo(sistema_novo: String) -> String:
	var cfg := ConfigFile.new()
	if cfg.load(ARQUIVO_OPCOES) != OK:
		return ""
	var nome := str(cfg.get_value(sistema_novo, CHAVE_CORE, ""))
	if nome.is_empty():
		return ""
	var caminho := "res://cores/" + nome
	if not FileAccess.file_exists(caminho):
		# Nome errado não pode virar "sem core": cair no padrão dá um teste que
		# mede a variante errada em silêncio, que é pior que não rodar.
		push_warning("EmuCore: core pedido pelo arquivo não existe: " + caminho)
		return ""
	print("EmuCore: core de %s vindo do arquivo: %s" % [sistema_novo, nome])
	return caminho


## `core_path` vazio faz o core sair da extensão da ROM — é o caminho normal.
## Passar um explícito serve para os testes e para o `--core` da linha de comando.
func iniciar(core_path: String, rom_path: String) -> bool:
	if rom_path.is_empty():
		falhou.emit("Nenhuma ROM informada")
		return false
	if core_path.is_empty():
		core_path = core_para_rom(rom_path)
		if core_path.is_empty():
			falhou.emit("Sem core para " + rom_path.get_file())
			return false

	_host = LibretroHost.new()
	if not _carregar_core(core_path, NavegadorRoms.sistema_de(rom_path)):
		return false
	if not _host.load_rom(rom_path):
		falhou.emit("Falha ao carregar a ROM: " + rom_path)
		return false

	_apos_carregar_rom(rom_path)
	return true


## Sistemas cujo core não aceita carregar uma segunda ROM sem ser reiniciado.
##
## O mupen64plus é um deles: o segundo `retro_load_game` responde "failed to
## load ROM" e o jogo não abre. Não depende de ser a mesma ROM — em
## `test_troca_rom.tscn`, o que falha é sempre a primeira troca N64→N64, seja
## para o mesmo cartucho ou para outro. E não é só do headset: reproduz igual no
## desktop.
##
## Para estes, `trocar_rom` refaz o dlopen mesmo quando o sistema não muda.
## Custa alguns décimos de segundo e evita um erro que, da interface, parece ROM
## corrompida.
const RECARREGA_SEMPRE := ["n64"]


## Troca o jogo. Mantém o core carregado quando dá — o dlopen custa caro —, mas
## troca de core quando a ROM é de outro sistema (ou quando o core não suporta
## uma segunda carga; ver RECARREGA_SEMPRE).
func trocar_rom(rom_path: String) -> bool:
	if _host == null:
		falhou.emit("Sem core carregado")
		return false

	var core_novo := core_para_rom(rom_path)
	if core_novo.is_empty():
		falhou.emit("Sem core para " + rom_path.get_file())
		return false

	# Antes de qualquer descarga: depois dela o buffer da SRAM já morreu e
	# rom_atual apontaria para o arquivo errado.
	gravar_sram()
	_rodando = false

	var sistema_novo := NavegadorRoms.sistema_de(rom_path)
	if sistema_novo != sistema or not _host.is_core_loaded() \
			or sistema_novo in RECARREGA_SEMPRE:
		# Outro sistema (ou core que não recarrega): o core atual não abre esta
		# ROM. unload() derruba jogo e core de uma vez, e a SRAM já foi gravada
		# acima. Recarregar também é o que faz as opções valerem de novo, já que
		# elas são aplicadas junto do load_core.
		_host.unload()
		rom_atual = ""
		sistema = ""
		if not _carregar_core(core_novo, sistema_novo):
			return false

	if not _host.load_rom(rom_path):
		# load_rom já descarregou o jogo anterior, então não há para onde voltar.
		rom_atual = ""
		sistema = ""
		falhou.emit("Falha ao carregar a ROM: " + rom_path.get_file())
		return false

	_apos_carregar_rom(rom_path)
	return true


func _carregar_core(core_path: String, sistema_novo: String) -> bool:
	# No Android o core vive dentro do APK (res:// virtual) e o dlopen não
	# consegue abri-lo; então preparamos uma cópia num caminho real (user://).
	var core_real := _preparar_core(core_path)
	if not _host.load_core(core_real):
		falhou.emit("Falha ao carregar o core: " + core_real.get_file())
		return false
	# Aqui, e não depois do load_rom: o core lê boa parte das opções ao abrir a
	# ROM, e as que ele já leu não voltam atrás.
	for chave: String in OPCOES.get(sistema_novo, {}):
		_host.set_option(chave, OPCOES[sistema_novo][chave])
	if sistema_novo == "n64":
		_host.set_option("mupen64plus-rdp-plugin", rdp_do_n64())
	_aplicar_opcoes_do_arquivo(sistema_novo)
	return true


## Sobrescritas de `user://opcoes_core.cfg`, se houver. Imprime o que aplicou:
## num log de headset, saber com que opções aquele teste rodou é a diferença
## entre bisseccionar e adivinhar.
func _aplicar_opcoes_do_arquivo(sistema_novo: String) -> void:
	var cfg := ConfigFile.new()
	if cfg.load(ARQUIVO_OPCOES) != OK:
		return
	if not cfg.has_section(sistema_novo):
		return
	for chave in cfg.get_section_keys(sistema_novo):
		if chave == CHAVE_CORE:
			continue   # escolhe o .so, não é opção do core (ver _core_do_arquivo)
		var valor := str(cfg.get_value(sistema_novo, chave))
		print("EmuCore: opção de %s vinda do arquivo: %s = %s" % [sistema_novo, chave, valor])
		_host.set_option(chave, valor)


## O que vale para toda ROM recém-carregada, seja no arranque ou na troca.
func _apos_carregar_rom(rom_path: String) -> void:
	rom_atual = rom_path
	sistema = NavegadorRoms.sistema_de(rom_path)
	# Só depois do load_rom: antes disso o core ainda não tem porta para
	# configurar. O N64 não consulta os eixos sem isto.
	if sistema == "n64":
		_host.set_controller_device(0, LibretroHost.DEVICE_ANALOG)
	_carregar_sram()
	# O novo jogo pode ter outra taxa de amostragem; recria a cadeia de áudio.
	_configurar_audio(_host.get_sample_rate())
	_rodando = true
	iniciado.emit(_host.get_frame_width(), _host.get_frame_height(), _host.get_fps())


func get_sample_rate() -> float:
	return _host.get_sample_rate() if _host != null else 32040.0


# ---------------------------------------------------------------------------
# Save states
# ---------------------------------------------------------------------------
func suporta_estado() -> bool:
	return _host != null and _host.supports_state()


func caminho_estado(slot: int) -> String:
	return "%s/%s_%d.state" % [PASTA_ESTADOS, id_rom(), slot]


func caminho_miniatura(slot: int) -> String:
	return "%s/%s_%d.png" % [PASTA_ESTADOS, id_rom(), slot]


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


## Apaga um slot: o estado e a miniatura junto. É a única saída de um slot
## ocupado — gravar por cima exige ter o jogo naquele ponto de novo, e sem isto
## um save ruim fica lá para sempre.
func apagar_estado(slot: int) -> bool:
	var caminho := caminho_estado(slot)
	if not FileAccess.file_exists(caminho):
		return false
	if DirAccess.remove_absolute(caminho) != OK:
		falhou.emit("Não consegui apagar o slot %d" % slot)
		return false

	# A miniatura sozinha não é save nenhum, mas se ficar para trás o slot vazio
	# mostra a imagem de um estado que não existe mais.
	var png := caminho_miniatura(slot)
	if FileAccess.file_exists(png):
		DirAccess.remove_absolute(png)
	return true


## Nome de arquivo seguro derivado da ROM, para os arquivos de um jogo não
## colidirem com os de outro. É o id do cartucho em todo o resto do app: nomeia
## os slots de estado, o `.srm` e o perfil de controle, então os arquivos de um
## jogo ficam todos com o mesmo nome na pasta.
func id_rom() -> String:
	if rom_atual.is_empty():
		return "sem_rom"
	return rom_atual.get_file().get_basename().validate_filename()


# ---------------------------------------------------------------------------
# SRAM (save de bateria)
# ---------------------------------------------------------------------------
## Diferente do save state: é o que o jogo grava sozinho quando você salva
## *dentro* dele. O core mantém a SRAM só em memória — persistir é trabalho
## nosso, e quem não faz perde o progresso ao fechar o app sem sintoma nenhum.
##
## `.srm` é a convenção do RetroArch e o conteúdo é o buffer cru, então os
## arquivos são intercambiáveis com uma instalação existente.
func caminho_sram() -> String:
	return "%s/%s.srm" % [PASTA_SAVES, id_rom()]


## Bytes de bateria deste jogo; 0 quando o cartucho não tem.
func tamanho_sram() -> int:
	return _host.get_memory_size(LibretroHost.MEMORY_SAVE_RAM) if _host != null else 0


## Grava a SRAM se ela mudou desde a última vez. Barato de chamar em intervalo
## curto: no caso comum sai na comparação, sem tocar o disco.
func gravar_sram() -> bool:
	if _host == null or not _host.is_game_loaded():
		return false
	var dados := _host.get_memory(LibretroHost.MEMORY_SAVE_RAM)
	if dados.is_empty() or dados == _sram_disco:
		return false

	DirAccess.make_dir_recursive_absolute(PASTA_SAVES)
	# Escreve num temporário e renomeia por cima: se o app morrer no meio da
	# escrita (o normal no Quest), o save anterior continua inteiro.
	var tmp := caminho_sram() + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("EmuCore: não consegui escrever em " + tmp)
		return false
	f.store_buffer(dados)
	f.close()

	var err := DirAccess.rename_absolute(tmp, caminho_sram())
	if err != OK:
		push_error("EmuCore: falha ao renomear %s (erro %d)" % [tmp, err])
		return false

	_sram_disco = dados
	return true


func _carregar_sram() -> void:
	_sram_disco = PackedByteArray()
	_desde_sram = 0.0
	if tamanho_sram() <= 0:
		return  # cartucho sem bateria

	var f := FileAccess.open(caminho_sram(), FileAccess.READ)
	if f == null:
		return  # primeira vez neste jogo
	var dados := f.get_buffer(f.get_length())
	f.close()

	# Se o tamanho não bater, set_memory recusa e avisa; deixando _sram_disco
	# vazio, a próxima gravação substitui o arquivo inservível pelo bom.
	if _host.set_memory(LibretroHost.MEMORY_SAVE_RAM, dados):
		_sram_disco = dados


func _process(delta: float) -> void:
	if not _rodando:
		return
	_desde_sram += delta
	if _desde_sram >= INTERVALO_SRAM:
		_desde_sram = 0.0
		gravar_sram()


func _notification(what: int) -> void:
	# APPLICATION_PAUSED é o caso do Quest: tirar o headset suspende o app e o
	# Android pode matá-lo sem mais aviso. É a última chance de gravar — e é
	# assim que a maioria das sessões termina no headset, não pelo botão de sair.
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		# Impresso porque este gatilho é invisível de qualquer outra forma: ele só
		# dispara quando ninguém está olhando a tela, e o que ele faz (ou deixa de
		# fazer) só aparece na sessão seguinte, como progresso perdido. No logcat
		# a linha responde de uma vez se a notificação chegou e se havia o que
		# gravar.
		var quem := "pausa" if what == NOTIFICATION_APPLICATION_PAUSED else "fechamento"
		print("EmuCore: %s — SRAM %s" % [quem, "gravada" if gravar_sram() else "sem mudança"])


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


## Eixo analógico. `valor` em [-1,1] na convenção do libretro: X para a direita,
## **Y para baixo** — o inverso do Vector2 do thumbstick, então quem chama a
## partir de um XRController3D precisa inverter o Y.
func set_analog(port: int, indice: int, eixo: int, valor: float) -> void:
	if _host != null:
		_host.set_analog(port, indice, eixo, valor)


## Anuncia o tipo de controle da porta. O N64 precisa de DEVICE_ANALOG para o
## core sequer consultar os eixos; o SNES fica no DEVICE_JOYPAD padrão.
func set_controller_device(port: int, device: int) -> void:
	if _host != null:
		_host.set_controller_device(port, device)


## Solta todos os botões. Usado ao abrir o menu, para o jogo não ficar com uma
## direção presa enquanto o gatilho vira clique de interface.
func limpar_input() -> void:
	if _host != null:
		_host.clear_input()


func get_fps() -> float:
	return _host.get_fps() if _host != null else 60.0


## Mapa de controle declarado pelo core: para cada id do joypad libretro, o
## nome daquele botão no console. É o que a página de Input mostra, em vez de
## uma tabela nossa que envelheceria a cada core novo.
func descritores_input() -> Array:
	return _host.get_input_descriptors() if _host != null else []


## true quando o core desenha pela GPU. Muda o que a página de Vídeo pode
## oferecer: filtro e brilho seguem valendo, mas a resolução passa a ser opção
## do core, não do nosso lado.
func hw_render() -> bool:
	return _host != null and _host.is_hw_render()


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
	diag_audio_gerado += quadros.size()
	var espaco := _audio_pb.get_frames_available()
	if quadros.size() > espaco:
		diag_audio_descartado += quadros.size() - espaco
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
	# Antes do unload: ele descarrega o jogo e o buffer da SRAM vai junto.
	gravar_sram()
	if _host != null:
		_host.unload()
