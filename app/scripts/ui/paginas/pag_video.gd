class_name PagVideo
extends PagBase
## Como o framebuffer do core é apresentado: filtro, proporção, brilho.

var _emu: EmuCore


func _init(cfg: ConfigEmu, emu: EmuCore) -> void:
	super("Vídeo")
	_emu = emu

	conteudo.add_child(WidgetsVR.campo("Filtro", "como o pixel é ampliado",
			WidgetsVR.segmentado(cfg, "video/filtro_suave", ["Nítido", "Suave"])))
	conteudo.add_child(WidgetsVR.campo("Proporção", "",
			WidgetsVR.segmentado(cfg, "video/aspecto", ["4:3", "8:7", "16:9", "Nativa"])))
	# "Escala inteira" saiu do mockup: só faz sentido casando pixels do jogo
	# com pixels de um display 2D. Num quad em 3D, visto de qualquer ângulo e
	# distância, não existe grade para casar — o toggle não teria efeito.
	conteudo.add_child(WidgetsVR.campo("Brilho", "compensa o passthrough claro",
			WidgetsVR.slider(cfg, "video/brilho", 0.4, 2.0, 0.05,
					func(v: float) -> String: return "%.2f×" % v)))

	conteudo.add_child(WidgetsVR.campo("Diagnóstico", "fps e ritmo do emulador na tela",
			WidgetsVR.interruptor(cfg, "video/diag")))

	rodape_de_ajuste(cfg, "video")
	_atualizar_cabecalho()
	emu.iniciado.connect(func(_w: int, _h: int, _fps: float) -> void: _atualizar_cabecalho())


func _atualizar_cabecalho() -> void:
	if _emu.largura > 0:
		caminho_lab.text = "%d × %d · %.2f fps" % [_emu.largura, _emu.altura, _emu.get_fps()]
	else:
		caminho_lab.text = "sem jogo carregado"
