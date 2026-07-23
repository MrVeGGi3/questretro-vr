extends SceneTree
## Roda N frames e salva um PNG do framebuffer — prova visual do pipeline.
func _initialize() -> void:
	var host: LibretroHost = LibretroHost.new()
	host.load_core("res://cores/snes9x_libretro.so")
	var rom := ""
	var a := OS.get_cmdline_user_args()
	for i in range(a.size() - 1):
		if a[i] == "--rom": rom = a[i + 1]
	if not host.load_rom(rom):
		quit(1); return
	for f in range(150):
		host.run_frame()
		host.get_audio()  # drena o áudio pra não estourar buffer
	var img := host.get_frame()
	if img != null:
		img.save_png("user://shot.png")
		print("SALVO ", img.get_width(), "x", img.get_height())
	host.unload()
	quit(0)
