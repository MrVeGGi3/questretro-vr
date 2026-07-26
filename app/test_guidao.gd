extends Node
## Prova a conta do guidão sem headset nenhum. É aritmética pura, então roda em
## `--headless` (ao contrário do test_troca_rom, que precisa de GPU):
##
##   godot --headless --xr-mode off --path app res://test_guidao.tscn
##
## Roda como cena e não com `-s` pelo mesmo motivo do test_ui: script de
## MainLoop trava na inicialização com a GDExtension carregada.
##
## O caso que mais importa aqui é o do corpo girado. Um referencial errado
## (usar os eixos do mundo em vez da guinada da câmera) passa despercebido em
## qualquer teste feito de frente — e é assim que se testa no headset, de pé,
## olhando para a tela. Aqui ele não escapa.

## Meia distância entre as mãos ao segurar a barra. As poses de teste são
## montadas a partir dela.
const MEIA_BARRA := 0.2

var _falhas := 0


func _ready() -> void:
	_nivelado_e_centrado_da_zero()
	_inclinar_a_barra_rola()
	_empurrar_e_puxar_arfa()
	_inverter_y_troca_so_o_y()
	_corpo_girado_nao_muda_nada()
	_cabeca_inclinada_nao_muda_nada()
	_satura_em_um()
	_zona_morta_e_exatamente_zero()
	_sem_centrar_nao_comanda()

	print("=== %s ===" % ("TUDO OK" if _falhas == 0 else "%d FALHA(S)" % _falhas))
	get_tree().quit(1 if _falhas > 0 else 0)


func _nivelado_e_centrado_da_zero() -> void:
	var g := _guidao()
	var p := _pose()
	g.centrar(p.esq, p.dir, p.cam)
	_perto(g.eixos(p.esq, p.dir, p.cam), Vector2.ZERO, "barra nivelada e no centro dá zero")


func _inclinar_a_barra_rola() -> void:
	var g := _guidao()
	var p := _pose()
	g.centrar(p.esq, p.dir, p.cam)

	# Mão direita sobe, esquerda desce: barra tombada para a direita.
	var d := _pose(0.0, deg_to_rad(20.0))
	var dir_cima := g.eixos(d.esq, d.dir, d.cam)
	_verdade(dir_cima.x > 0.4, "direita acima da esquerda rola para +x (deu %.2f)" % dir_cima.x)

	# E o espelho tem que dar o oposto, com a mesma força.
	var e := _pose(0.0, deg_to_rad(-20.0))
	var esq_cima := g.eixos(e.esq, e.dir, e.cam)
	_perto(Vector2(esq_cima.x, 0), Vector2(-dir_cima.x, 0), "inclinação espelhada dá x espelhado")


func _empurrar_e_puxar_arfa() -> void:
	var g := _guidao()
	var p := _pose()
	g.centrar(p.esq, p.dir, p.cam)

	var frente := _pose(-0.15)
	var tras := _pose(0.15)
	var y_frente := g.eixos(frente.esq, frente.dir, frente.cam).y
	var y_tras := g.eixos(tras.esq, tras.dir, tras.cam).y
	_verdade(y_frente > 0.3, "empurrar dá +y (deu %.2f)" % y_frente)
	_verdade(y_tras < -0.3, "puxar dá -y (deu %.2f)" % y_tras)


func _inverter_y_troca_so_o_y() -> void:
	var p := _pose(-0.15, deg_to_rad(20.0))

	var normal := _guidao()
	normal.centrar(_pose().esq, _pose().dir, _pose().cam)
	var a := normal.eixos(p.esq, p.dir, p.cam)

	var invertido := _guidao()
	invertido.inverter_y = true
	invertido.centrar(_pose().esq, _pose().dir, _pose().cam)
	var b := invertido.eixos(p.esq, p.dir, p.cam)

	_perto(Vector2(b.x, b.y), Vector2(a.x, -a.y), "inverter_y troca só o y")


## O teste que justifica a câmera entrar na conta.
func _corpo_girado_nao_muda_nada() -> void:
	var de_frente := _pose(-0.12, deg_to_rad(18.0))
	var g1 := _guidao()
	g1.centrar(_pose().esq, _pose().dir, _pose().cam)
	var esperado := g1.eixos(de_frente.esq, de_frente.dir, de_frente.cam)

	# Mesma pose relativa, o jogador inteiro girado. Não é só a câmera: as mãos
	# giram junto, porque o corpo girou.
	for graus in [90.0, -90.0, 180.0, 37.0]:
		var girado := _pose(-0.12, deg_to_rad(18.0), deg_to_rad(graus))
		var g2 := _guidao()
		var zero := _pose(0.0, 0.0, deg_to_rad(graus))
		g2.centrar(zero.esq, zero.dir, zero.cam)
		_perto(g2.eixos(girado.esq, girado.dir, girado.cam), esperado,
				"corpo girado %d° dá o mesmo comando" % int(graus))


func _cabeca_inclinada_nao_muda_nada() -> void:
	var p := _pose(-0.12, deg_to_rad(18.0))
	var g := _guidao()
	g.centrar(_pose().esq, _pose().dir, _pose().cam)
	var esperado := g.eixos(p.esq, p.dir, p.cam)

	# Mesma guinada, cabeça olhando para baixo e tombada: não é comando.
	var cam := Transform3D(Basis.from_euler(
			Vector3(deg_to_rad(-30.0), 0.0, deg_to_rad(15.0))), p.cam.origin)
	_perto(g.eixos(p.esq, p.dir, cam), esperado, "inclinar a cabeça não vira comando")


func _satura_em_um() -> void:
	var g := _guidao()
	g.centrar(_pose().esq, _pose().dir, _pose().cam)
	# Muito além do ângulo e do curso cheios.
	var p := _pose(-1.5, deg_to_rad(80.0))
	var v := g.eixos(p.esq, p.dir, p.cam)
	_verdade(v.length() <= 1.0001, "não passa de 1 no módulo (deu %.3f)" % v.length())
	_verdade(v.x > 0.6 and v.y > 0.6, "satura para o canto certo (%.2f, %.2f)" % [v.x, v.y])


func _zona_morta_e_exatamente_zero() -> void:
	var g := _guidao()
	g.centrar(_pose().esq, _pose().dir, _pose().cam)
	# Um tremor de mão: 1° de inclinação e 5 mm de curso.
	var p := _pose(-0.005, deg_to_rad(1.0))
	_perto(g.eixos(p.esq, p.dir, p.cam), Vector2.ZERO, "tremor dentro da zona morta dá zero exato")


func _sem_centrar_nao_comanda() -> void:
	var g := _guidao()
	var p := _pose(-0.15, deg_to_rad(20.0))
	_perto(g.eixos(p.esq, p.dir, p.cam), Vector2.ZERO, "sem centrar, pose nenhuma comanda")


# ---------------------------------------------------------------------------
# Montagem das poses
# ---------------------------------------------------------------------------
## Um jogador segurando a barra. `avanco` empurra as mãos para frente (metros,
## negativo é para frente em Godot), `tombo` inclina a barra (radianos, positivo
## levanta a direita) e `guinada` gira o jogador inteiro — corpo, cabeça e mãos.
func _pose(avanco := 0.0, tombo := 0.0, guinada := 0.0) -> Dictionary:
	var altura := Vector3(0.0, 1.2, 0.0)          # mãos na altura do peito
	var frente := Vector3(0.0, 0.0, -0.35)        # braços à frente do corpo
	var meia := Vector3(MEIA_BARRA, 0.0, 0.0)

	# A barra tomba em torno do eixo que aponta para frente do jogador.
	var giro_barra := Basis(Vector3.FORWARD, -tombo)
	var esq := altura + frente + giro_barra * -meia + Vector3(0, 0, avanco)
	var dir := altura + frente + giro_barra * meia + Vector3(0, 0, avanco)

	var giro := Basis(Vector3.UP, guinada)
	var olho := Vector3(0.0, 1.6, 0.0)
	return {
		"esq": Transform3D(Basis(), giro * esq),
		"dir": Transform3D(Basis(), giro * dir),
		"cam": Transform3D(giro, giro * olho),
	}


func _guidao() -> Guidao:
	return Guidao.new()


# ---------------------------------------------------------------------------
# Asserções
# ---------------------------------------------------------------------------
func _perto(deu: Vector2, esperado: Vector2, o_que: String) -> void:
	if deu.distance_to(esperado) < 0.02:
		print("  ok   %s" % o_que)
	else:
		printerr("  FALHA %s — esperava (%.3f, %.3f), deu (%.3f, %.3f)" % [
			o_que, esperado.x, esperado.y, deu.x, deu.y])
		_falhas += 1


func _verdade(ok: bool, o_que: String) -> void:
	if ok:
		print("  ok   %s" % o_que)
	else:
		printerr("  FALHA %s" % o_que)
		_falhas += 1
