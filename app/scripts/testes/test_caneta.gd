extends Node
## Prova da caneta do DS sem headset.
##
##   xvfb-run -a godot --xr-mode off --path app res://cenas/test_caneta.tscn
##
## O que se testa aqui não é a interface: é a **conta**. O libretro quer a
## posição sobre o framebuffer inteiro e o quad mostra só a metade de baixo, e
## errar essa conversão não dá erro nenhum — dá a caneta encostando na tela de
## cima, e de dentro do Quest isso parece "o toque não funciona".
##
## Roda como cena, e não com `-s`, pela mesma razão dos outros: script de
## MainLoop trava na inicialização com a GDExtension carregada.

## Quanto duas coordenadas podem diferir e ainda serem a mesma.
const TOL := 0.001

## Tamanho do quad da tela de baixo nos testes: 4:3, como a tela do DS.
const TAM := Vector2(1.4, 1.05)

const CONFERENCIAS := 19

var _falhas := 0
var _feitas := 0


func _ready() -> void:
	_testar_centro()
	_testar_cantos()
	_testar_metade_de_baixo()
	_testar_dentro()
	_testar_degenerado()
	await _testar_recorte()

	if _feitas != CONFERENCIAS:
		print("  FALHA rodaram %d conferências, esperava %d" % [_feitas, CONFERENCIAS])
		_falhas += 1
	print("=== %s ===" % ("TUDO OK" if _falhas == 0 else "%d FALHA(S)" % _falhas))
	get_tree().quit(1 if _falhas > 0 else 0)


## O centro do quad é o centro da tela **de baixo**, que no framebuffer inteiro
## fica em y = +0,5 — não em zero. Zero aqui seria a linha que divide as duas
## telas, e um toque no meio da tela de baixo iria parar na borda da de cima.
func _testar_centro() -> void:
	var p := CanetaDS.para_ponteiro(Vector3.ZERO, TAM)
	_perto(p.x, 0.0, "centro do quad: x no meio")
	_perto(p.y, 0.5, "centro do quad: y no meio da metade de baixo")


func _testar_cantos() -> void:
	var meia_x := TAM.x * 0.5
	var meia_y := TAM.y * 0.5

	# Cantos de cima do quad = a linha do meio do framebuffer.
	var ce := CanetaDS.para_ponteiro(Vector3(-meia_x, meia_y, 0), TAM)
	_perto(ce.x, -1.0, "canto superior esquerdo: x na borda esquerda")
	_perto(ce.y, 0.0, "canto superior esquerdo: y na divisa das telas")

	var cd := CanetaDS.para_ponteiro(Vector3(meia_x, meia_y, 0), TAM)
	_perto(cd.x, 1.0, "canto superior direito: x na borda direita")

	# Cantos de baixo = o fim do framebuffer.
	var be := CanetaDS.para_ponteiro(Vector3(-meia_x, -meia_y, 0), TAM)
	_perto(be.x, -1.0, "canto inferior esquerdo: x na borda esquerda")
	_perto(be.y, 1.0, "canto inferior esquerdo: y no fim do framebuffer")

	var bd := CanetaDS.para_ponteiro(Vector3(meia_x, -meia_y, 0), TAM)
	_perto(bd.x, 1.0, "canto inferior direito: x na borda direita")
	_perto(bd.y, 1.0, "canto inferior direito: y no fim do framebuffer")


## A asserção que existe por causa do erro que se quer evitar: **nenhum** ponto
## do quad pode cair na metade de cima do framebuffer (y < 0). Se a conversão
## esquecer o deslocamento de meia tela, metade dos toques vai para lá.
func _testar_metade_de_baixo() -> void:
	var pior := 1.0
	for i in 21:
		for j in 21:
			var local := Vector3(
					(float(i) / 20.0 - 0.5) * TAM.x,
					(float(j) / 20.0 - 0.5) * TAM.y,
					0.0)
			pior = minf(pior, CanetaDS.para_ponteiro(local, TAM).y)
	_conferir(pior >= -TOL,
			"441 pontos do quad ficam todos na metade de baixo (menor y = %.3f)" % pior)

	# E o inverso: a tela de baixo tem de alcançar o fim do framebuffer, senão a
	# faixa de baixo do jogo seria inalcançável pela caneta.
	_perto(CanetaDS.para_ponteiro(Vector3(0, -TAM.y * 0.5, 0), TAM).y, 1.0,
			"e a borda de baixo alcança o fim")


func _testar_dentro() -> void:
	_conferir(CanetaDS.dentro(Vector3.ZERO, TAM), "o centro está dentro")
	_conferir(CanetaDS.dentro(Vector3(TAM.x * 0.5, TAM.y * 0.5, 0), TAM),
			"o canto exato ainda está dentro")
	_conferir(not CanetaDS.dentro(Vector3(TAM.x * 0.6, 0, 0), TAM),
			"um palmo à direita está fora")
	_conferir(not CanetaDS.dentro(Vector3(0, -TAM.y, 0), TAM),
			"um palmo abaixo está fora")


## Quad de tamanho zero acontece antes da primeira ROM carregar. Dividir por ele
## daria NaN, e NaN vira ponteiro em lugar nenhum — sem erro no console.
func _testar_degenerado() -> void:
	var p := CanetaDS.para_ponteiro(Vector3(0.3, 0.2, 0), Vector2.ZERO)
	_conferir(p == Vector2.ZERO, "quad de tamanho zero devolve zero, e não NaN")


## O recorte de UV: cada quad tem de mostrar **a sua** metade do framebuffer.
##
## Errar isto não produz erro nenhum — produz as duas telas mostrando a mesma
## coisa, ou trocadas, e nenhuma asserção numérica sobre coordenadas pegaria.
## Aqui a textura é sintética (metade de cima vermelha, de baixo azul) justamente
## para a resposta ser inequívoca.
func _testar_recorte() -> void:
	var img := Image.create(8, 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		img.fill_rect(Rect2i(0, y, 8, 1), Color.RED if y < 8 else Color.BLUE)
	var tex := ImageTexture.create_from_image(img)

	var vp := SubViewport.new()
	vp.size = Vector2i(64, 64)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var cam := Camera3D.new()
	vp.add_child(cam)
	cam.current = true

	var cores: Array[Color] = []
	for offset in [CanetaDS.UV_CIMA, CanetaDS.UV_BAIXO]:
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_texture = tex
		mat.uv1_scale = CanetaDS.UV_ESCALA
		mat.uv1_offset = offset

		var quad := QuadMesh.new()
		quad.size = Vector2(2, 2)
		var mi := MeshInstance3D.new()
		mi.mesh = quad
		mi.material_override = mat
		mi.position = Vector3(0, 0, -2)
		vp.add_child(mi)

		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		cores.append(vp.get_texture().get_image().get_pixel(32, 32))
		mi.queue_free()
		await get_tree().process_frame

	_conferir(cores[0].r > 0.5 and cores[0].b < 0.5,
			"a tela de cima mostra a metade de cima (%s)" % str(cores[0].to_html(false)))
	_conferir(cores[1].b > 0.5 and cores[1].r < 0.5,
			"a de baixo mostra a metade de baixo (%s)" % str(cores[1].to_html(false)))
	_conferir(cores[0] != cores[1], "e as duas não mostram a mesma coisa")

	vp.queue_free()


func _perto(a: float, b: float, descricao: String) -> void:
	_conferir(absf(a - b) <= TOL, "%s (%.3f ≈ %.3f)" % [descricao, a, b])


func _conferir(condicao: bool, descricao: String) -> void:
	_feitas += 1
	if condicao:
		print("  ok   ", descricao)
	else:
		print("  FALHA ", descricao)
		_falhas += 1
