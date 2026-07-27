extends SceneTree
## Teste headless da Fase 0: prova que a GDExtension registra a classe,
## que o dlopen do core funciona e que retro_init roda.
## Rodar: godot --headless --path app -s res://scripts/testes/test_load.gd

func _initialize() -> void:
	print("=== teste libretrogd ===")

	if not ClassDB.class_exists("LibretroHost"):
		printerr("FALHA: classe LibretroHost não registrada (GDExtension não carregou)")
		quit(1)
		return
	print("OK  classe LibretroHost registrada pela GDExtension")

	var host: LibretroHost = LibretroHost.new()
	var core := _arg("--core", "res://cores/snes9x_libretro.so")
	if not host.load_core(core):
		printerr("FALHA: load_core('%s')" % core)
		quit(2)
		return
	print("OK  core carregado (dlopen + símbolos + retro_init)")
	print("    is_core_loaded=", host.is_core_loaded())
	_testar_opcoes(host)

	# ROM opcional: se passada, testa o pipeline completo de um frame.
	var rom := _arg("--rom", "")
	if not rom.is_empty():
		if host.load_rom(rom):
			print("OK  ROM carregada: %dx%d @ %.1ffps sr=%.0f" % [
				host.get_frame_width(), host.get_frame_height(),
				host.get_fps(), host.get_sample_rate()])
			for f in range(3):
				host.run_frame()
			var img := host.get_frame()
			if img != null:
				print("OK  frame renderizado: %dx%d" % [img.get_width(), img.get_height()])
			var audio := host.get_audio()
			print("OK  amostras de áudio no frame: ", audio.size())
			_mostrar_descritores(host)
			_testar_sram(host)
		else:
			printerr("FALHA: load_rom('%s')" % rom)

	host.unload()
	print("=== fim (Fase 0 verificada) ===")
	quit(0)


func _arg(nome: String, padrao: String) -> String:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size() - 1):
		if args[i] == nome:
			return args[i + 1]
	return padrao


## Mapa de controle declarado pelo core. É a fonte da verdade para montar o
## mapa do Touch: o mesmo JOYPAD_L2 é "Z" no N64 e não existe no SNES.
func _mostrar_descritores(host: LibretroHost) -> void:
	var descs := host.get_input_descriptors()
	print("OK  descritores de input: %d" % descs.size())
	for d: Dictionary in descs:
		if d["port"] != 0:
			continue
		print("    porta 0  device=%d index=%d id=%2d  %s" % [
			d["device"], d["index"], d["id"], d["desc"]])


## Opções do core: o core as declara dentro de retro_set_environment, então já
## têm que estar aqui, antes de qualquer ROM. Sem isto o mupen64plus fica preso
## nos defaults dele — é por opção que se escolhe plugin de vídeo e resolução.
func _testar_opcoes(host: LibretroHost) -> void:
	var opcoes := host.get_options()
	print("OK  opções declaradas pelo core: %d" % opcoes.size())
	if opcoes.is_empty():
		return
	for op: Dictionary in opcoes.slice(0, 3):
		print("    %s = %s  (padrão %s, %d valores) — %s" % [
			op["key"], op["value"], op["default"], (op["values"] as PackedStringArray).size(),
			op["desc"]])

	# Round-trip: escolher um valor diferente do vigente tem que pegar.
	var primeira: Dictionary = opcoes[0]
	var vals: PackedStringArray = primeira["values"]
	if vals.size() < 2:
		return
	var outro: String = vals[1] if vals[0] == primeira["value"] else vals[0]
	host.set_option(primeira["key"], outro)
	if host.get_option(primeira["key"]) == outro:
		print("OK  set_option pegou (%s = %s)" % [primeira["key"], outro])
	else:
		printerr("FALHA: set_option não mudou %s" % primeira["key"])

	# E um valor fora da lista tem que ser recusado, não repassado ao core.
	host.set_option(primeira["key"], "valor_que_nao_existe")
	if host.get_option(primeira["key"]) == outro:
		print("OK  set_option recusou valor inválido (o aviso acima é esperado)")
	else:
		printerr("FALHA: set_option aceitou valor fora da lista")

	# Devolve o valor original: a primeira opção do mupen é o renderizador, e
	# deixá-la trocada faria o resto do teste medir outro caminho de vídeo.
	host.set_option(primeira["key"], primeira["value"])


## Round-trip da SRAM: ler, alterar, escrever de volta e reler. Prova que o
## ponteiro do core é gravável e que set_memory recusa tamanho errado — as duas
## coisas que, se falharem em silêncio, viram progresso perdido no headset.
func _testar_sram(host: LibretroHost) -> void:
	var tam := host.get_memory_size(LibretroHost.MEMORY_SAVE_RAM)
	print("OK  SRAM: %d bytes" % tam)
	if tam <= 0:
		print("    (esta ROM não tem bateria — round-trip pulado)")
		return

	var original := host.get_memory(LibretroHost.MEMORY_SAVE_RAM)
	if original.size() != tam:
		printerr("FALHA: get_memory devolveu %d bytes, esperava %d" % [original.size(), tam])
		return

	var alterado := original.duplicate()
	for i in mini(8, tam):
		alterado[i] = (original[i] + 1) % 256
	if not host.set_memory(LibretroHost.MEMORY_SAVE_RAM, alterado):
		printerr("FALHA: set_memory recusou dados do tamanho certo")
		return
	if host.get_memory(LibretroHost.MEMORY_SAVE_RAM) != alterado:
		printerr("FALHA: SRAM relida difere do que foi escrito")
		return
	print("OK  round-trip da SRAM (escreveu e releu igual)")

	# Devolve o conteúdo original: o teste não pode sujar o save de ninguém.
	host.set_memory(LibretroHost.MEMORY_SAVE_RAM, original)

	if host.set_memory(LibretroHost.MEMORY_SAVE_RAM, original.slice(0, tam - 1)):
		printerr("FALHA: set_memory aceitou um buffer de tamanho errado")
	else:
		print("OK  set_memory recusou tamanho errado (o aviso acima é esperado)")
