extends Node
## Prova do menu sem headset: renderiza cada página em PNG, exercita o caminho
## de clique do laser e testa o round-trip de save state.
##
## Precisa de um renderizador de verdade (o headless não desenha em textura),
## mas não precisa de janela visível:
##
##   xvfb-run -a godot --xr-mode off --path app res://cenas/test_ui.tscn
##   # -> user://ui_<pagina>.png
##
## O `--xr-mode off` não é opcional: o projeto liga OpenXR, e sem um runtime
## ativo na máquina o Godot trava no arranque sob Xvfb, sem imprimir nada.
##
## Roda como cena, e não com `-s`, porque scripts de MainLoop travam na
## inicialização nesta versão do Godot com a GDExtension carregada.

const PAGINAS := ["ROMs", "Tela", "Vídeo", "Áudio", "Input", "Saves"]

var _falhas := 0


func _ready() -> void:
	var cfg := ConfigEmu.new()
	add_child(cfg)

	var emu := EmuCore.new()
	add_child(emu)
	# Uma ROM de verdade deixa a página de Saves e o cabeçalho de Vídeo com
	# conteúdo real em vez de estado vazio.
	# `-- --rom /caminho/jogo.sfc` troca a ROM: útil para ver a página de Saves
	# com um cartucho que tem bateria — a demo não tem.
	# Core vazio: sai da extensão da ROM. Com o caminho do snes9x fixo aqui,
	# passar uma .z64 renderizava a página de Input do N64 com o core errado —
	# e é justamente essa página que muda mais com o sistema.
	emu.iniciar("", _arg("--rom", "res://roms/demo.smc"))

	await _renderizar_paginas(cfg, emu)
	await _testar_clique(cfg, emu)
	await _testar_rolagem(cfg, emu)
	await _testar_oclusao(cfg, emu)
	_testar_save_state(emu)
	await _testar_apagar_estado(cfg, emu)
	_testar_persistencia(cfg)

	print("=== %s ===" % ("TUDO OK" if _falhas == 0 else "%d FALHA(S)" % _falhas))
	get_tree().quit(1 if _falhas > 0 else 0)


## Cada página vira um PNG — é o que pega texto estourando, alvo pequeno demais
## ou container que não expande, sem precisar de build + sideload.
func _renderizar_paginas(cfg: ConfigEmu, emu: EmuCore) -> void:
	var vp := SubViewport.new()
	vp.size = TemaVR.PAINEL
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)

	var menu := MenuRaiz.new(cfg, emu)
	vp.add_child(menu)

	for pagina in PAGINAS:
		menu.mostrar(pagina)
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		await _salvar(vp, _sem_acento(pagina))

		# Página que não cabe também precisa ser vista por baixo: é lá que mora
		# o que foi acrescentado por último, e um PNG só do topo não mostraria
		# texto estourando no fim da página.
		var rolagem := _achar_scroll(menu)
		if rolagem != null and rolagem.get_v_scroll_bar().max_value > rolagem.size.y:
			rolagem.scroll_vertical = int(rolagem.get_v_scroll_bar().max_value)
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			await _salvar(vp, _sem_acento(pagina) + "_fim")
			rolagem.scroll_vertical = 0

	vp.queue_free()


func _salvar(vp: SubViewport, nome: String) -> void:
	var img := vp.get_texture().get_image()
	var arquivo := "user://ui_%s.png" % nome
	img.save_png(arquivo)
	print("SALVO ", arquivo, " ", img.get_width(), "x", img.get_height())


## O laser em VR vira exatamente isto: mouse motion + clique empurrados no
## SubViewport. Se um botão não responde aqui, também não responde no headset.
func _testar_clique(cfg: ConfigEmu, emu: EmuCore) -> void:
	var painel := PainelMenu.new(cfg, emu)
	add_child(painel)
	painel.abrir()
	await get_tree().process_frame
	await get_tree().process_frame

	# Pergunta ao próprio botão onde ele está, em vez de recalcular o layout:
	# assim o teste confere o mapeamento de coordenadas, não a minha aritmética.
	for alvo_nome in ["Áudio", "Saves", "ROMs"]:
		var bt: Button = painel.menu._botoes[alvo_nome]
		_clicar(painel, bt.get_global_rect().get_center())
		await get_tree().process_frame
		var ativa := _pagina_visivel(painel.menu)
		_conferir(ativa == alvo_nome,
				"clique em '%s' na sidebar abre a página (deu '%s')" % [alvo_nome, ativa])

	painel.queue_free()


## O conteúdo abaixo da dobra tem que ser alcançável. No headset o laser só
## emitia movimento e clique, então nada que passasse da altura da tela dava
## para ler — e a página de Input do N64 não cabe inteira em tela nenhuma.
## Este teste confere o outro lado do conserto: que a roda chega ao
## ScrollContainer do PagBase. O lado do thumbstick (`PainelMenu._rolar`) só o
## headset exercita.
func _testar_rolagem(cfg: ConfigEmu, emu: EmuCore) -> void:
	var painel := PainelMenu.new(cfg, emu)
	add_child(painel)
	painel.abrir()
	painel.menu.mostrar("Input")
	await get_tree().process_frame
	await get_tree().process_frame

	var rolagem := _achar_scroll(painel.menu)
	if rolagem == null:
		_conferir(false, "achei o ScrollContainer da página")
		painel.queue_free()
		return

	_conferir(rolagem.get_v_scroll_bar().max_value > rolagem.size.y,
			"a página de Input tem mais conteúdo do que cabe (é o caso que importa)")

	var antes := rolagem.scroll_vertical
	for i in 5:
		_rodar(painel, MOUSE_BUTTON_WHEEL_DOWN)
		await get_tree().process_frame
	_conferir(rolagem.scroll_vertical > antes,
			"roda para baixo rola a página (%d -> %d)" % [antes, rolagem.scroll_vertical])

	var desceu := rolagem.scroll_vertical
	for i in 10:
		_rodar(painel, MOUSE_BUTTON_WHEEL_UP)
		await get_tree().process_frame
	_conferir(rolagem.scroll_vertical < desceu, "roda para cima volta")

	painel.queue_free()


func _rodar(painel: PainelMenu, botao: int) -> void:
	for apertado in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = botao
		ev.pressed = apertado
		ev.position = TemaVR.PAINEL * 0.5
		ev.global_position = ev.position
		painel.entrada_desktop(ev)


func _achar_scroll(no: Node) -> ScrollContainer:
	if no is ScrollContainer and (no as Control).is_visible_in_tree():
		return no
	for filho in no.get_children():
		var achou := _achar_scroll(filho)
		if achou != null:
			return achou
	return null




func _clicar(painel: PainelMenu, pos: Vector2) -> void:
	var mover := InputEventMouseMotion.new()
	mover.position = pos
	mover.global_position = pos
	painel.entrada_desktop(mover)
	for apertado in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = apertado
		ev.position = pos
		ev.global_position = pos
		painel.entrada_desktop(ev)


func _pagina_visivel(menu: MenuRaiz) -> String:
	for nome in PAGINAS:
		if menu._paginas[nome].visible:
			return nome
	return "<nenhuma>"


## Reproduz a predefinição "Portátil": a tela do emulador a 1,0 m e o painel a
## 1,6 m, ou seja, a tela fisicamente na frente do menu. O painel tem que
## continuar visível — é o que o no_depth_test garante.
func _testar_oclusao(cfg: ConfigEmu, emu: EmuCore) -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(640, 400)
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)

	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.4, 0)
	vp.add_child(cam)

	# A "tela do emulador": quad opaco e bem maior que o painel, mais perto.
	var barreira := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(4, 3)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color.RED
	quad.material = mat
	barreira.mesh = quad
	barreira.position = Vector3(0, 1.4, -1.0)
	vp.add_child(barreira)

	var painel := PainelMenu.new(cfg, emu)
	vp.add_child(painel)
	painel.abrir()
	painel.global_position = Vector3(0, 1.4, -1.6)

	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var img := vp.get_texture().get_image()
	img.save_png("user://ui_oclusao.png")

	# No centro da imagem, o painel cobre a barreira. Se o vermelho dominar, a
	# tela venceu o teste de profundidade e o menu está invisível.
	var vermelhos := 0
	var total := 0
	for y in range(150, 250, 5):
		for x in range(250, 390, 5):
			var c := img.get_pixel(x, y)
			total += 1
			if c.r > 0.5 and c.g < 0.2 and c.b < 0.2:
				vermelhos += 1
	_conferir(vermelhos == 0,
			"painel visível com a tela na frente (%d/%d pixels tapados)" % [vermelhos, total])

	vp.queue_free()


## Round-trip do retro_serialize recém-bindado: gravar, avançar o jogo, voltar
## e conferir que o estado bate byte a byte com o original.
func _testar_save_state(emu: EmuCore) -> void:
	if not emu.suporta_estado():
		print("PULADO: o core não implementa save states")
		return

	for i in 60:
		emu.step()
	var antes := emu._host.save_state()
	_conferir(not antes.is_empty(), "save_state devolve dados (%d bytes)" % antes.size())

	for i in 120:
		emu.step()
	var divergiu := emu._host.save_state()
	_conferir(divergiu != antes, "o jogo realmente avançou depois de gravar")

	_conferir(emu._host.load_state(antes), "load_state aceita o estado gravado")

	# Comparar estados byte a byte só diz alguma coisa se o core for
	# determinístico sob o nosso step(). O mupen64plus não é: ele roda uma
	# EmuThread própria, e refazer o mesmo trecho a partir do mesmo estado
	# restaurado produz bytes diferentes. Aí a comparação não distingue uma
	# restauração ruim de um core que simplesmente não repete — medido, não
	# suposto (ver docs/EXPORT.md).
	var deterministico := emu.sistema != "n64"
	if not deterministico:
		print("PULADO: %s não repete byte a byte; quem confere o N64 é o test_estado, "
				% emu.sistema + "que compara a imagem em vez dos bytes")
	if deterministico:
		var depois := emu._host.save_state()
		_conferir(depois == antes, "estado restaurado bate byte a byte com o original")

	# E o caminho completo pelo disco, que é o que a página de Saves usa.
	_conferir(emu.gravar_estado(1), "gravar_estado escreve o slot 1")
	_conferir(FileAccess.file_exists(emu.caminho_estado(1)), "arquivo .state existe")
	_conferir(FileAccess.file_exists(emu.caminho_miniatura(1)), "miniatura .png existe")
	for i in 120:
		emu.step()
	_conferir(emu.carregar_estado(1), "carregar_estado lê o slot 1")
	if deterministico:
		_conferir(emu._host.save_state() == antes, "slot 1 restaura o mesmo estado")


## Apagar um slot pede duas batidas, e é a **primeira** que este teste protege:
## ela não pode apagar nada. É a única defesa contra um laser que escorregou para
## o botão errado, e um save state apagado não tem desfazer. Uma regressão aqui
## não apareceria em PNG nenhum — só na primeira vez que alguém perdesse um save.
func _testar_apagar_estado(cfg: ConfigEmu, emu: EmuCore) -> void:
	if not emu.suporta_estado():
		print("PULADO: o core não implementa save states")
		return

	_conferir(emu.gravar_estado(2), "gravou o slot 2 para ter o que apagar")
	var estado := emu.caminho_estado(2)
	var png := emu.caminho_miniatura(2)

	var vp := SubViewport.new()
	vp.size = TemaVR.PAINEL
	add_child(vp)
	var menu := MenuRaiz.new(cfg, emu)
	vp.add_child(menu)
	menu.mostrar("Saves")
	await get_tree().process_frame

	# Pelo nome, e não pelo texto: os quatro botões dizem "Apagar", e procurar por
	# texto acha o do slot 1 — foi assim que este teste nasceu errado, armando um
	# slot e conferindo os arquivos de outro.
	var bt := menu.find_child("ApagarSlot2", true, false) as Button
	if bt == null:
		_conferir(false, "achei o botão Apagar do slot 2")
		vp.queue_free()
		return

	bt.pressed.emit()
	await get_tree().process_frame
	_conferir(FileAccess.file_exists(estado), "uma batida só NÃO apaga")
	_conferir(bt.text == "Confirmar?", "e o botão passa a perguntar")

	bt.pressed.emit()
	await get_tree().process_frame
	_conferir(not FileAccess.file_exists(estado), "a segunda batida apaga o estado")
	_conferir(not FileAccess.file_exists(png), "e leva a miniatura junto")
	_conferir(not emu.apagar_estado(2), "apagar slot vazio devolve false, não finge")

	vp.queue_free()
	await get_tree().process_frame


## A promessa do ConfigEmu é sobreviver ao fechamento do app, então o teste
## grava, cria uma instância nova e relê — não basta conferir o dicionário.
func _testar_persistencia(cfg: ConfigEmu) -> void:
	cfg.definir("tela/escala", 3.33)
	cfg.definir("audio/mudo", true)
	cfg.definir("video/aspecto", ConfigEmu.ASPECTO_16_9)
	cfg.salvar()

	var relido := ConfigEmu.new()
	relido.carregar()
	_conferir(is_equal_approx(relido.obter("tela/escala"), 3.33), "float persiste")
	_conferir(relido.obter("audio/mudo") == true, "bool persiste")
	_conferir(int(relido.obter("video/aspecto")) == ConfigEmu.ASPECTO_16_9, "enum persiste")

	relido.restaurar("tela")
	_conferir(is_equal_approx(relido.obter("tela/escala"),
			ConfigEmu.PADROES["tela/escala"]), "restaurar volta ao padrão")
	relido.free()

	# Não deixa o config de teste sujando a próxima execução do app.
	DirAccess.remove_absolute(ConfigEmu.ARQUIVO)


func _conferir(condicao: bool, descricao: String) -> void:
	if condicao:
		print("  ok   ", descricao)
	else:
		print("  FALHA ", descricao)
		_falhas += 1


func _sem_acento(s: String) -> String:
	return s.to_lower().replace("í", "i").replace("á", "a")


func _arg(nome: String, padrao: String) -> String:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size() - 1):
		if args[i] == nome:
			return args[i + 1]
	return padrao
