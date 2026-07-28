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
	"Portátil": [0.6, 1.0],
	"TV": [1.5, 2.2],
	"Cinema": [5.0, 6.0],
}

var _cfg: ConfigEmu
var _emu: EmuCore


func _init(cfg: ConfigEmu, emu: EmuCore) -> void:
	super("Tela")
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

	conteudo.add_child(WidgetsVR.campo("Predefinição", "", _predefinicoes()))
	conteudo.add_child(WidgetsVR.campo("Tamanho", "analógico direito ↕",
			WidgetsVR.slider(_cfg, "tela/escala", ESCALA_MIN, ESCALA_MAX, 0.05,
					func(v: float) -> String: return "%.2f×" % v)))
	conteudo.add_child(WidgetsVR.campo("Distância", "analógico direito ↔",
			WidgetsVR.slider(_cfg, "tela/distancia", DIST_MIN, DIST_MAX, 0.05,
					func(v: float) -> String: return "%.2f m" % v)))
	conteudo.add_child(WidgetsVR.campo("Altura", "relativa aos olhos",
			WidgetsVR.slider(_cfg, "tela/altura", ALTURA_MIN, ALTURA_MAX, 0.02,
					func(v: float) -> String: return "%+.2f m" % v)))
	conteudo.add_child(WidgetsVR.campo("Curvatura", "vira uma malha em arco",
			WidgetsVR.slider(_cfg, "tela/curvatura", 0.0, 1.0, 0.05,
					func(v: float) -> String: return "%d %%" % roundi(v * 100.0))))

	if NavegadorRoms.tem_duas_telas(_emu.sistema):
		conteudo.add_child(WidgetsVR.divisoria())
		conteudo.add_child(WidgetsVR.campo("Tela de baixo", "a da caneta",
				WidgetsVR.mono("posição própria")))
		conteudo.add_child(WidgetsVR.campo("Tamanho", "",
				WidgetsVR.slider(_cfg, "tela/ds_escala", ESCALA_MIN, 2.0, 0.05,
						func(v: float) -> String: return "%.2f×" % v)))
		conteudo.add_child(WidgetsVR.campo("Distância", "ao alcance do braço",
				WidgetsVR.slider(_cfg, "tela/ds_distancia", DS_DIST_MIN, DS_DIST_MAX, 0.05,
						func(v: float) -> String: return "%.2f m" % v)))
		conteudo.add_child(WidgetsVR.campo("Altura", "relativa aos olhos",
				WidgetsVR.slider(_cfg, "tela/ds_altura", ALTURA_MIN, ALTURA_MAX, 0.02,
						func(v: float) -> String: return "%+.2f m" % v)))

	_atualizar_cabecalho()


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
	caminho_lab.text = "%.2f m de largura a %.2f m" % [1.4 * escala, dist]
