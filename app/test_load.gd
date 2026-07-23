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
		else:
			printerr("FALHA: load_rom('%s')" % rom)

	host.unload()
	print("=== fim (Fase 0 verificada) ===")
	quit(0)
