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

const PAGINAS := ["ROMs", "Tela", "Sala", "Vídeo", "Áudio", "Input", "Saves"]

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
	_testar_perfil()
	await _testar_botao_perfil(cfg, emu)
	_testar_combinar()
	await _testar_remap(cfg, emu)
	_testar_sistemas_completos()

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
	# Guardado antes de apagar: o desfazer só vale alguma coisa se devolver
	# **estes** bytes. Um desfazer que recria um arquivo vazio passaria em
	# qualquer asserção de existência.
	var antes := FileAccess.get_file_as_bytes(estado)

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

	# O que apaga move para a lixeira, e é isso que torna o engano reversível.
	# Sem esta parte, "apagar" e "apagar de verdade" seriam indistinguíveis daqui.
	_conferir(emu.tem_na_lixeira(2), "o apagado foi para a lixeira")

	menu.mostrar("Saves")
	await get_tree().process_frame
	var bt_undo := menu.find_child("DesfazerSlot2", true, false) as Button
	_conferir(bt_undo != null, "o slot vazio oferece Desfazer")
	if bt_undo != null:
		bt_undo.pressed.emit()
		await get_tree().process_frame

	_conferir(FileAccess.file_exists(estado), "desfazer devolve o estado")
	_conferir(FileAccess.file_exists(png), "e a miniatura junto")
	_conferir(FileAccess.get_file_as_bytes(estado) == antes,
			"e são os mesmos bytes, não um arquivo novo")
	_conferir(not emu.tem_na_lixeira(2), "a lixeira fica vazia depois de desfazer")
	_conferir(not emu.desfazer_apagar(2),
			"desfazer sem nada na lixeira devolve false")

	# Slot reocupado não aceita desfazer: seria trocar um engano por outro.
	_conferir(emu.apagar_estado(2), "apaga de novo")
	_conferir(emu.gravar_estado(2), "e o slot volta a ser ocupado por cima")
	_conferir(not emu.desfazer_apagar(2),
			"com o slot ocupado, desfazer se recusa")

	emu.apagar_estado(2)
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


## Perfil de controle por cartucho. O que este teste protege não aparece em PNG
## nenhum: que ajustar o guidão de um jogo **não** vaza para os outros. Sem ele,
## a regressão só apareceria no headset, com o Mario 64 herdando o manche do
## Star Fox — e depois de dez minutos de export.
func _testar_perfil() -> void:
	var c := ConfigEmu.new()
	c.carregar()
	c.definir("input/guidao_curva", 1.4)   # geral, com nenhum jogo ativo

	c.usar_perfil("teste_a")
	_conferir(not c.tem_perfil(), "jogo sem arquivo de perfil segue o geral")
	c.criar_perfil()
	_conferir(c.tem_perfil(), "criar_perfil liga o perfil")
	# Ligar não pode mudar o comportamento no mesmo instante: o perfil nasce
	# copiando o que a pessoa já estava sentindo.
	_conferir(is_equal_approx(c.obter("input/guidao_curva"), 1.4),
			"o perfil nasce igual ao geral")

	c.definir("input/guidao_curva", 2.5)
	c.definir("tela/escala", 2.2)          # não é input: vai para o geral
	c.salvar()

	c.usar_perfil("teste_b")
	_conferir(is_equal_approx(c.obter("input/guidao_curva"), 1.4),
			"outro cartucho NÃO herda o ajuste do primeiro")
	_conferir(not c.tem_perfil(), "e continua sem perfil próprio")

	# O sinal é o mecanismo inteiro: é por ele que a cena reaplica o guidão ao
	# trocar de jogo. Sem ele o perfil estaria certo no disco e errado no ar.
	var vistas: Array[String] = []
	c.mudou.connect(func(k: String, _v: Variant) -> void: vistas.append(k))
	c.usar_perfil("teste_a")
	_conferir("input/guidao_curva" in vistas, "trocar de cartucho avisa quem escuta")
	_conferir(is_equal_approx(c.obter("input/guidao_curva"), 2.5), "e devolve o ajuste do jogo")

	# Relê do disco com uma instância nova: a promessa é sobreviver ao app.
	var d := ConfigEmu.new()
	d.carregar()
	d.usar_perfil("teste_a")
	_conferir(is_equal_approx(d.obter("input/guidao_curva"), 2.5), "o perfil persiste em disco")

	var arq := ConfigFile.new()
	_conferir(arq.load(c.caminho_perfil("teste_a")) == OK, "o perfil virou arquivo")
	_conferir(arq.has_section_key("input", "guidao_curva"), "o arquivo do perfil guarda input")
	_conferir(not arq.has_section("tela"), "e não guarda tela — perfil é só de controle")
	_conferir(is_equal_approx(d.obter("tela/escala"), 2.2), "a escala foi para o geral")

	c.apagar_perfil()
	_conferir(not c.tem_perfil(), "apagar desliga o perfil")
	_conferir(is_equal_approx(c.obter("input/guidao_curva"), 1.4), "e o jogo volta ao geral")
	_conferir(not FileAccess.file_exists(c.caminho_perfil("teste_a")), "o arquivo some junto")

	d.free()
	c.free()
	DirAccess.remove_absolute(ConfigEmu.ARQUIVO)


## A outra metade: o botão da página de Input. Apagar um perfil não tem desfazer,
## então a primeira batida não pode apagar nada — mesmo contrato dos saves.
func _testar_botao_perfil(cfg: ConfigEmu, emu: EmuCore) -> void:
	# Quem roda o teste pode ter um perfil de verdade para esta ROM. Guarda e
	# devolve: testar perfil destruindo o perfil de alguém seria irônico demais.
	cfg.usar_perfil(emu.id_rom())
	var arquivo := cfg.caminho_perfil(emu.id_rom())
	var backup := PackedByteArray()
	if FileAccess.file_exists(arquivo):
		backup = FileAccess.get_file_as_bytes(arquivo)
		cfg.apagar_perfil()

	var vp := SubViewport.new()
	vp.size = TemaVR.PAINEL
	add_child(vp)
	var menu := MenuRaiz.new(cfg, emu)
	vp.add_child(menu)
	menu.mostrar("Input")
	await get_tree().process_frame

	var bt := menu.find_child("PerfilJogo", true, false) as Button
	if bt == null:
		_conferir(false, "achei o botão de perfil na página de Input")
		vp.queue_free()
		return

	bt.pressed.emit()
	await get_tree().process_frame
	_conferir(cfg.tem_perfil(), "o botão cria o perfil deste jogo")
	_conferir(FileAccess.file_exists(arquivo), "e o arquivo aparece na pasta")

	bt.pressed.emit()
	await get_tree().process_frame
	_conferir(cfg.tem_perfil(), "uma batida só NÃO apaga o perfil")
	_conferir(bt.text == "Apagar mesmo?", "e o botão passa a perguntar")

	bt.pressed.emit()
	await get_tree().process_frame
	_conferir(not cfg.tem_perfil(), "a segunda batida apaga")
	_conferir(not FileAccess.file_exists(arquivo), "e o arquivo some")

	vp.queue_free()
	await get_tree().process_frame

	if not backup.is_empty():
		var f := FileAccess.open(arquivo, FileAccess.WRITE)
		if f != null:
			f.store_buffer(backup)
			f.close()


## A conta do mapa, sem XR nenhum — é para isso que ela mora no MapaInput e não
## dentro do xr_main. O que ela protege é o que dá para errar em silêncio: um
## botão que fica preso depois de deixar de ser mapeado, e duas origens no mesmo
## destino em que uma anula a outra.
func _testar_combinar() -> void:
	var mapa := {"dir_ax": LibretroHost.JOYPAD_A, "esq_grip": LibretroHost.JOYPAD_SELECT}

	var e := MapaInput.combinar(mapa, {"dir_ax": true}, {})
	_conferir(e[LibretroHost.JOYPAD_A] == true, "a origem pressionada chega no destino")
	_conferir(e[LibretroHost.JOYPAD_SELECT] == false, "a origem solta não")
	_conferir(e.size() == MapaInput.IDS, "todos os ids saem definidos, não só os mapeados")
	_conferir(e[LibretroHost.JOYPAD_R] == false,
			"id fora do mapa sai zerado — é o que impede botão preso após remap")

	# Duas origens no mesmo destino somam. A alternativa (a última ganha) faria
	# uma das duas não fazer nada, sem avisar ninguém.
	var dois := {"esq_trigger": LibretroHost.JOYPAD_L, "dir_trigger": LibretroHost.JOYPAD_L}
	var s := MapaInput.combinar(dois, {"esq_trigger": false, "dir_trigger": true}, {})
	_conferir(s[LibretroHost.JOYPAD_L] == true, "duas origens no mesmo destino somam")

	# "Nada" desliga a origem sem tirá-la da lista.
	var nada := MapaInput.combinar({"dir_ax": MapaInput.NADA}, {"dir_ax": true}, {})
	_conferir(nada[LibretroHost.JOYPAD_A] == false, "origem em 'Nada' não manda nada")

	# O que vem por fora (as direções do analógico no SNES) sobrevive ao mapa.
	var pre := MapaInput.combinar(mapa, {}, {LibretroHost.JOYPAD_LEFT: true})
	_conferir(pre[LibretroHost.JOYPAD_LEFT] == true, "as direções do analógico passam inteiras")


## O remap pela página: tocar na linha abre os destinos, tocar num destino grava.
## E — o ponto de tudo isto — o que ele grava vai para o perfil do cartucho, sem
## mexer no mapa dos outros jogos.
func _testar_remap(cfg: ConfigEmu, emu: EmuCore) -> void:
	# O sistema vem da ROM carregada, e não fixo: a página mostra o mapa do
	# console em execução, e um teste que olhasse sempre a chave do SNES passaria
	# no caminho comum e reprovaria com uma ROM de N64 — foi o que aconteceu.
	var sistema := emu.sistema if not emu.sistema.is_empty() else "snes"
	var chave := MapaInput.chave(sistema, "dir_ax")
	var antes := int(cfg.obter(chave))

	var vp := SubViewport.new()
	vp.size = TemaVR.PAINEL
	add_child(vp)
	var menu := MenuRaiz.new(cfg, emu)
	vp.add_child(menu)
	menu.mostrar("Input")
	await get_tree().process_frame

	var linha := menu.find_child("Origem_dir_ax", true, false) as Button
	if linha == null:
		_conferir(false, "achei a linha do botão A na página de Input")
		vp.queue_free()
		return

	# Antes do toque não há destino à mostra: a página não pode nascer com oito
	# seletores abertos.
	_conferir(menu.find_child("Destino_dir_ax_1", true, false) == null,
			"os destinos só aparecem depois do toque")

	linha.pressed.emit()
	await get_tree().process_frame
	var alvo := menu.find_child("Destino_dir_ax_%d" % LibretroHost.JOYPAD_Y, true, false) as Button
	if alvo == null:
		_conferir(false, "o toque na linha abriu a lista de destinos")
		vp.queue_free()
		return
	_conferir(true, "o toque na linha abre a lista de destinos")

	# O seletor aberto em PNG: é a única forma de ver se a grade de destinos cabe
	# na largura do painel e se as linhas debaixo foram empurradas para fora.
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await _salvar(vp, "input_remap")

	alvo.pressed.emit()
	await get_tree().process_frame
	_conferir(int(cfg.obter(chave)) == LibretroHost.JOYPAD_Y, "escolher um destino grava o mapa")
	_conferir(menu.find_child("Destino_dir_ax_%d" % LibretroHost.JOYPAD_Y, true, false) == null,
			"e a lista fecha depois de escolher")

	# O que este remap todo existe para fazer: valer só neste cartucho.
	cfg.usar_perfil("teste_remap")
	cfg.criar_perfil()
	cfg.definir(chave, LibretroHost.JOYPAD_X)
	_conferir(int(cfg.obter(chave)) == LibretroHost.JOYPAD_X, "o perfil remapeia por cima do geral")
	cfg.apagar_perfil()
	_conferir(int(cfg.obter(chave)) == LibretroHost.JOYPAD_Y,
			"e apagar o perfil devolve o mapa geral, intacto")

	cfg.definir(chave, antes)
	cfg.usar_perfil(emu.id_rom())
	vp.queue_free()
	await get_tree().process_frame


## Todo sistema que o navegador reconhece precisa das quatro peças: core, nome,
## linhas de eixo e mapa de botões completo.
##
## Acrescentar um sistema toca em quatro arquivos diferentes, e esquecer um deles
## não dá erro nenhum — dá um jogo que abre com o controle morto, ou uma página
## de Input em branco, e só no headset. Este teste é a lista de conferência que
## não depende de eu lembrar dela.
func _testar_sistemas_completos() -> void:
	var sistemas := {}
	for ext: String in NavegadorRoms.SISTEMAS:
		sistemas[NavegadorRoms.SISTEMAS[ext]] = true

	for sis: String in sistemas:
		_conferir(EmuCore.CORES.has(sis), "%s tem core declarado" % sis)
		_conferir(NavegadorRoms.NOMES_SISTEMA.has(sis), "%s tem nome legível" % sis)
		_conferir(PagInput.EIXOS.has(sis), "%s declara as linhas de eixo" % sis)

		if EmuCore.CORES.has(sis):
			for plat: String in ["desktop", "android"]:
				_conferir(EmuCore.CORES[sis].has(plat),
						"%s tem core de %s" % [sis, plat])

		var faltando: Array = []
		for entrada in MapaInput.ORIGENS:
			if not ConfigEmu.PADROES.has(MapaInput.chave(sis, entrada[0])):
				faltando.append(entrada[0])
		_conferir(faltando.is_empty(),
				"%s mapeia as %d origens do Touch (faltam: %s)"
						% [sis, MapaInput.ORIGENS.size(), str(faltando)])


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
