class_name PagCores
extends PagBase
## Onde a pessoa vê quais cores tem e busca os que faltam, sem PC nenhum.
##
## É a página que fecha o buraco do modelo "o usuário fornece o core": até aqui,
## fornecer significava ligar o headset num computador e arrastar um `.so` — ou
## seja, o app **não se bastava**, e quem só tem o Quest não jogava nada.
##
## Uma linha por sistema conhecido, e a lista sai de `EmuCore.CORES` — console
## novo aparece aqui sozinho, sem ninguém lembrar de acrescentá-lo.
##
## **A licença fica visível antes do botão**, e isso não é enfeite: é o que
## sustenta a leitura de que baixar não é redistribuir (ver `BaixadorCores`).
## Ninguém traz um core para dentro do aparelho sem saber sob que termos ele vem.

var _baixador: BaixadorCores
var _lista: VBoxContainer
var _aviso: Label
## Estado por sistema, só para a linha saber o que desenhar enquanto baixa.
var _andamento := {}


func _init() -> void:
	super("Cores")

	_baixador = BaixadorCores.new()
	add_child(_baixador)
	_baixador.concluido.connect(_ao_concluir)
	_baixador.falhou.connect(_ao_falhar)
	_baixador.progresso.connect(_ao_progredir)

	_aviso = WidgetsVR.mono("", TemaVR.DIM)
	_aviso.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	conteudo.add_child(_aviso)

	_lista = VBoxContainer.new()
	_lista.add_theme_constant_override("separation", 10)
	_lista.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	conteudo.add_child(_lista)

	# Fora do Android `cores()` é "", e concatenar daria um "/" solto no rodapé —
	# que parece caminho raiz e não é caminho nenhum.
	var pasta := Armazenamento.cores()
	rodape.add_child(WidgetsVR.mono(pasta + "/" if not pasta.is_empty() else "res://cores/"))
	rodape.add_child(espacador())

	atualizar()


## Rechamada sempre que o menu abre: um core pode ter sido copiado à mão desde a
## última vez, e a página não pode contradizer a pasta.
func atualizar() -> void:
	for filho in _lista.get_children():
		filho.queue_free()

	if not Armazenamento.ativo():
		# No desktop os cores vêm por `res://cores` e o fluxo de desenvolvimento já
		# os põe lá (ver "Baixar os cores" no README). Baixar aqui só confundiria:
		# o buildbot publica binário de Android, que não roda nesta máquina.
		_aviso.text = "Fora do headset os cores vêm de res://cores — ver o README."
		return

	_aviso.text = ("Os cores são de terceiros e não vão no APK: cada um tem a sua "
			+ "licença, e é você quem escolhe trazê-lo. Baixados de "
			+ "buildbot.libretro.com.")

	for sistema: String in EmuCore.CORES:
		_lista.add_child(_linha(sistema))


func _linha(sistema: String) -> Control:
	var caixa := VBoxContainer.new()
	caixa.add_theme_constant_override("separation", 2)

	var topo := HBoxContainer.new()
	topo.add_theme_constant_override("separation", 12)
	caixa.add_child(topo)

	var titulo := Label.new()
	titulo.text = NavegadorRoms.nome_sistema(sistema)
	titulo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	topo.add_child(titulo)

	var caminho := Armazenamento.procurar_core(BaixadorCores.nome_baixavel(sistema))
	var presente := not caminho.is_empty()

	if _andamento.has(sistema):
		topo.add_child(WidgetsVR.mono(_andamento[sistema]))
		var bt_cancelar := WidgetsVR.botao("Parar")
		bt_cancelar.custom_minimum_size.x = 0
		bt_cancelar.pressed.connect(_baixador.cancelar)
		topo.add_child(bt_cancelar)
	elif presente:
		topo.add_child(WidgetsVR.chip("no aparelho", TemaVR.ACCENT))
		var bt_remover := WidgetsVR.botao("Remover")
		bt_remover.custom_minimum_size.x = 0
		bt_remover.pressed.connect(_remover.bind(sistema, caminho))
		topo.add_child(bt_remover)
	else:
		var bt := WidgetsVR.botao("Baixar", true)
		bt.custom_minimum_size.x = 0
		# `ocupado()` é conferido no clique, e não aqui, porque a página não é
		# redesenhada a cada byte: o botão existe desde antes de o download começar.
		bt.pressed.connect(_baixar.bind(sistema))
		topo.add_child(bt)

	# Nome do arquivo e licença ficam **sempre** visíveis, inclusive depois de
	# baixado: quem for reportar um problema precisa saber qual binário tem, e quem
	# for redistribuir o aparelho precisa saber sob que termos aquilo entrou.
	var rodape_linha := WidgetsVR.mono("%s — %s" % [
		BaixadorCores.nome_baixavel(sistema),
		BaixadorCores.LICENCAS.get(sistema, "licença do upstream"),
	])
	rodape_linha.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caixa.add_child(rodape_linha)

	return caixa


func _baixar(sistema: String) -> void:
	if _baixador.ocupado():
		_aviso.text = "Um download por vez — espere o que está em curso."
		return
	_andamento[sistema] = "iniciando…"
	_baixador.baixar(sistema)
	atualizar()


func _remover(sistema: String, caminho: String) -> void:
	DirAccess.remove_absolute(caminho)
	print("Cores: removido %s (%s)" % [caminho.get_file(), sistema])
	atualizar()


func _ao_progredir(sistema: String, recebido: int, total: int) -> void:
	# Sem Content-Length não dá para mostrar porcentagem, e inventar uma seria
	# pior: mostra o que se sabe, que é quanto já veio.
	if total > 0:
		_andamento[sistema] = "%d%%" % int(float(recebido) * 100.0 / float(total))
	else:
		_andamento[sistema] = "%d KB" % int(recebido / 1024.0)
	for filho in _lista.get_children():
		filho.queue_free()
	for s: String in EmuCore.CORES:
		_lista.add_child(_linha(s))


func _ao_concluir(sistema: String, caminho: String) -> void:
	_andamento.erase(sistema)
	print("Cores: %s baixado (%s)" % [sistema, caminho])
	_aviso.text = "%s pronto. Já dá para abrir um jogo." % NavegadorRoms.nome_sistema(sistema)
	atualizar()


func _ao_falhar(sistema: String, msg: String) -> void:
	_andamento.erase(sistema)
	push_warning("Cores: %s falhou — %s" % [sistema, msg])
	_aviso.text = "%s: %s" % [NavegadorRoms.nome_sistema(sistema), msg]
	atualizar()
