class_name CanetaDS
extends RefCounted
## A caneta do Nintendo DS: converte onde o laser bateu no quad da tela de baixo
## na coordenada de ponteiro que o core espera.
##
## Sem nenhuma dependência de XR, como `guidao.gd` e `mapa_input.gd`: entram um
## ponto e um tamanho, sai um `Vector2`. É o que permite conferir a conta sem
## headset — e aqui isso importa mais que nos outros, porque o erro natural não
## dá erro nenhum: a caneta encosta na tela **de cima**, o jogo não responde, e
## de dentro do Quest isso parece "o toque não funciona".
##
## O que torna a conta traiçoeira: o libretro quer a posição sobre o
## **framebuffer inteiro**, e o quad mostra só metade dele. As duas telas do DS
## vêm empilhadas num framebuffer 256×384 (ver `EmuCore.OPCOES["nds"]`, que fixa
## `screen_layout = Top/Bottom` e `screen_gap = 0` justamente para esta metade
## ser exata), então a tela de baixo é `v` de 0,5 a 1,0.

## Recorte de UV de cada tela, para os materiais dos dois quads. Moram aqui, e
## não no `xr_main`, para o teste poder conferir **as mesmas** que o app usa —
## duas cópias da mesma constante seria um teste que passa enquanto o app erra.
const UV_ESCALA := Vector3(1.0, 0.5, 1.0)
const UV_CIMA := Vector3.ZERO
const UV_BAIXO := Vector3(0.0, 0.5, 0.0)

## Fatia do framebuffer que o quad da caneta mostra, derivada do recorte acima.
const V0 := UV_BAIXO.y
const V1 := 1.0


## Ponto no espaço local do quad → ponteiro do libretro, em `[-1, 1]` nos dois
## eixos, com a origem no centro do framebuffer.
##
## O quad é centrado na origem e tem +Y para cima; a textura conta de cima para
## baixo, como em `PainelMenu._para_viewport()`.
static func para_ponteiro(local: Vector3, tamanho: Vector2) -> Vector2:
	if tamanho.x <= 0.0 or tamanho.y <= 0.0:
		return Vector2.ZERO

	# Posição dentro do quad, em 0..1.
	var u := clampf(local.x / tamanho.x + 0.5, 0.0, 1.0)
	var v := clampf(0.5 - local.y / tamanho.y, 0.0, 1.0)

	# E agora dentro do framebuffer inteiro, que é o que o core mede.
	var v_fb := V0 + v * (V1 - V0)

	return Vector2(u * 2.0 - 1.0, v_fb * 2.0 - 1.0)


## Se um ponto local cai dentro do quad. O raycast já garante isso quando acerta
## o colisor, mas quem chama pode ter um ponto de outra origem — e um ponto de
## fora, uma vez preso pelo clamp acima, viraria um toque na borda em vez de
## nenhum toque.
static func dentro(local: Vector3, tamanho: Vector2) -> bool:
	return absf(local.x) <= tamanho.x * 0.5 and absf(local.y) <= tamanho.y * 0.5
