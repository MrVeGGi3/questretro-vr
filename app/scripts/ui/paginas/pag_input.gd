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
## Os **botões** são remapeáveis: tocar numa linha abre a lista de destinos ali
## mesmo, embaixo dela, e tocar num destino fecha. Escolher apontando, e não
## por um modo "aperte um botão", não é preguiça — é o que contorna o problema
## que segurava o remap: com o painel aberto o input do jogo fica congelado, e
## um modo de captura precisaria distinguir "apertei para escolher" de "apertei
## para jogar". Apontar é o que o laser já sabe fazer.
##
## Nada de PopupMenu ou OptionButton aqui: eles abrem em outra janela, e esta
## página vive dentro de um SubViewport colado num quad — a janela apareceria
## fora do painel, ou não apareceria.
##
## Também dá para mudar os ajustes contínuos: a zona morta do D-pad e o guidão
## de nave do N64, que troca o thumbstick pela pose das duas mãos.

## Linhas que **não** são remapeáveis, por sistema: os analógicos não são botões
## para o core. No SNES o esquerdo vira as quatro direções (mostrar o nome de
## uma só diria que as outras três não estão ligadas); no N64 os dois são eixos
## de verdade.
const EIXOS := {
	"snes": [["Analógico esquerdo", "D-PAD"]],
	"megadrive": [["Analógico esquerdo", "D-PAD"]],
	"n64": [["Analógico esquerdo", "MANCHE"], ["Analógico direito", "C"]],
}

## Com o guidão ligado, o manche do N64 sai da pose das mãos e o analógico
## esquerdo passa a servir de recentro — então as linhas de eixo do N64 deixam
## de valer e estas as substituem.
const EIXOS_GUIDAO := [
	["Pose dos dois controles", "MANCHE"],
	["Clique do analógico esq.", "CENTRAR"],
	["Analógico direito", "C"],
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
var _bt_perfil: Button
var _perfil_lab: Label
var _nomes: Dictionary = {}   ## nomes dos ids vindos do core; ver _nomes_do_core()


func _init(cfg: ConfigEmu, emu: EmuCore) -> void:
	super("Input")
	_emu = emu
	_cfg = cfg

	_linhas = VBoxContainer.new()
	conteudo.add_child(_linhas)

	# Antes dos ajustes, e não depois: tudo o que vem abaixo pertence ou ao jogo
	# ou ao geral, e quem mexe num slider precisa saber qual dos dois está
	# editando *antes* de mexer.
	conteudo.add_child(_montar_perfil())

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

	cfg.perfil_mudou.connect(func(_ativo: bool) -> void: _atualizar_perfil())

	# Depois de montar as seções: atualizar() decide qual delas aparece.
	atualizar()

	rodape.add_child(WidgetsVR.mono("Segure o botão de menu 0,5 s para abrir/fechar"))
	rodape.add_child(espacador())
	var bt := WidgetsVR.botao("Restaurar padrões")
	bt.pressed.connect(func() -> void: cfg.restaurar("input"))
	rodape.add_child(bt)


## Perfil do cartucho: com ele ligado, tudo o que esta página ajusta vale só
## para o jogo em execução. É o que o Star Fox 64 pede e o Super Mario 64 não —
## a pose das mãos no lugar do manche não faz sentido num jogo de plataforma, e
## até aqui ligar o guidão para um ligava para os dois.
##
## Botão, e não interruptor: apagar um perfil não tem desfazer, então precisa de
## confirmação, e um interruptor que pergunta antes de desligar passa a sessão
## inteira mostrando o estado errado enquanto espera resposta.
func _montar_perfil() -> Control:
	var caixa := VBoxContainer.new()
	caixa.add_child(WidgetsVR.divisoria(TemaVR.LINE))

	_perfil_lab = WidgetsVR.mono("")
	_bt_perfil = WidgetsVR.botao("")
	# Nomeado pelo mesmo motivo dos botões de apagar save: o teste precisa achar
	# este e não outro qualquer com o mesmo texto.
	_bt_perfil.name = "PerfilJogo"
	_bt_perfil.custom_minimum_size.x = 300
	_bt_perfil.pressed.connect(_ao_tocar_perfil)

	var linha := HBoxContainer.new()
	linha.add_theme_constant_override("separation", 20)
	linha.custom_minimum_size.y = 88
	var col := VBoxContainer.new()
	col.custom_minimum_size.x = 300
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 2)
	var tit := Label.new()
	tit.text = "Ajustes deste jogo"
	col.add_child(tit)
	col.add_child(_perfil_lab)
	linha.add_child(col)
	_bt_perfil.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	linha.add_child(_bt_perfil)

	caixa.add_child(linha)
	_atualizar_perfil()
	return caixa


## Primeira batida arma, segunda apaga — o mesmo contrato dos saves, pela mesma
## razão: no headset o clique sai de um laser apontado à distância, que erra o
## alvo com mais facilidade que um mouse. Sair da página desarma, porque o
## estado mora no próprio botão.
func _ao_tocar_perfil() -> void:
	if not _cfg.tem_perfil():
		_cfg.criar_perfil()
		return
	if not _bt_perfil.get_meta("armado", false):
		_bt_perfil.set_meta("armado", true)
		_bt_perfil.text = "Apagar mesmo?"
		_bt_perfil.add_theme_color_override("font_color", TemaVR.BTN_A)
		return
	_cfg.apagar_perfil()


func _atualizar_perfil() -> void:
	if _bt_perfil == null:
		return
	_bt_perfil.set_meta("armado", false)
	_bt_perfil.remove_theme_color_override("font_color")

	var sem_rom := _emu == null or _emu.rom_atual.is_empty()
	_bt_perfil.disabled = sem_rom
	if sem_rom:
		_bt_perfil.text = "Criar perfil"
		_perfil_lab.text = "sem jogo carregado"
		return

	if _cfg.tem_perfil():
		_bt_perfil.text = "Apagar perfil"
		_perfil_lab.text = "perfis/%s.cfg" % _cfg.perfil_id()
	else:
		_bt_perfil.text = "Criar perfil"
		_perfil_lab.text = "seguindo os ajustes gerais"


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
	# O mínimo desce a 4 cm porque 10 cm ainda era lerdo para quem pilotou; o
	# máximo antigo (50 cm) ninguém alcança sem sair da cadeira.
	caixa.add_child(WidgetsVR.campo("Curso cheio", "quanto empurrar para subir/descer tudo",
			WidgetsVR.slider(cfg, "input/guidao_curso", 0.04, 0.30, 0.01,
					func(v: float) -> String: return "%d cm" % roundi(v * 100.0))))
	caixa.add_child(WidgetsVR.campo("Zona morta", "ignora tremor de mão",
			WidgetsVR.slider(cfg, "input/guidao_zona_morta", 0.0, 0.3, 0.01,
					func(v: float) -> String: return "%.2f" % v)))
	# Acima de 1 o começo do movimento rende mais; abaixo, controle fino perto
	# do centro. Os extremos não mudam — o eixo cheio continua alcançável em
	# qualquer curva, então mexer aqui nunca custa manobra.
	caixa.add_child(WidgetsVR.campo("Curva", "acima de 1: reage mais no começo",
			WidgetsVR.slider(cfg, "input/guidao_curva", 0.5, 3.0, 0.1,
					func(v: float) -> String:
						return "linear" if is_equal_approx(v, 1.0) else "%.1f" % v)))
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
	# A ROM pode ter trocado, e com ela o core: os nomes dos ids são de outro
	# console agora.
	_nomes = {}

	# A ROM pode ter trocado desde a última abertura do painel, e com ela o
	# perfil — o botão precisa falar do cartucho que está rodando agora.
	_atualizar_perfil()

	var sistema := _sistema()
	var eixos: Array = EIXOS.get(sistema, EIXOS["snes"])
	if sistema == "n64" and _cfg.obter("input/n64_guidao"):
		eixos = EIXOS_GUIDAO

	caminho_lab.text = "Meta Touch · porta 1"
	if not sistema.is_empty():
		caminho_lab.text += " · " + NavegadorRoms.nome_sistema(sistema)

	var e_n64 := sistema == "n64"
	_secao_guidao.visible = e_n64
	_secao_dpad.visible = not e_n64

	# Primeiro o que não se remapeia, depois o que se remapeia: as duas metades
	# ficam separadas em vez de intercaladas, para não parecer que uma linha de
	# eixo não respondeu ao toque.
	for entrada in eixos:
		_linhas.add_child(_linha_fixa(entrada[0], entrada[1]))

	for entrada in MapaInput.ORIGENS:
		_linhas.add_child(_linha_botao(sistema, entrada[0], entrada[1]))


## Sistema da ROM em execução, ou "snes" quando não há ROM: a página precisa
## mostrar *algum* mapa, e é o do sistema que sempre está no APK.
func _sistema() -> String:
	var s := _emu.sistema if _emu != null else ""
	return s if EIXOS.has(s) else "snes"


## Nome de cada id do joypad, como o core declarou. Vazio se o core não declarou
## nada — aí a coluna cai no id cru, que é feio mas honesto.
##
## Guardado por remontagem: cada linha e cada destino do seletor pergunta o nome
## de um id, e sem o cache isso viraria uma varredura dos descritores por chip.
func _nomes_do_core() -> Dictionary:
	if not _nomes.is_empty():
		return _nomes
	var fora := {}
	if _emu == null:
		return fora
	for d: Dictionary in _emu.descritores_input():
		# Porta 0 e device joypad: é o que o nosso mapa cobre.
		if d["port"] == 0 and d["device"] == LibretroHost.DEVICE_JOYPAD:
			var desc: String = d["desc"]
			if not desc.is_empty():
				fora[d["id"]] = desc
	_nomes = fora
	return fora


## Linha de eixo: informação, sem toque. Os analógicos não são botões para o
## core, então não há destino para escolher.
func _linha_fixa(origem: String, destino: String) -> Control:
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

	caixa.add_child(_chip(destino))
	return caixa


## Linha remapeável: a linha inteira é o alvo do laser, e não só o chip. Mirar
## um chip de 120 px a dois metros de distância com a mão no ar é bem mais
## difícil do que mirar a faixa inteira.
func _linha_botao(sistema: String, origem: String, rotulo: String) -> Control:
	var caixa := VBoxContainer.new()

	var bt := Button.new()
	# Nomeado para o teste achar esta origem e não outra: os rótulos mudam com o
	# idioma do console, o nome da origem não.
	bt.name = "Origem_" + origem
	bt.custom_minimum_size.y = 66
	bt.alignment = HORIZONTAL_ALIGNMENT_LEFT
	# Só o estado normal fica invisível: hover e pressed continuam vindo do tema,
	# e são eles que dizem que a linha é tocável antes de alguém tocar.
	bt.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	caixa.add_child(bt)

	var linha := HBoxContainer.new()
	linha.add_theme_constant_override("separation", 20)
	linha.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# O conteúdo é enfeite dentro do botão: quem recebe o clique é o botão, e um
	# filho que capturasse o mouse abriria buracos no alvo.
	linha.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bt.add_child(linha)

	var lab := Label.new()
	lab.text = rotulo
	lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	linha.add_child(lab)

	var seta := WidgetsVR.mono("→")
	seta.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	linha.add_child(seta)

	var id := int(_cfg.obter(MapaInput.chave(sistema, origem)))
	linha.add_child(_chip(_nome_destino(id)))

	var escolhas := VBoxContainer.new()
	escolhas.visible = false
	caixa.add_child(escolhas)

	bt.pressed.connect(func() -> void:
		if escolhas.visible:
			escolhas.visible = false
			return
		_fechar_escolhas()
		for filho in escolhas.get_children():
			filho.queue_free()
		escolhas.add_child(_grade_destinos(sistema, origem))
		escolhas.visible = true
	)
	return caixa


## Fecha qualquer seletor aberto. Dois abertos ao mesmo tempo empurrariam a
## página para baixo duas vezes, e o segundo nasceria fora da tela.
func _fechar_escolhas() -> void:
	for linha in _linhas.get_children():
		if linha is VBoxContainer and linha.get_child_count() > 1:
			linha.get_child(1).visible = false


## Os destinos possíveis, em grade, com o nome que o **core** dá a cada um. A
## lista sai de `SET_INPUT_DESCRIPTORS`: é o core que sabe que `JOYPAD_L2` é o
## "Z Trigger" do N64 e não existe no SNES.
func _grade_destinos(sistema: String, origem: String) -> Control:
	var grade := GridContainer.new()
	grade.columns = 4
	grade.add_theme_constant_override("h_separation", 8)
	grade.add_theme_constant_override("v_separation", 8)

	var ids := _destinos_do_core()
	# "Nada" primeiro: desligar uma origem é uma escolha tão válida quanto
	# trocá-la, e é a única forma de tirar um botão do caminho sem perdê-lo.
	var opcoes: Array = [MapaInput.NADA] + ids
	var atual := int(_cfg.obter(MapaInput.chave(sistema, origem)))

	for id: int in opcoes:
		var bt := Button.new()
		bt.name = "Destino_%s_%d" % [origem, id]
		bt.text = _nome_destino(id)
		bt.custom_minimum_size = Vector2(0, 52)
		bt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bt.toggle_mode = true
		bt.button_pressed = (id == atual)
		bt.focus_mode = Control.FOCUS_NONE
		var escolhido := id
		bt.pressed.connect(func() -> void:
			_cfg.definir(MapaInput.chave(sistema, origem), escolhido)
			atualizar()
		)
		grade.add_child(bt)
	return grade


## Ids que o core declara para a porta 1, em ordem. Cai na lista de reserva
## quando o core não declarou nada — sem ela a página não ofereceria destino
## nenhum, que é pior que oferecer ids crus.
func _destinos_do_core() -> Array:
	var ids: Array = _nomes_do_core().keys()
	ids.sort()
	return ids if not ids.is_empty() else MapaInput.DESTINOS_RESERVA.duplicate()


## Nome de um destino como o core o chama; o id cru se ele não declarou, e
## "Nada" para a origem desligada.
func _nome_destino(id: int) -> String:
	if id == MapaInput.NADA:
		return "Nada"
	return _nomes_do_core().get(id, "id %d" % id)


func _chip(destino: String) -> Control:
	# O core rotula com frase ("A Button (C3)"), não com letra; a cor sai da
	# primeira palavra, que é onde o nome do botão está nos dois sistemas.
	var chave := destino.split(" ")[0].to_upper()
	var c := WidgetsVR.chip(destino, CORES.get(chave, TemaVR.LINE))
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return c
