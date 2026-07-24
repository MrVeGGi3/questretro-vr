extends SceneTree
## Teste headless da Fase 0: prova que a GDExtension registra a classe,
## que o dlopen do core funciona e que retro_init roda.
## Rodar: godot --headless --path app -s res://test_load.gd

func _initialize() -> void:
	print("=== teste libretrogd ===")

	if not ClassDB.class_exists("LibretroHost"):
		printerr("FALHA: classe LibretroHost não registrada (GDExtension não carregou)")
		quit(1)
		return
	print("OK  classe LibretroHost registrada pela GDExtension")

	var host: LibretroHost = LibretroHost.new()
	var core := "res://cores/snes9x_libretro.so"
	if not host.load_core(core):
		printerr("FALHA: load_core('%s')" % core)
		quit(2)
		return
	print("OK  core carregado (dlopen + símbolos + retro_init)")
	print("    is_core_loaded=", host.is_core_loaded())

	# ROM opcional: se passada, testa o pipeline completo de um frame.
	var rom := ""
	for i in range(OS.get_cmdline_user_args().size() - 1):
		if OS.get_cmdline_user_args()[i] == "--rom":
			rom = OS.get_cmdline_user_args()[i + 1]
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
			_testar_sram(host)
		else:
			printerr("FALHA: load_rom('%s')" % rom)

	host.unload()
	print("=== fim (Fase 0 verificada) ===")
	quit(0)


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
