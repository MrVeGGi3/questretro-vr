extends Node
## Prova do menu sem headset: renderiza cada página em PNG, exercita o caminho
## de clique do laser e testa o round-trip de save state.
##
## Precisa de um renderizador de verdade (o headless não desenha em textura),
## mas não precisa de janela visível:
##
##   xvfb-run -a godot --path app res://test_ui.tscn
##   # -> user://ui_<pagina>.png
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
	emu.iniciar("res://cores/snes9x_libretro.so", "res://roms/demo.smc")

	await _renderizar_paginas(cfg, emu)
	await _testar_clique(cfg, emu)
	_testar_save_state(emu)
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
		var img := vp.get_texture().get_image()
		var arquivo := "user://ui_%s.png" % _sem_acento(pagina)
		img.save_png(arquivo)
		print("SALVO ", arquivo, " ", img.get_width(), "x", img.get_height())

	vp.queue_free()


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
	var depois := emu._host.save_state()
	_conferir(depois == antes, "estado restaurado bate byte a byte com o original")

	# E o caminho completo pelo disco, que é o que a página de Saves usa.
	_conferir(emu.gravar_estado(1), "gravar_estado escreve o slot 1")
	_conferir(FileAccess.file_exists(emu.caminho_estado(1)), "arquivo .state existe")
	_conferir(FileAccess.file_exists(emu.caminho_miniatura(1)), "miniatura .png existe")
	for i in 120:
		emu.step()
	_conferir(emu.carregar_estado(1), "carregar_estado lê o slot 1")
	_conferir(emu._host.save_state() == antes, "slot 1 restaura o mesmo estado")


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
