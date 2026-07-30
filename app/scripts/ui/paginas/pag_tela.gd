class_name PagTela
extends PagBase
## Tamanho, posição e curvatura da tela do emulador no espaço.
##
## Nos sistemas de duas telas (o DS) a página ganha um segundo bloco, com a tela
## de baixo — a da caneta — tendo posição própria. Ele aparece **só** quando há
## duas telas: três sliders mortos num jogo de SNES seriam quatro linhas a mais
## para rolar atrás do que interessa.

# Limites que antes eram constantes em vr/xr_main.gd.
const ESCALA_MIN := 0.3
const ESCALA_MAX := 8.0
const DIST_MIN := 0.8
const DIST_MAX := 8.0
const ALTURA_MIN := -1.0
const ALTURA_MAX := 1.0

## A tela de baixo é de mão, e o alcance do braço é o teto útil — deixá-la ir a
## 8 m como a de cima só daria uma caneta que não alcança.
##
## O piso não é 0,4 por acaso: abaixo de ~0,7 m a mão fica **à frente** do quad e
## o laser, que só enxerga para diante, deixa de acertar. Perto demais a caneta
## para de existir, que é o oposto do que a proximidade deveria dar.
const DS_DIST_MIN := 0.7
const DS_DIST_MAX := 2.0

## Predefinições: escala, distância. Cobrem os três usos que o projeto
## promete — do portátil ao cinema.
const PREDEFINICOES := {
	"TELA_PRE_PORTATIL": [0.6, 1.0],
	"TELA_PRE_TV": [1.5, 2.2],
	"TELA_PRE_CINEMA": [5.0, 6.0],
}

## Pedido de centralizar a tela à frente de quem joga. A conta é do `xr_main` —
## é lá que existem câmera e sala —, então a página só avisa.
signal centrar_pedido

var _cfg: ConfigEmu
var _emu: EmuCore


func _init(cfg: ConfigEmu, emu: EmuCore) -> void:
	super("MENU_TELA")
	_cfg = cfg
	_emu = emu

	rodape_de_ajuste(cfg, "tela")
	atualizar()
	cfg.mudou.connect(func(k: String, _v: Variant) -> void:
		if k.begins_with("tela/"):
			_atualizar_cabecalho()
	)


## Remonta o conteúdo. Chamada ao abrir o painel, porque o que a página mostra
## depende do sistema da ROM — e a ROM pode ter trocado desde a última vez.
func atualizar() -> void:
	for filho in conteudo.get_children():
		filho.queue_free()
		conteudo.remove_child(filho)

	# Primeiro de tudo, e com rótulo bilíngue: quem não lê português precisa
	# reconhecer esta linha para chegar às outras. Sem aba própria, é o que
	# substitui a descoberta que uma aba daria.
	conteudo.add_child(WidgetsVR.campo("TELA_IDIOMA", "",
			WidgetsVR.segmentado(_cfg, "app/idioma", Idioma.ROTULOS)))
	conteudo.add_child(WidgetsVR.divisoria())

	conteudo.add_child(WidgetsVR.campo("TELA_PREDEFINICAO", "", _predefinicoes()))
	# O atalho do controle vem escrito ao lado: sem isso ninguém descobre que o
	# clique do analógico direito faz isto, e um atalho que ninguém acha é o
	# mesmo que não existir. Mesma razão dos "analógico direito ↕" abaixo.
	conteudo.add_child(WidgetsVR.campo("TELA_CENTRALIZAR", "TELA_CENTRALIZAR_DESC",
			_botao_centrar()))
	conteudo.add_child(WidgetsVR.campo("TELA_TAMANHO", "TELA_TAMANHO_DESC",
			WidgetsVR.slider(_cfg, "tela/escala", ESCALA_MIN, ESCALA_MAX, 0.05,
					func(v: float) -> String: return "%.2f×" % v)))
	conteudo.add_child(WidgetsVR.campo("TELA_DISTANCIA", "TELA_DISTANCIA_DESC",
			WidgetsVR.slider(_cfg, "tela/distancia", DIST_MIN, DIST_MAX, 0.05,
					func(v: float) -> String: return "%.2f m" % v)))
	conteudo.add_child(WidgetsVR.campo("TELA_ALTURA", "TELA_ALTURA_DESC",
			WidgetsVR.slider(_cfg, "tela/altura", ALTURA_MIN, ALTURA_MAX, 0.02,
					func(v: float) -> String: return "%+.2f m" % v)))
	conteudo.add_child(WidgetsVR.campo("TELA_CURVATURA", "TELA_CURVATURA_DESC",
			WidgetsVR.slider(_cfg, "tela/curvatura", 0.0, 1.0, 0.05,
					func(v: float) -> String: return "%d %%" % roundi(v * 100.0))))

	if NavegadorRoms.tem_duas_telas(_emu.sistema):
		conteudo.add_child(WidgetsVR.divisoria())
		conteudo.add_child(WidgetsVR.campo("TELA_DE_BAIXO", "TELA_DE_BAIXO_DESC",
				WidgetsVR.mono("TELA_POSICAO_PROPRIA")))
		conteudo.add_child(WidgetsVR.campo("TELA_TAMANHO", "",
				WidgetsVR.slider(_cfg, "tela/ds_escala", ESCALA_MIN, 2.0, 0.05,
						func(v: float) -> String: return "%.2f×" % v)))
		conteudo.add_child(WidgetsVR.campo("TELA_DISTANCIA", "TELA_ALCANCE_BRACO",
				WidgetsVR.slider(_cfg, "tela/ds_distancia", DS_DIST_MIN, DS_DIST_MAX, 0.05,
						func(v: float) -> String: return "%.2f m" % v)))
		conteudo.add_child(WidgetsVR.campo("TELA_ALTURA", "TELA_ALTURA_DESC",
				WidgetsVR.slider(_cfg, "tela/ds_altura", ALTURA_MIN, ALTURA_MAX, 0.02,
						func(v: float) -> String: return "%+.2f m" % v)))

	_atualizar_cabecalho()


## Põe tela e sala à frente de quem joga agora. Existe além do atalho porque a
## página é onde se procura quando a tela está fora do lugar — e porque o atalho
## fica atrás de um clique que não tem rótulo nenhum no controle.
func _botao_centrar() -> Control:
	var caixa := HBoxContainer.new()
	caixa.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bt := WidgetsVR.botao("TELA_TRAZER_FRENTE")
	bt.name = "CentrarTela"
	bt.custom_minimum_size.x = 300
	bt.pressed.connect(func() -> void: centrar_pedido.emit())
	caixa.add_child(bt)
	return caixa


func _predefinicoes() -> Control:
	var caixa := HBoxContainer.new()
	caixa.add_theme_constant_override("separation", 5)
	caixa.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for nome in PREDEFINICOES:
		var bt := WidgetsVR.botao(nome)
		bt.custom_minimum_size.x = 150
		var v: Array = PREDEFINICOES[nome]
		bt.pressed.connect(func() -> void:
			_cfg.definir("tela/escala", v[0])
			_cfg.definir("tela/distancia", v[1])
		)
		caixa.add_child(bt)
	return caixa


func _atualizar_cabecalho() -> void:
	var escala: float = _cfg.obter("tela/escala")
	var dist: float = _cfg.obter("tela/distancia")
	# LARGURA_BASE do xr_main: 1.4 m em escala 1.0.
	caminho_lab.text = tr("TELA_MEDIDAS") % [1.4 * escala, dist]
