class_name ConfigEmu
extends Node
## Configuração persistente do emulador, em `user://config.cfg`.
##
## Fonte única de verdade: quem muda um valor chama definir(), quem reage
## escuta `mudou`. A cena VR e as páginas do menu nunca conversam direto —
## isso evita que o slider e o analógico briguem pelo mesmo estado.
##
## As chaves são "secao/nome" e viram seção/chave do ConfigFile.

signal mudou(chave: String, valor: Variant)

const ARQUIVO := "user://config.cfg"

## Intervalo mínimo entre gravações. Arrastar um slider dispara dezenas de
## definir() por segundo; sem isso seria um write em disco por frame.
const INTERVALO_SALVAR := 0.75

# Índices dos aspectos (a UI mostra na mesma ordem).
enum { ASPECTO_4_3, ASPECTO_8_7, ASPECTO_16_9, ASPECTO_NATIVO }

const PADROES := {
	# Os padrões de tela/input vieram das constantes que antes moravam
	# em vr/xr_main.gd — mudar aqui muda o comportamento inicial.
	"tela/escala": 1.5,
	"tela/distancia": 2.2,
	"tela/altura": 0.0,
	"tela/curvatura": 0.0,
	"video/filtro_suave": false,
	"video/aspecto": ASPECTO_4_3,
	"video/brilho": 1.0,
	"audio/volume": 0.8,
	"audio/mudo": false,
	"input/dpad_engaja": 0.5,
	"input/dpad_solta": 0.32,
	"input/dpad_meia_cardeal": 55.0,
	"roms/ultima_pasta": "",
	"roms/recentes": [],
}

var _valores: Dictionary = {}
var _sujo := false
var _desde_salvar := 0.0


func _ready() -> void:
	carregar()


func _process(delta: float) -> void:
	if not _sujo:
		return
	_desde_salvar += delta
	if _desde_salvar >= INTERVALO_SALVAR:
		salvar()


func obter(chave: String) -> Variant:
	return _valores.get(chave, PADROES.get(chave))


func definir(chave: String, valor: Variant) -> void:
	if not PADROES.has(chave):
		push_error("ConfigEmu: chave desconhecida: " + chave)
		return
	if _valores.get(chave) == valor:
		return
	_valores[chave] = valor
	_sujo = true
	mudou.emit(chave, valor)


## Volta uma seção inteira ao padrão (o "Restaurar padrões" de cada página).
func restaurar(secao: String) -> void:
	for chave in PADROES:
		if chave.begins_with(secao + "/"):
			definir(chave, PADROES[chave])


## Proporção largura/altura para o aspecto escolhido. `nativo` é a do core,
## por isso vem de fora em vez de ser constante.
func aspecto_como_razao(nativo: float) -> float:
	match int(obter("video/aspecto")):
		ASPECTO_4_3: return 4.0 / 3.0
		ASPECTO_8_7: return 8.0 / 7.0
		ASPECTO_16_9: return 16.0 / 9.0
		_: return nativo


func registrar_recente(caminho: String) -> void:
	var lista: Array = (obter("roms/recentes") as Array).duplicate()
	lista.erase(caminho)
	lista.push_front(caminho)
	if lista.size() > 10:
		lista.resize(10)
	# definir() compara por igualdade; a lista sempre muda aqui, então grava.
	_valores["roms/recentes"] = lista
	_sujo = true
	mudou.emit("roms/recentes", lista)


func carregar() -> void:
	_valores = PADROES.duplicate(true)
	var cfg := ConfigFile.new()
	if cfg.load(ARQUIVO) != OK:
		return  # primeira execução: fica nos padrões
	for chave: String in PADROES:
		var partes := chave.split("/", false, 1)
		if cfg.has_section_key(partes[0], partes[1]):
			var lido: Variant = cfg.get_value(partes[0], partes[1])
			# Arquivo editado à mão ou de uma versão antiga pode trazer tipo
			# errado; nesse caso o padrão vale mais que um crash adiante.
			if typeof(lido) == typeof(PADROES[chave]):
				_valores[chave] = lido
			else:
				push_warning("ConfigEmu: tipo inesperado em %s, usando o padrão" % chave)


func salvar() -> void:
	var cfg := ConfigFile.new()
	for chave: String in _valores:
		var partes := chave.split("/", false, 1)
		cfg.set_value(partes[0], partes[1], _valores[chave])
	var err := cfg.save(ARQUIVO)
	if err != OK:
		push_error("ConfigEmu: falha ao salvar %s (erro %d)" % [ARQUIVO, err])
	_sujo = false
	_desde_salvar = 0.0


func _exit_tree() -> void:
	if _sujo:
		salvar()
