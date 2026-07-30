class_name PagAudio
extends PagBase
## Volume e mudo do emulador. Atua no bus "Emu", não no Master, para não
## silenciar junto sons de interface que venham depois.

var _emu: EmuCore


func _init(cfg: ConfigEmu, emu: EmuCore) -> void:
	super("MENU_AUDIO")
	_emu = emu

	conteudo.add_child(WidgetsVR.campo("AUDIO_VOLUME", "",
			WidgetsVR.slider(cfg, "audio/volume", 0.0, 1.0, 0.01,
					func(v: float) -> String: return "%d %%" % roundi(v * 100.0))))
	conteudo.add_child(WidgetsVR.campo("AUDIO_MUDO", "",
			WidgetsVR.interruptor(cfg, "audio/mudo")))

	rodape_de_ajuste(cfg, "audio")
	_atualizar_cabecalho()
	emu.iniciado.connect(func(_w: int, _h: int, _fps: float) -> void: _atualizar_cabecalho())


func _atualizar_cabecalho() -> void:
	caminho_lab.text = tr("AUDIO_MEDIDAS") % [roundi(_emu.get_sample_rate()), EmuCore.BUS_AUDIO]
