extends Node
## Confere que restaurar um save state traz o jogo de volta ao ponto gravado —
## no N64, onde a comparação byte a byte não serve.
##
## Por que não comparar os bytes do estado: o mupen64plus roda uma `EmuThread`
## própria, então o nosso `step()` não avança uma quantidade fixa de trabalho e
## dois trechos idênticos produzem blobs diferentes. Uma igualdade que falha ali
## não distingue restauração ruim de core que não repete — é inconclusiva, e por
## isso `test_ui.gd` a pula no N64 (ver docs/EXPORT.md).
##
## O que este teste mede é o que o jogador percebe: **a imagem volta ao que era**.
## Grava o estado, colhe uma janela de frames de referência, segue em frente e
## guarda um frame bem distante (B), restaura e guarda o frame de volta (C). Se a
## restauração funciona, C cai dentro da janela enquanto B está longe dela.
##
## Duas escolhas de desenho que não são detalhe — as duas saíram de o teste ter
## reprovado com a restauração comprovadamente correta:
##
## - **Janela, e não um frame só.** A mesma `EmuThread` que embaralha os bytes
##   também faz os frames depois de restaurar saírem com a animação uns poucos
##   quadros adiantada. O estado volta certo, a fase não. Comparar contra um
##   único instante media esse deslize de fase, não a restauração; comparar
##   contra a janela pergunta a coisa certa — "o frame restaurado aparece na
##   sequência que este estado produz?".
## - **Comparação relativa.** `dist(janela, B)` mede quanto aquele trecho daquele
##   jogo se mexe, e serve de escala, então o limiar não precisa ser calibrado
##   por ROM e nada aqui depende do core repetir byte a byte.
##
## O SNES entra junto como controle. Ele é determinístico e sabidamente restaura
## (resíduo exatamente zero), então reprovar no SNES acusa a métrica, não o
## emulador — foi assim que os dois desenhos acima se corrigiram.
##
## Roda como cena, e não com `-s`: o N64 desenha por GPU e sem contexto de GL o
## FBO emprestado ao core não sobe (mesmo motivo do test_troca_rom). As ROMs não
## são versionadas, então vêm por argumento:
##
##   xvfb-run -a godot --xr-mode off --path app res://cenas/test_estado.tscn -- \
##       --n64 "/caminho/Star Fox 64 (USA).z64" \
##       --snes "/caminho/jogo.sfc"

## Slot alto de propósito: o test_ui usa o 1, e cruzar os dois esconderia qual
## teste escreveu o arquivo que sobrou no disco.
const SLOT := 4

## Frames antes da primeira tentativa: é o tanto que um jogo leva para sair da
## tela preta de boot, e medir ali não diria nada.
const AQUECER_MIN := 300

## Quantos trechos tentar antes de desistir. Cada tentativa consome AVANCAR
## frames, então elas varrem a intro para a frente sem precisar de um número de
## aquecimento por ROM.
const TENTATIVAS := 12

## Quanto o frame restaurado pode estar longe da janela, em múltiplos do que um
## único frame emulado muda. Restaurar não devolve o instante exato — a EmuThread
## do mupen faz cada step() render uma quantidade diferente de trabalho —, então a
## pergunta honesta é se C cai na sequência, com folga de cerca de um frame.
const TOLERANCIA := 1.5

## O quanto B tem que estar além dessa tolerância para o teste ter poder de
## separar as duas coisas. Se não estiver, a cena não serve e o teste diz isso em
## vez de dar um veredito que não sustenta.
const FOLGA := 3.0

## Frames de referência colhidos logo depois de gravar, a partir do **primeiro** —
## do lado da gravação não há frame velho para descartar, e começar depois deixava
## a janela inteira à frente de C, que a jitter do mupen atrasa. 24 quadros ≈
## 0,4 s de jogo, folgado para esse deslize e muito menor que a distância até B,
## que é o que impede a janela de tornar o teste frouxo.
const JANELA := 24

## Frames entre gravar e o frame distante. Precisa ser visível na tela.
const AVANCAR := 180

## O frame seguinte a um load_state ainda é o antigo: o core só redesenha no
## `retro_run` seguinte, e com hw render ainda há o readback do FBO no meio. Vale
## só para o lado da restauração; na gravação a tela já é a do estado gravado.
const REDESENHAR := 3

## Resolução da comparação. Reduzir mata o ruído de um pixel e o custo do laço.
const LARG := 64
const ALT := 48

var _falhas := 0


func _ready() -> void:
	var roms := {
		"snes": _arg("--snes", ""),   # o controle vem primeiro: se ele reprovar,
		"n64": _arg("--n64", ""),     # o que está errado é a métrica
	}
	if roms["n64"].is_empty() and roms["snes"].is_empty():
		printerr("FALHA: passe --n64 e/ou --snes")
		get_tree().quit(2)
		return

	for sistema: String in roms:
		if not roms[sistema].is_empty():
			await _testar(sistema, roms[sistema])

	print("=== %s ===" % ("TUDO OK" if _falhas == 0 else "%d FALHA(S)" % _falhas))
	get_tree().quit(1 if _falhas > 0 else 0)


func _testar(sistema: String, rom: String) -> void:
	print("\n--- %s: %s" % [sistema, rom.get_file()])

	var emu := EmuCore.new()
	add_child(emu)
	emu.falhou.connect(func(msg: String) -> void: print("       (falhou: %s)" % msg))

	if not _checar(emu.iniciar("", rom), "abrir a ROM"):
		emu.queue_free()
		return
	if not _checar(emu.suporta_estado(), "o core implementa save states"):
		emu.queue_free()
		return

	await _avancar(emu, AQUECER_MIN)

	# Tentativas sucessivas até cair num trecho que sustente um veredito. Cada uma
	# grava, mede para a frente e só então decide se aquela cena serve. É o único
	# jeito honesto de escolher o ponto: medindo para trás, o buscador pousava
	# sempre logo depois de um corte de cena — onde a mudança recém-acumulada é
	# enorme e não diz nada sobre os 180 frames seguintes.
	for tentativa in TENTATIVAS:
		# Pelo disco, e não por `_host.save_state()` direto: é este o caminho que
		# a página de Saves usa, com o arquivo e a miniatura no meio.
		if not _checar(emu.gravar_estado(SLOT), "gravar_estado escreve o slot %d" % SLOT):
			break
		if tentativa == 0:
			_checar(FileAccess.file_exists(emu.caminho_estado(SLOT)), "arquivo .state existe")
			_checar(FileAccess.file_exists(emu.caminho_miniatura(SLOT)), "miniatura .png existe")

		var janela := await _colher_janela(emu, sistema)
		if not _checar(not janela.is_empty(), "janela de referência depois do ponto gravado"):
			break

		await _avancar(emu, AVANCAR - JANELA)
		var b := _capturar(emu, sistema, "b")

		# B mede contra a mesma janela que C, senão a escala e o resíduo não
		# seriam a mesma régua.
		var passo := _passo_da_janela(janela)
		var movimento := _dist_janela(janela, b)

		# Sem esta guarda o veredito não se sustenta: se B couber na tolerância,
		# passar não distingue restauração boa de um frame qualquer do trecho — é
		# o modo mais fácil de um teste de imagem mentir. Cena que satura (um
		# fade, uma tela quase parada) cai aqui, e a resposta é seguir em frente e
		# tentar outro trecho, não afrouxar o limiar.
		if movimento <= FOLGA * passo:
			print("       tentativa %d em vão: a cena não separa %d frames (B a %.1f frames)" % [
				tentativa + 1, AVANCAR, movimento / maxf(passo, 0.00001)])
			continue

		if not _checar(emu.carregar_estado(SLOT), "carregar_estado lê o slot %d" % SLOT):
			break
		await _avancar(emu, REDESENHAR)
		var c := _capturar(emu, sistema, "c")
		var residuo := _dist_janela(janela, c)

		print("       um frame muda %.4f · resíduo=%.4f (%.1f frames) · B=%.4f (%.1f frames)" % [
			passo, residuo, residuo / maxf(passo, 0.00001),
			movimento, movimento / maxf(passo, 0.00001)])
		_checar(residuo <= TOLERANCIA * passo,
				"restaurar volta ao ponto gravado (dentro de %.1f frame de folga)" % TOLERANCIA)
		emu.queue_free()
		await get_tree().process_frame
		return

	_checar(false, "algum trecho em %d tentativas sustenta um veredito" % TENTATIVAS)
	emu.queue_free()
	await get_tree().process_frame


## Os primeiros frames depois de gravar. É a "assinatura" daquele estado: qualquer
## um deles é uma volta aceitável.
func _colher_janela(emu: EmuCore, sistema: String) -> Array[Image]:
	var janela: Array[Image] = []
	for i in JANELA:
		var img := _capturar(emu, sistema, "a") if i == 0 else _reduzir(emu)
		if img != null:
			janela.append(img)
		await _avancar(emu, 1)
	return janela


## Quanto a imagem muda de um frame emulado para o seguinte — a granularidade da
## régua. Nenhuma medida pode ser mais fina que isso, então é contra ela que o
## resíduo tem sentido.
##
## Pares idênticos entram na conta como zero de propósito: no N64 o `step()` nem
## sempre produz frame novo (a EmuThread anda no ritmo dela), e contar só os pares
## que mudaram inflaria o passo justamente onde ele precisa ser honesto. O máximo,
## e não a média, porque é o pior caso do que um frame pode deslocar.
func _passo_da_janela(janela: Array[Image]) -> float:
	var maior := 0.0
	for i in range(1, janela.size()):
		maior = maxf(maior, _dist(janela[i - 1], janela[i]))
	return maior


## Distância do frame ao membro mais próximo da janela.
func _dist_janela(janela: Array[Image], frame: Image) -> float:
	var menor := INF
	for ref in janela:
		menor = minf(menor, _dist(ref, frame))
	return menor if menor < INF else 0.0


## Um `process_frame` entre os steps porque o hw render devolve o alvo de render
## ao Godot a cada frame — sem isso o readback do FBO mede um frame a meio.
func _avancar(emu: EmuCore, quantos: int) -> void:
	for f in quantos:
		emu.step()
		await get_tree().process_frame


## O frame atual, reduzido para comparação. Sem PNG: é o caso das dezenas de
## capturas da janela e da procura de cena.
func _reduzir(emu: EmuCore) -> Image:
	var img := emu._host.get_frame() as Image
	if img == null:
		return null
	var pequena := Image.create_from_data(
			img.get_width(), img.get_height(), false, img.get_format(), img.get_data())
	pequena.resize(LARG, ALT, Image.INTERPOLATE_BILINEAR)
	pequena.convert(Image.FORMAT_L8)
	return pequena


## Como `_reduzir`, mas grava o frame cheio em PNG antes. O PNG é para o olho:
## quando o teste falha, ele diz na hora se foi restauração ruim ou só a fase da
## animação — coisas que um número sozinho não separa. Foi olhando A e C que os
## dois desenhos descritos no topo se corrigiram.
func _capturar(emu: EmuCore, sistema: String, marca: String) -> Image:
	var img := emu._host.get_frame() as Image
	if img != null:
		img.save_png("user://estado_%s_%s.png" % [sistema, marca])
	return _reduzir(emu)


## Diferença média absoluta por pixel, em cinza, em [0,1].
func _dist(x: Image, y: Image) -> float:
	if x == null or y == null:
		return 0.0
	var soma := 0.0
	for py in ALT:
		for px in LARG:
			soma += absf(x.get_pixel(px, py).r - y.get_pixel(px, py).r)
	return soma / float(LARG * ALT)


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
