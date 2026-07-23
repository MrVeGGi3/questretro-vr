class_name PagInput
extends PagBase
## Mapa do controle Touch para o joypad libretro, mais o ajuste fino da
## conversão analógico → D-pad.
##
## O mapa é fixo por enquanto: mostra o que está valendo em vez de deixar
## remapear. Remap de verdade precisa de um modo "aperte um botão" que capture
## input do Touch enquanto o menu está aberto — e é justamente o menu que hoje
## congela o input do jogo. Fica para quando o painel souber distinguir os dois.

## Origem no controle → destino no SNES, na ordem em que a mão encontra.
## A cor é a do botão no Super Famicom, onde existe.
const MAPA := [
	["Analógico esquerdo", "D-PAD", null],
	["Botão A (direito)", "A", "a"],
	["Botão B (direito)", "B", "b"],
	["Botão X (esquerdo)", "X", "x"],
	["Botão Y (esquerdo)", "Y", "y"],
	["Gatilho esquerdo", "L", null],
	["Gatilho direito", "R", null],
	["Grip direito", "START", null],
	["Grip esquerdo", "SELECT", null],
]

const CORES := {
	"a": TemaVR.BTN_A, "b": TemaVR.BTN_B, "x": TemaVR.BTN_X, "y": TemaVR.BTN_Y,
}


func _init(cfg: ConfigEmu) -> void:
	super("Input")
	caminho_lab.text = "Meta Touch · porta 1"

	for entrada in MAPA:
		conteudo.add_child(_linha(entrada[0], entrada[1], entrada[2]))

	conteudo.add_child(WidgetsVR.divisoria(TemaVR.LINE))

	var titulo := Label.new()
	titulo.text = "Zona morta do D-pad"
	titulo.add_theme_color_override("font_color", TemaVR.DIM)
	conteudo.add_child(titulo)

	conteudo.add_child(WidgetsVR.campo("Engatar", "quanto empurrar para valer",
			WidgetsVR.slider(cfg, "input/dpad_engaja", 0.2, 0.9, 0.01,
					func(v: float) -> String: return "%.2f" % v)))
	conteudo.add_child(WidgetsVR.campo("Soltar", "histerese: evita tremular",
			WidgetsVR.slider(cfg, "input/dpad_solta", 0.1, 0.8, 0.01,
					func(v: float) -> String: return "%.2f" % v)))
	conteudo.add_child(WidgetsVR.campo("Setor cardeal", "acima de 45° gera diagonais",
			WidgetsVR.slider(cfg, "input/dpad_meia_cardeal", 45.0, 75.0, 1.0,
					func(v: float) -> String: return "%d°" % roundi(v))))

	rodape.add_child(WidgetsVR.mono("Segure o botão de menu 0,5 s para abrir/fechar"))
	rodape.add_child(espacador())
	var bt := WidgetsVR.botao("Restaurar padrões")
	bt.pressed.connect(func() -> void: cfg.restaurar("input"))
	rodape.add_child(bt)


func _linha(origem: String, destino: String, cor_id: Variant) -> Control:
	var caixa := HBoxContainer.new()
	caixa.add_theme_constant_override("separation", 20)
	caixa.custom_minimum_size.y = 66

	var lab := Label.new()
	lab.text = origem
	lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caixa.add_child(lab)

	var seta := WidgetsVR.mono("→")
	seta.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caixa.add_child(seta)

	var cor: Color = CORES.get(cor_id, TemaVR.LINE) if cor_id != null else TemaVR.LINE
	var c := WidgetsVR.chip(destino, cor)
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	caixa.add_child(c)
	return caixa
