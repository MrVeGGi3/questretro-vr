class_name PagInput
extends PagBase
## Mapa do controle Touch para o joypad libretro, mais o ajuste fino da
## conversão analógico → D-pad.
##
## O mapa muda com o sistema da ROM, e o **nome** de cada destino vem do core:
## o mesmo `JOYPAD_L2` é "Z Trigger" no N64 e não existe no SNES. Por isso a
## coluna da direita sai de `EmuCore.descritores_input()`
## (`SET_INPUT_DESCRIPTORS`) e não de tabela escrita aqui — foi o que já me
## salvou de mostrar "A" onde o core entende "B".
##
## O mapa de **botões** continua sendo só exibição, sem remapear. Remap de
## verdade precisa de um modo "aperte um botão" que capture input do Touch
## enquanto o menu está aberto — e é justamente o menu que hoje congela o input
## do jogo. Fica para quando o painel souber distinguir os dois.
##
## O que dá para mudar aqui são os ajustes contínuos: a zona morta do D-pad e o
## guidão de nave do N64, que troca o thumbstick pela pose das duas mãos.

## Origem no Touch → id do joypad libretro, por sistema, na ordem em que a mão
## encontra. Espelha `xr_main._input_snes()` / `_input_n64()`; mudar lá pede
## mudar aqui. Os eixos analógicos não têm id de botão e vão como `null`.
const MAPAS := {
	"snes": [
		# Sem id: o stick vira as quatro direções, e mostrar o nome de uma só
		# ("D-Pad Up") diria que as outras três não estão ligadas.
		["Analógico esquerdo", null, "D-PAD"],
		["Botão A (direito)", LibretroHost.JOYPAD_A, ""],
		["Botão B (direito)", LibretroHost.JOYPAD_B, ""],
		["Botão X (esquerdo)", LibretroHost.JOYPAD_X, ""],
		["Botão Y (esquerdo)", LibretroHost.JOYPAD_Y, ""],
		["Gatilho esquerdo", LibretroHost.JOYPAD_L, ""],
		["Gatilho direito", LibretroHost.JOYPAD_R, ""],
		["Grip direito", LibretroHost.JOYPAD_START, ""],
		["Grip esquerdo", LibretroHost.JOYPAD_SELECT, ""],
	],
	"n64": [
		["Analógico esquerdo", null, "MANCHE"],
		["Analógico direito", null, "C"],
		["Botão A (direito)", LibretroHost.JOYPAD_B, ""],
		["Botão B (direito)", LibretroHost.JOYPAD_Y, ""],
		["Gatilho esquerdo", LibretroHost.JOYPAD_L, ""],
		["Gatilho direito", LibretroHost.JOYPAD_R, ""],
		["Grip esquerdo", LibretroHost.JOYPAD_L2, ""],
		["Grip direito", LibretroHost.JOYPAD_START, ""],
		["Botão Y (esquerdo)", LibretroHost.JOYPAD_UP, ""],
		["Botão X (esquerdo)", LibretroHost.JOYPAD_DOWN, ""],
	],
}

## Com o guidão ligado, o manche do N64 sai da pose das mãos e o analógico
## esquerdo passa a servir de recentro. As duas primeiras linhas de MAPAS["n64"]
## deixam de valer, então este mapa as substitui em vez de somar a elas.
const MAPA_GUIDAO := [
	["Pose dos dois controles", null, "MANCHE"],
	["Clique do analógico esq.", null, "CENTRAR"],
	["Analógico direito", null, "C"],
]

## Cor do chip por nome de botão, onde o console tem uma. Casa com o rótulo que
## o core declara, então serve para os dois sistemas.
const CORES := {
	"A": TemaVR.BTN_A, "B": TemaVR.BTN_B, "X": TemaVR.BTN_X, "Y": TemaVR.BTN_Y,
}

var _emu: EmuCore
var _cfg: ConfigEmu
var _linhas: VBoxContainer
var _secao_dpad: VBoxContainer
var _secao_guidao: VBoxContainer


func _init(cfg: ConfigEmu, emu: EmuCore) -> void:
	super("Input")
	_emu = emu
	_cfg = cfg

	_linhas = VBoxContainer.new()
	conteudo.add_child(_linhas)

	# As duas seções de ajuste são mutuamente exclusivas, e não por economia de
	# espaço: a zona morta do D-pad só alimenta `xr_main._dpad_do_stick()`, que
	# só o SNES usa, e o guidão só existe onde há eixo analógico de verdade.
	# Mostrar as duas sempre ofereceria um ajuste morto em cada sistema.
	_secao_dpad = _montar_dpad(cfg)
	conteudo.add_child(_secao_dpad)

	_secao_guidao = _montar_guidao(cfg)
	conteudo.add_child(_secao_guidao)

	# Ligar o guidão troca a linha do manche na lista acima. Sem isto a página
	# ficaria mentindo até o painel ser reaberto — e o interruptor está a dois
	# dedos da lista que ele contradiz.
	cfg.mudou.connect(func(chave: String, _v: Variant) -> void:
		if chave == "input/n64_guidao":
			atualizar())

	# Depois de montar as seções: atualizar() decide qual delas aparece.
	atualizar()

	rodape.add_child(WidgetsVR.mono("Segure o botão de menu 0,5 s para abrir/fechar"))
	rodape.add_child(espacador())
	var bt := WidgetsVR.botao("Restaurar padrões")
	bt.pressed.connect(func() -> void: cfg.restaurar("input"))
	rodape.add_child(bt)


## Conversão analógico → D-pad, que só o SNES faz. No N64 o stick é eixo de
## verdade e estes três sliders não teriam a quem responder.
func _montar_dpad(cfg: ConfigEmu) -> VBoxContainer:
	var caixa := VBoxContainer.new()
	caixa.add_child(WidgetsVR.divisoria(TemaVR.LINE))

	var titulo := Label.new()
	titulo.text = "Zona morta do D-pad"
	titulo.add_theme_color_override("font_color", TemaVR.DIM)
	caixa.add_child(titulo)

	caixa.add_child(WidgetsVR.campo("Engatar", "quanto empurrar para valer",
			WidgetsVR.slider(cfg, "input/dpad_engaja", 0.2, 0.9, 0.01,
					func(v: float) -> String: return "%.2f" % v)))
	caixa.add_child(WidgetsVR.campo("Soltar", "histerese: evita tremular",
			WidgetsVR.slider(cfg, "input/dpad_solta", 0.1, 0.8, 0.01,
					func(v: float) -> String: return "%.2f" % v)))
	caixa.add_child(WidgetsVR.campo("Setor cardeal", "acima de 45° gera diagonais",
			WidgetsVR.slider(cfg, "input/dpad_meia_cardeal", 45.0, 75.0, 1.0,
					func(v: float) -> String: return "%d°" % roundi(v))))
	return caixa


## Ajustes do guidão de nave. Só faz sentido no N64, então `atualizar()` esconde
## a seção inteira nos outros sistemas.
##
## Ângulo e curso são chute educado: ninguém sabe qual inclinação é confortável
## sem pilotar. Ficam como slider justamente porque a resposta vem do corpo, e
## corrigi-los aqui custa segundos contra os dez minutos de um export.
func _montar_guidao(cfg: ConfigEmu) -> VBoxContainer:
	var caixa := VBoxContainer.new()
	caixa.add_child(WidgetsVR.divisoria(TemaVR.LINE))

	var titulo := Label.new()
	titulo.text = "Guidão de nave"
	titulo.add_theme_color_override("font_color", TemaVR.DIM)
	caixa.add_child(titulo)

	caixa.add_child(WidgetsVR.campo("Ligar", "as duas mãos viram o manche",
			WidgetsVR.interruptor(cfg, "input/n64_guidao")))
	caixa.add_child(WidgetsVR.campo("Inclinação cheia", "quanto tombar para virar tudo",
			WidgetsVR.slider(cfg, "input/guidao_angulo_max", 15.0, 60.0, 1.0,
					func(v: float) -> String: return "%d°" % roundi(v))))
	caixa.add_child(WidgetsVR.campo("Curso cheio", "quanto empurrar para subir/descer tudo",
			WidgetsVR.slider(cfg, "input/guidao_curso", 0.1, 0.5, 0.01,
					func(v: float) -> String: return "%d cm" % roundi(v * 100.0))))
	caixa.add_child(WidgetsVR.campo("Zona morta", "ignora tremor de mão",
			WidgetsVR.slider(cfg, "input/guidao_zona_morta", 0.0, 0.3, 0.01,
					func(v: float) -> String: return "%.2f" % v)))
	# O Star Fox 64 já nasce invertido, e a preferência varia de pessoa para
	# pessoa: não é escolha que dê para acertar por padrão.
	caixa.add_child(WidgetsVR.campo("Inverter subir/descer", "empurrar mergulha",
			WidgetsVR.interruptor(cfg, "input/guidao_inverter_y")))
	caixa.add_child(WidgetsVR.campo("Mostrar leitura", "os eixos ao vivo, na tela",
			WidgetsVR.interruptor(cfg, "input/guidao_diag")))
	caixa.add_child(WidgetsVR.mono("Clique o analógico esquerdo para centralizar"))
	return caixa


## Remonta a lista para o sistema da ROM em execução. Chamada pelo MenuRaiz ao
## abrir o painel, porque a ROM pode ter trocado desde a última vez.
func atualizar() -> void:
	for filho in _linhas.get_children():
		filho.queue_free()

	var sistema := _emu.sistema if _emu != null else ""
	var mapa: Array = MAPAS.get(sistema, MAPAS["snes"])
	if sistema == "n64" and _cfg.obter("input/n64_guidao"):
		# As duas primeiras linhas (os dois analógicos) saem; o resto do mapa do
		# N64 — botões, gatilhos, grips — não muda com o guidão.
		mapa = MAPA_GUIDAO + mapa.slice(2)
	var nomes := _nomes_do_core()

	caminho_lab.text = "Meta Touch · porta 1"
	if not sistema.is_empty():
		caminho_lab.text += " · " + NavegadorRoms.nome_sistema(sistema)

	var e_n64 := sistema == "n64"
	_secao_guidao.visible = e_n64
	_secao_dpad.visible = not e_n64

	for entrada in mapa:
		var origem: String = entrada[0]
		var id: Variant = entrada[1]
		# O rótulo fixo é para o que não tem id de botão (os eixos). Para o
		# resto, o nome do core manda; o id cru só aparece se ele não declarou.
		var destino: String = entrada[2]
		if id != null:
			destino = nomes.get(id, "id %d" % id)
		_linhas.add_child(_linha(origem, destino))


## Nome de cada id do joypad, como o core declarou. Vazio se o core não declarou
## nada — aí a coluna cai no id cru, que é feio mas honesto.
func _nomes_do_core() -> Dictionary:
	var fora := {}
	if _emu == null:
		return fora
	for d: Dictionary in _emu.descritores_input():
		# Porta 0 e device joypad: é o que o nosso mapa cobre.
		if d["port"] == 0 and d["device"] == LibretroHost.DEVICE_JOYPAD:
			var desc: String = d["desc"]
			if not desc.is_empty():
				fora[d["id"]] = desc
	return fora


func _linha(origem: String, destino: String) -> Control:
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

	# O core rotula com frase ("A Button (C3)"), não com letra; a cor sai da
	# primeira palavra, que é onde o nome do botão está nos dois sistemas.
	var chave := destino.split(" ")[0].to_upper()
	var c := WidgetsVR.chip(destino, CORES.get(chave, TemaVR.LINE))
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	caixa.add_child(c)
	return caixa
