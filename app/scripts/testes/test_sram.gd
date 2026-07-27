extends Node
## Prova que o save de bateria chega ao disco e volta — a camada do EmuCore, que
## é a que o jogador sente e a única sem teste.
##
## `test_load.gd` já cobre o nível de baixo (`get_memory`/`set_memory` do
## LibretroHost). O que ninguém tinha conferido é o que vem depois: o timer que
## descobre que a SRAM mudou, o arquivo que ele escreve, e a releitura ao reabrir
## o jogo. É disso que depende o progresso sobreviver a fechar o app.
##
## O ponto sensível é **quando** a gravação acontece. O jogo escreve na bateria
## sem avisar ninguém, então a única forma de saber é comparar de tempos em
## tempos (`EmuCore.INTERVALO_SRAM`) — e esse intervalo é o teto do que se perde
## se o app morrer. No Quest ele morre bastante: o Godot segfalta ao ser pausado,
## que é o que acontece ao tirar o headset (`docs/EXPORT.md`). Por isso o teste
## não só confere que grava, mas **mede** quanto tempo levou.
##
## Roda como cena, e não com `-s`, para que uma ROM de N64 possa entrar depois:
## lá o vídeo é por GPU e no headless o FBO não sobe.
##
##   xvfb-run -a godot --xr-mode off --path app res://cenas/test_sram.tscn -- \
##       --rom "/caminho/jogo.sfc"

## Margem sobre o INTERVALO_SRAM antes de desistir de esperar a gravação.
const ESPERA_EXTRA := 5.0

## Quantos bytes alterar para simular o jogo salvando. O suficiente para a
## comparação não passar por acaso.
const BYTES_ALTERADOS := 64

var _falhas := 0
var _srm := ""      ## caminho do .srm deste jogo
var _bak := ""      ## backup do .srm que já existia, se existia


func _ready() -> void:
	var rom := _arg("--rom", "")
	if rom.is_empty():
		printerr("FALHA: passe --rom")
		get_tree().quit(2)
		return

	await _testar(rom)

	# Sempre, inclusive depois de falhar no meio: o teste não pode ser o motivo
	# de alguém perder um save.
	_restaurar_backup()

	print("=== %s ===" % ("TUDO OK" if _falhas == 0 else "%d FALHA(S)" % _falhas))
	get_tree().quit(1 if _falhas > 0 else 0)


func _testar(rom: String) -> void:
	print("\n--- %s" % rom.get_file())

	var emu := EmuCore.new()
	add_child(emu)
	emu.falhou.connect(func(msg: String) -> void: print("       (falhou: %s)" % msg))

	if not _checar(emu.iniciar("", rom), "abrir a ROM"):
		return

	# Antes de qualquer coisa que escreva. O caminho sai do nome da ROM, então sem
	# isto rodar o teste com um jogo de verdade apagaria o save do jogador.
	_srm = emu.caminho_sram()
	_fazer_backup()

	if not _checar(emu.tamanho_sram() > 0,
			"o cartucho tem bateria (sem isso o teste não diz nada)"):
		return
	print("       bateria: %d bytes · %s" % [emu.tamanho_sram(), _srm])

	var em_disco_antes := _ler(_srm)

	# O jogador salvando dentro do jogo: o core escreve na SRAM viva e ninguém é
	# avisado. Alterar por set_memory é a mesma coisa vista de fora.
	var alterado := _alterar(emu)
	if not _checar(not alterado.is_empty(), "alterar a SRAM viva"):
		return

	# A janela existe, e é isto que a torna visível: acabou de salvar e o disco
	# ainda tem o conteúdo velho.
	_checar(_ler(_srm) == em_disco_antes,
			"logo depois de salvar, o disco ainda tem o conteúdo antigo")

	# E o gatilho de que tudo depende hoje. O tempo medido é o que se perde num
	# crash — o número que justifica (ou não) mexer no INTERVALO_SRAM.
	var demorou := await _esperar_gravacao(alterado, EmuCore.INTERVALO_SRAM + ESPERA_EXTRA)
	if _checar(demorou >= 0.0, "o timer periódico gravou a SRAM em disco"):
		print("       gravou %.1f s depois de salvar (INTERVALO_SRAM = %.0f s)" % [
			demorou, EmuCore.INTERVALO_SRAM])

	# Sem mudança não se toca no disco: é o que torna barato checar com frequência.
	_checar(not emu.gravar_sram(), "sem mudança nenhuma, não reescreve")

	# Um .tmp largado por uma morte anterior no meio da escrita não pode
	# atrapalhar a próxima — a gravação é atômica justamente para isso.
	var tmp := _srm + ".tmp"
	var lixo := FileAccess.open(tmp, FileAccess.WRITE)
	if lixo != null:
		lixo.store_string("restos de uma gravação interrompida")
		lixo.close()
	var alterado2 := _alterar(emu)
	_checar(emu.gravar_sram(), "grava por cima de um .tmp órfão")
	_checar(_ler(_srm) == alterado2, "e o conteúdo em disco é o novo")
	_checar(not FileAccess.file_exists(tmp), "o .tmp não fica para trás")

	# Reabrir o jogo é a outra metade da promessa: de nada adianta gravar se a
	# releitura não devolve. Um EmuCore de cada vez — o LibretroHost roteia os
	# callbacks do core para uma única instância viva.
	emu.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

	var emu2 := EmuCore.new()
	add_child(emu2)
	emu2.falhou.connect(func(msg: String) -> void: print("       (falhou: %s)" % msg))
	if _checar(emu2.iniciar("", rom), "reabrir a ROM"):
		var relido: PackedByteArray = emu2._host.get_memory(LibretroHost.MEMORY_SAVE_RAM)
		_checar(relido == alterado2, "reabrir devolve a bateria gravada ao core")
	emu2.queue_free()
	await get_tree().process_frame


## Altera os primeiros bytes da SRAM viva e devolve o buffer inteiro como ficou.
func _alterar(emu: EmuCore) -> PackedByteArray:
	var vivo: PackedByteArray = emu._host.get_memory(LibretroHost.MEMORY_SAVE_RAM)
	if vivo.is_empty():
		return PackedByteArray()
	var novo := vivo.duplicate()
	for i in mini(BYTES_ALTERADOS, novo.size()):
		novo[i] = (novo[i] + 1) % 256
	if not emu._host.set_memory(LibretroHost.MEMORY_SAVE_RAM, novo):
		return PackedByteArray()
	return novo


## Espera o conteúdo esperado aparecer no arquivo. Devolve quantos segundos
## levou, ou -1 se estourou o limite. Não chama `step()` de propósito: o jogo
## rodando reescreveria a SRAM que acabamos de plantar.
func _esperar_gravacao(esperado: PackedByteArray, limite: float) -> float:
	var t0 := Time.get_ticks_msec()
	while (Time.get_ticks_msec() - t0) / 1000.0 < limite:
		await get_tree().process_frame
		if _ler(_srm) == esperado:
			return (Time.get_ticks_msec() - t0) / 1000.0
	return -1.0


func _ler(caminho: String) -> PackedByteArray:
	var f := FileAccess.open(caminho, FileAccess.READ)
	if f == null:
		return PackedByteArray()
	var dados := f.get_buffer(f.get_length())
	f.close()
	return dados


func _fazer_backup() -> void:
	if not FileAccess.file_exists(_srm):
		return
	_bak = _srm + ".bak-teste"
	var dados := _ler(_srm)
	var f := FileAccess.open(_bak, FileAccess.WRITE)
	if f == null:
		# Sem backup seguro, é melhor não rodar do que arriscar o save.
		printerr("FALHA: não consegui fazer backup de " + _srm)
		_falhas += 1
		_bak = ""
		return
	f.store_buffer(dados)
	f.close()
	print("       backup do save existente em %s" % _bak.get_file())


func _restaurar_backup() -> void:
	var tmp := _srm + ".tmp"
	if FileAccess.file_exists(tmp):
		DirAccess.remove_absolute(tmp)
	if _bak.is_empty():
		# Não havia save antes: o certo é não deixar um.
		if FileAccess.file_exists(_srm):
			DirAccess.remove_absolute(_srm)
		return
	var dados := _ler(_bak)
	var f := FileAccess.open(_srm, FileAccess.WRITE)
	if f != null:
		f.store_buffer(dados)
		f.close()
		DirAccess.remove_absolute(_bak)
		print("       save original devolvido")
	else:
		printerr("ATENÇÃO: o save original ficou só em " + _bak)


func _checar(ok: bool, o_que: String) -> bool:
	if ok:
		print("  ok   %s" % o_que)
	else:
		printerr("  FALHA %s" % o_que)
		_falhas += 1
	return ok


func _arg(nome: String, padrao: String) -> String:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size() - 1):
		if args[i] == nome:
			return args[i + 1]
	return padrao
