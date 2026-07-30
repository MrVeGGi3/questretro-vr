class_name PagSala
extends PagBase
## Onde você joga: o ambiente em volta da tela.
##
## Só um controle, e é de propósito — a sala é uma escolha, não um ajuste. O
## que cada modo faz vive em `scripts/vr/sala.gd`; aqui só se escolhe.

var _cfg: ConfigEmu


func _init(cfg: ConfigEmu) -> void:
	super("MENU_SALA")
	_cfg = cfg

	conteudo.add_child(WidgetsVR.campo("SALA_AMBIENTE", "SALA_AMBIENTE_DESC",
			WidgetsVR.segmentado(cfg, "sala/modo", Sala.NOMES)))

	# Uma linha por modo, porque "Passthrough" e "Vazio" não dizem sozinhos o
	# que fazem — e no headset não há como espiar antes de escolher.
	conteudo.add_child(WidgetsVR.divisoria())
	for i in Sala.NOMES.size():
		conteudo.add_child(WidgetsVR.campo(Sala.NOMES[i], "",
				WidgetsVR.mono(_explicacao(i))))

	rodape_de_ajuste(cfg, "sala")
	_atualizar_cabecalho()
	cfg.mudou.connect(func(k: String, _v: Variant) -> void:
		if k == "sala/modo":
			_atualizar_cabecalho()
	)


func _explicacao(modo: int) -> String:
	match modo:
		Sala.FLIPERAMA:
			return "SALA_FLIPERAMA_DESC"
		Sala.PASSTHROUGH:
			return "SALA_PASSTHROUGH_DESC"
		_:
			return "SALA_VAZIO_DESC"


func _atualizar_cabecalho() -> void:
	var modo := int(_cfg.obter("sala/modo"))
	caminho_lab.text = Sala.NOMES[modo] if modo < Sala.NOMES.size() else "?"
