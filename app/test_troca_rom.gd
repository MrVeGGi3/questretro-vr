extends Node
## Prova a regra do RECARREGA_SEMPRE: o mupen64plus não aceita um segundo
## retro_load_game, então trocar para uma ROM de N64 (inclusive a mesma) tem que
## refazer o dlopen do core. Sem isso o jogo não abre e a interface mostra
## "failed to load ROM", que parece ROM corrompida.
##
## Precisa de um renderizador de verdade — o N64 desenha por GPU, e no headless
## o FBO emprestado ao core não sobe. Como o test_ui, roda como cena e não com
## `-s`: scripts de MainLoop travam na inicialização com a GDExtension carregada.
##
## As ROMs não são versionadas, então vêm por argumento:
##
##   xvfb-run -a godot --xr-mode off --path app res://test_troca_rom.tscn -- \
##       --n64 "/caminho/Star Fox 64 (USA).z64" \
##       --n64b "/caminho/Super Mario 64 (USA).z64" \
##       --snes "/caminho/jogo.sfc"

var _falhas := 0


func _ready() -> void:
	var n64 := _arg("--n64", "")
	var n64b := _arg("--n64b", "")
	var snes := _arg("--snes", "")
	if n64.is_empty() or snes.is_empty():
		printerr("FALHA: passe --n64 e --snes (e opcionalmente --n64b)")
		get_tree().quit(2)
		return

	var emu := EmuCore.new()
	add_child(emu)
	emu.falhou.connect(func(msg: String) -> void: print("       (falhou: %s)" % msg))

	# Primeira carga: é o caminho de iniciar(), não o de troca.
	_checar(emu.iniciar("", n64), "iniciar com a ROM de N64")
	await _alguns_frames(emu)

	# Outra ROM de N64 primeiro, e a mesma ROM depois. A ordem importa para o que
	# o teste ensina: uma troca que falha já descarrega o jogo e deixa o core
	# num estado limpo, então a troca seguinte passaria por tabela e esconderia
	# qual das duas regras está em jogo.
	if not n64b.is_empty():
		_checar(emu.trocar_rom(n64b), "trocar para OUTRA ROM de N64")
		await _alguns_frames(emu)

	# O caso que motivou a mudança. Antes do RECARREGA_SEMPRE, o segundo
	# retro_load_game do mupen respondia "failed to load ROM".
	_checar(emu.trocar_rom(n64b if not n64b.is_empty() else n64), "trocar para a MESMA ROM de N64")
	await _alguns_frames(emu)

	# E a troca entre sistemas, que já funcionava, tem que continuar funcionando
	# nos dois sentidos — é o caminho que o RECARREGA_SEMPRE poderia ter quebrado.
	_checar(emu.trocar_rom(snes), "trocar de N64 para SNES")
	await _alguns_frames(emu)
	_checar(emu.trocar_rom(n64), "trocar de SNES de volta para N64")
	await _alguns_frames(emu)

	print("=== %s ===" % ("TUDO OK" if _falhas == 0 else "%d FALHA(S)" % _falhas))
	get_tree().quit(1 if _falhas > 0 else 0)


## Avança alguns frames: um load_rom que "deu certo" mas deixou o core num
## estado ruim aparece aqui, não no valor de retorno. Um process_frame entre os
## steps porque o hw render devolve o alvo de render ao Godot a cada frame.
func _alguns_frames(emu: EmuCore) -> void:
	for f in range(5):
		emu.step()
		await get_tree().process_frame
	print("       %s — %dx%d, hw_render=%s, sram=%d bytes" % [
		emu.rom_atual.get_file(), emu.largura, emu.altura,
		emu.hw_render(), emu.tamanho_sram()])


func _checar(ok: bool, o_que: String) -> void:
	if ok:
		print("  ok   %s" % o_que)
	else:
		printerr("  FALHA %s" % o_que)
		_falhas += 1


func _arg(nome: String, padrao: String) -> String:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size() - 1):
		if args[i] == nome:
			return args[i + 1]
	return padrao
