class_name MapaInput
extends RefCounted
## O mapa de botões do Touch para o joypad libretro: quais origens existem, e
## como um estado de origens vira um estado de ids do core.
##
## Vive fora do `xr_main` pelo mesmo motivo que o `Guidao`: aqui não entra nada
## de XR — entram dois dicionários e sai um terceiro —, e é isso que permite
## conferir o remap sem headset, onde cada tentativa custa dez minutos de
## export. Quem sabe de OpenXR é o `xr_main`, que só preenche `pressionadas`.
##
## O que **não** é remapeável são os dois analógicos: eles não são botões para o
## core (o esquerdo do SNES vira D-pad por setores, os dois do N64 são eixos de
## verdade), e enfiá-los na mesma tabela obrigaria cada linha a explicar se é
## botão ou eixo. Eles continuam fixos, e a página os mostra como informação.

## Destino "nenhum": a origem existe mas não manda nada para o core. Precisa de
## um valor próprio porque 0 é um id de botão de verdade (`JOYPAD_B`).
const NADA := -1

## Quantos ids digitais o joypad libretro tem (0..15). Todos são zerados a cada
## frame antes do mapa entrar — sem isso, um botão que deixa de ser mapeado
## ficaria preso no último estado que teve.
const IDS := 16

## Origens físicas do Touch, na ordem em que a mão as encontra — a mesma ordem
## em que a página as lista.
##
## O primeiro campo é o **id**, que entra na chave de configuração e no nome do
## nó: ele não traduz, e é por ele que o teste acha a linha. O segundo é chave de
## tradução, e não o rótulo pronto — a página joga o que está aqui direto no
## `Label`, então texto literal apareceria em português com `--language en`, ao
## lado das linhas de eixo que já traduzem.
const ORIGENS := [
	["dir_ax", "INPUT_BOTAO_A_DIR"],
	["dir_by", "INPUT_BOTAO_B_DIR"],
	["esq_ax", "INPUT_BOTAO_X_ESQ"],
	["esq_by", "INPUT_BOTAO_Y_ESQ"],
	["esq_trigger", "INPUT_GATILHO_ESQ"],
	["dir_trigger", "INPUT_GATILHO_DIR"],
	["dir_grip", "INPUT_GRIP_DIR"],
	["esq_grip", "INPUT_GRIP_ESQ"],
]

## Destinos oferecidos quando o core não declarou descritor nenhum. O caminho
## normal é perguntar ao core (`EmuCore.descritores_input()`), que também dá o
## **nome** de cada id naquele console; isto é só a rede de segurança.
const DESTINOS_RESERVA := [
	LibretroHost.JOYPAD_B, LibretroHost.JOYPAD_Y, LibretroHost.JOYPAD_SELECT,
	LibretroHost.JOYPAD_START, LibretroHost.JOYPAD_UP, LibretroHost.JOYPAD_DOWN,
	LibretroHost.JOYPAD_LEFT, LibretroHost.JOYPAD_RIGHT, LibretroHost.JOYPAD_A,
	LibretroHost.JOYPAD_X, LibretroHost.JOYPAD_L, LibretroHost.JOYPAD_R,
	LibretroHost.JOYPAD_L2, LibretroHost.JOYPAD_R2,
]


## Chave do ConfigEmu para uma origem num sistema. Fica sob `input/` porque é
## isso que a torna parte do perfil do cartucho.
static func chave(sistema: String, origem: String) -> String:
	return "input/mapa_%s_%s" % [sistema, origem]


## Rótulo de uma origem, para a página não decorar a lista.
static func rotulo(origem: String) -> String:
	for o in ORIGENS:
		if o[0] == origem:
			return o[1]
	return origem


## Estado de todos os ids do joypad a partir do que está pressionado no Touch.
##
## `mapa` é origem → id (o que o jogador escolheu), `pressionadas` é origem →
## bool (o que a mão está fazendo agora) e `pre` são ids já resolvidos por fora
## — as direções que o analógico esquerdo gera no SNES, que não passam por
## origem nenhuma.
##
## Duas origens no mesmo destino somam em vez de a última ganhar: mapear os dois
## gatilhos no mesmo botão é uma escolha legítima, e a alternativa silenciosa
## seria um dos dois não fazer nada.
static func combinar(mapa: Dictionary, pressionadas: Dictionary, pre: Dictionary) -> Dictionary:
	var fora := {}
	for id in IDS:
		fora[id] = pre.get(id, false)
	for origem: String in mapa:
		var id := int(mapa[origem])
		if id < 0 or id >= IDS:
			continue
		fora[id] = fora[id] or bool(pressionadas.get(origem, false))
	return fora
