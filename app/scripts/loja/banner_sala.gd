extends SceneTree
## Renderiza o salão de arcade em proporção de banner, para a página da itch.io.
##
## Roda por `-s`, sem cena e sem headset:
##
##   godot --headless --xr-mode off --path app -s res://scripts/loja/banner_sala.gd
##
## Existe para a arte da loja ser o **salão de verdade**, e não um desenho que
## se parece com ele. O que a página promete ("um fliperama que cabe no seu
## quarto") é exatamente o que esta imagem mostra, porque é o mesmo código que
## roda no headset — o `Sala.aplicar(Sala.FLIPERAMA)` aqui é o do jogo.
##
## Sai em `user://`, junto das capturas dos testes. Não versionamos as saídas:
## são geradas, e PNG versionado já custou uma reescrita de histórico neste repo.

## Padrão: proporção de banner da itch (1920 de largura é o que cobre as telas
## comuns). Outro tamanho vem por argumento, depois de `--`:
##
##   ... -s res://scripts/loja/banner_sala.gd -- --tamanho 1920x1080 --nome fundo
const LARGURA_PADRAO := 1920
const ALTURA_PADRAO := 480

## Câmera baixa e recuada, olhando o fundo do salão. Mais baixa que a vista
## "jogador" do teste de propósito: em faixa larga o teto domina o quadro, e o
## que se quer ver é o corredor de gabinetes fugindo para o fundo.
const OLHO := Vector3(0.0, 1.35, 3.2)
const ALVO := Vector3(0.0, 1.30, -7.0)

## Campo de visão maior que o padrão, porque a faixa é larga e o corte vertical
## já é agressivo. Com 75 a parede lateral some e sobra um túnel preto.
const FOV := 95.0


## Lê `--tamanho LxA` e `--nome X` de depois do `--`. Sem eles, os padrões.
func _argumentos() -> Dictionary:
	var arg := {"tamanho": Vector2i(LARGURA_PADRAO, ALTURA_PADRAO), "nome": "banner_sala"}
	var lista := OS.get_cmdline_user_args()
	for i in lista.size():
		if lista[i] == "--tamanho" and i + 1 < lista.size():
			var partes := lista[i + 1].split("x")
			if partes.size() == 2 and partes[0].is_valid_int() and partes[1].is_valid_int():
				arg["tamanho"] = Vector2i(int(partes[0]), int(partes[1]))
			else:
				printerr("--tamanho espera LARGURAxALTURA, veio: ", lista[i + 1])
		elif lista[i] == "--nome" and i + 1 < lista.size():
			arg["nome"] = lista[i + 1]
	return arg


func _initialize() -> void:
	var arg := _argumentos()
	var vp := SubViewport.new()
	vp.size = arg["tamanho"]
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.transparent_bg = false
	root.add_child(vp)

	var sala := Sala.new()
	vp.add_child(sala)
	sala.aplicar(Sala.FLIPERAMA)

	var cam := Camera3D.new()
	vp.add_child(cam)
	cam.fov = FOV
	cam.current = true

	# Posicionar **depois** de um frame: em `_initialize` os nós recém-criados
	# ainda não estão na árvore, e `look_at` recusa com "Node not inside tree" —
	# um erro que **não** aborta o script. A imagem sai, com a câmera na origem
	# olhando para o vazio, e parece só um enquadramento ruim.
	await process_frame
	cam.global_position = OLHO
	cam.look_at(ALVO)

	# Dois frames antes do `frame_post_draw`, como no teste da sala: com um só, o
	# alvo do viewport sai preto de vez em quando, e o erro é intermitente — o
	# tipo que se descobre no dia em que a arte final sai vazia.
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw

	var img := vp.get_texture().get_image()
	var arquivo := "user://%s.png" % arg["nome"]
	img.save_png(arquivo)
	print("SALVO ", arquivo, " ", img.get_width(), "x", img.get_height())

	# Uma imagem preta é o desfecho provável de erro de câmera ou de normal, e
	# passaria despercebida num arquivo que ninguém abre antes de subir.
	var acesos := 0
	for y in range(0, img.get_height(), 4):
		for x in range(0, img.get_width(), 4):
			if img.get_pixel(x, y).get_luminance() > 0.04:
				acesos += 1
	var fracao := float(acesos) / float((img.get_width() / 4) * (img.get_height() / 4))
	print("fração acesa: %.1f%%" % (fracao * 100.0))
	if fracao < 0.02:
		printerr("banner saiu praticamente preto — confira câmera e FOV")
		quit(1)
		return

	quit(0)
