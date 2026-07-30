class_name ConfigEmu
extends Node
## Configuração persistente do emulador, em `user://config.cfg`.
##
## Fonte única de verdade: quem muda um valor chama definir(), quem reage
## escuta `mudou`. A cena VR e as páginas do menu nunca conversam direto —
## isso evita que o slider e o analógico briguem pelo mesmo estado.
##
## As chaves são "secao/nome" e viram seção/chave do ConfigFile.
##
## Por cima do valor geral pode haver um **perfil do cartucho** (ver
## `usar_perfil`), que sobrescreve as chaves de input. Ele entra por baixo do
## contrato acima: quem lê continua chamando obter() e quem reage continua
## escutando `mudou`, então nem a cena nem as páginas precisam saber que
## perfis existem.

signal mudou(chave: String, valor: Variant)

## Emitido quando o jogo passa a ter (ou deixa de ter) perfil próprio. Só a
## página de Input escuta: o interruptor dela não está ligado a chave nenhuma,
## porque "ter perfil" é estado do arquivo, não valor de configuração.
signal perfil_mudou(ativo: bool)

const ARQUIVO := "user://config.cfg"
const PASTA_PERFIS := "user://perfis"

## O que um perfil de cartucho pode sobrescrever. Só input: o guidão e a zona
## morta são ajustes do corpo contra *aquele* jogo — o Star Fox 64 nasce com Y
## invertido e o Mario 64 não. Tamanho de tela e volume são preferência de quem
## joga, não do cartucho, e duplicá-los por jogo só criaria lugares diferentes
## para consertar a mesma coisa.
const PERFIL_PREFIXO := "input/"

## Intervalo mínimo entre gravações. Arrastar um slider dispara dezenas de
## definir() por segundo; sem isso seria um write em disco por frame.
const INTERVALO_SALVAR := 0.75

# Índices dos aspectos (a UI mostra na mesma ordem).
enum { ASPECTO_4_3, ASPECTO_8_7, ASPECTO_16_9, ASPECTO_NATIVO }

## Como a página de ROMs lista. Biblioteca é o padrão; Pastas é o navegador de
## arquivos, que fica como saída quando a varredura não achou alguma ROM.
enum { LISTA_BIBLIOTECA, LISTA_PASTAS }

const PADROES := {
	# Idioma da interface. Índice de `Idioma` (0 = Auto), e não o locale por
	# extenso, porque o `segmentado` que desenha o seletor grava inteiro. O padrão
	# é Auto: quem instala não deveria precisar escolher para o app abrir na
	# língua do próprio aparelho.
	"app/idioma": Idioma.AUTO,
	# Qual mão aponta: a caneta do DS, o laser do menu e os ajustes de tela vão
	# nela; o botão de menu e o D-pad vão na outra.
	#
	# **Fica em `app/` e não em `input/` de propósito**: tudo sob `input/` pode ser
	# sobrescrito por perfil de cartucho (ver `PERFIL_PREFIXO`), e ser canhoto é
	# propriedade da pessoa, não do jogo. Um perfil que lembrasse uma mão para o
	# Star Fox e outra para o Mario seria um defeito, não um recurso.
	"app/mao_aponta": 0,
	# Os padrões de tela/input vieram das constantes que antes moravam
	# em vr/xr_main.gd — mudar aqui muda o comportamento inicial.
	"tela/escala": 1.5,
	"tela/distancia": 2.2,
	"tela/altura": 0.0,
	"tela/curvatura": 0.0,
	# Tela de baixo do DS, que tem posição própria: as chaves acima passam a
	# valer só para a de cima quando há duas. Os padrões põem um DS na mão —
	# perto, baixa e menor que a de cima, que é onde a caneta alcança sem
	# esticar o braço.
	# A distância não é só estética: a caneta é um **laser**, e um laser precisa
	# de espaço entre a mão e o alvo. A 0,75 m — que era o padrão anterior, e a
	# distância de um DS de verdade — a mão esticada passa do quad e o raio,
	# começando depois do alvo, não acerta nada. 1,15 m mantém a tela ao alcance
	# e deixa o braço atrás dela.
	"tela/ds_escala": 0.8,
	"tela/ds_distancia": 1.15,
	"tela/ds_altura": -0.35,
	# Ambiente em volta da tela. Nasce no Vazio — que é o que a cena sempre fez —
	# pela mesma razão que o guidão nasce desligado: uma atualização não troca o
	# cenário debaixo de quem já usa o app. Fora do perfil do cartucho de
	# propósito: onde você joga é preferência sua, não do jogo.
	"sala/modo": Sala.VAZIO,
	"video/filtro_suave": false,
	"video/aspecto": ASPECTO_4_3,
	"video/brilho": 1.0,
	# Contadores de frame na tela e no log. Existe como chave, e não só como
	# `-- --diag`, porque no Quest não há linha de comando: o argumento não
	# atravessa o `am start` (medido), e sem isto medir o custo de uma sala nova
	# custava export + sideload. Mesma razão do `input/guidao_diag`.
	"video/diag": false,
	"audio/volume": 0.8,
	"audio/mudo": false,
	"input/dpad_engaja": 0.5,
	"input/dpad_solta": 0.32,
	"input/dpad_meia_cardeal": 55.0,
	# Guidão de nave: pose dos controles no lugar do thumbstick, no N64.
	# Desligado por padrão — quem já usa o app continua com o mapa de sempre
	# até pedir o contrário. Ângulo e curso são chute educado até alguém
	# pilotar de verdade; a página Input existe para corrigi-los sem rebuild.
	"input/n64_guidao": false,
	"input/guidao_angulo_max": 35.0,
	# 12 cm, não 25: rolar é ângulo (o pulso resolve), arfar é distância, e
	# empurrar meio braço para subir ficava lerdo ao lado da rolagem.
	"input/guidao_curso": 0.12,
	"input/guidao_zona_morta": 0.08,
	# 1.0 = linear. Padrão neutro de propósito: a curva mexe no gosto, e não
	# tenho nada além de uma pessoa pilotando para chutar um valor melhor.
	"input/guidao_curva": 1.0,
	"input/guidao_inverter_y": false,
	# Leitura ao vivo dos eixos, na tela. Existe porque cada ida ao headset é
	# cara: com o número à vista, "não responde" e "responde ao contrário" e
	# "está grudado no batente" param de ser a mesma queixa.
	"input/guidao_diag": false,
	# Mapa de botões, uma chave por origem do Touch e por sistema — o mapa de
	# fábrica, que a página de Input deixa trocar e o perfil do cartucho deixa
	# trocar só para um jogo. Escrito por extenso, e não gerado em `_init`, para
	# este dicionário continuar sendo a lista completa do que existe: é ele que
	# decide se uma chave é conhecida, o que um perfil pode sobrescrever e o que
	# "Restaurar padrões" devolve.
	#
	# Os nomes não batem com os ids no N64, e não é engano: o próprio core
	# declara `JOYPAD_B` como o **A** do controle, `JOYPAD_Y` como o B e o Z em
	# `JOYPAD_L2`. Ainda no N64, sobram dois botões do Touch para quatro
	# direções de D-pad: cima/baixo é o que aparece em menu de jogo, e
	# esquerda/direita quase nunca. O Z fica no grip esquerdo, que era o que
	# tinha sobrado.
	"input/mapa_snes_dir_ax": LibretroHost.JOYPAD_A,
	"input/mapa_snes_dir_by": LibretroHost.JOYPAD_B,
	"input/mapa_snes_esq_ax": LibretroHost.JOYPAD_X,
	"input/mapa_snes_esq_by": LibretroHost.JOYPAD_Y,
	"input/mapa_snes_esq_trigger": LibretroHost.JOYPAD_L,
	"input/mapa_snes_dir_trigger": LibretroHost.JOYPAD_R,
	"input/mapa_snes_dir_grip": LibretroHost.JOYPAD_START,
	"input/mapa_snes_esq_grip": LibretroHost.JOYPAD_SELECT,
	"input/mapa_n64_dir_ax": LibretroHost.JOYPAD_B,
	"input/mapa_n64_dir_by": LibretroHost.JOYPAD_Y,
	"input/mapa_n64_esq_ax": LibretroHost.JOYPAD_DOWN,
	"input/mapa_n64_esq_by": LibretroHost.JOYPAD_UP,
	"input/mapa_n64_esq_trigger": LibretroHost.JOYPAD_L,
	"input/mapa_n64_dir_trigger": LibretroHost.JOYPAD_R,
	"input/mapa_n64_dir_grip": LibretroHost.JOYPAD_START,
	"input/mapa_n64_esq_grip": LibretroHost.JOYPAD_L2,
	# Mega Drive (e Sega CD, que usa o mesmo controle). Os nomes pregam a mesma
	# peça do N64: no genesis_plus_gx o "A" do controle é `JOYPAD_Y`, o "C" é
	# `JOYPAD_A`, e `JOYPAD_B` é o único que calha de bater.
	#
	# A mão direita fica com o controle de 3 botões inteiro — A, B, C e Start —,
	# que é tudo o que Sonic pede. Os três extras do controle de 6 botões (X, Y,
	# Z) e o Mode vão para a esquerda, onde só chegam em jogo que os use.
	"input/mapa_megadrive_dir_ax": LibretroHost.JOYPAD_Y,        # A
	"input/mapa_megadrive_dir_by": LibretroHost.JOYPAD_B,        # B
	"input/mapa_megadrive_dir_trigger": LibretroHost.JOYPAD_A,   # C
	"input/mapa_megadrive_dir_grip": LibretroHost.JOYPAD_START,
	"input/mapa_megadrive_esq_ax": LibretroHost.JOYPAD_L,        # X
	"input/mapa_megadrive_esq_by": LibretroHost.JOYPAD_X,        # Y
	"input/mapa_megadrive_esq_trigger": LibretroHost.JOYPAD_R,   # Z
	"input/mapa_megadrive_esq_grip": LibretroHost.JOYPAD_SELECT, # Mode
	# Nintendo DS. Os nomes batem com os ids, ao contrário do N64 e do Mega Drive
	# — conferido nos descritores do melonDS.
	#
	# O **gatilho direito fica em Nada**, e é a única escolha de peso aqui: ele é
	# a caneta. Mapeá-lo em R faria todo toque na tela de baixo apertar R junto,
	# e o jogo pareceria ter um botão fantasma. R vai para o grip.
	#
	# Start não entra no mapa porque não precisa: o toque curto no botão de menu
	# vale como Start em qualquer sistema (ver `_start_com_pulso`).
	"input/mapa_nds_dir_ax": LibretroHost.JOYPAD_A,
	"input/mapa_nds_dir_by": LibretroHost.JOYPAD_B,
	"input/mapa_nds_esq_ax": LibretroHost.JOYPAD_X,
	"input/mapa_nds_esq_by": LibretroHost.JOYPAD_Y,
	"input/mapa_nds_esq_trigger": LibretroHost.JOYPAD_L,
	"input/mapa_nds_dir_trigger": MapaInput.NADA,
	"input/mapa_nds_dir_grip": LibretroHost.JOYPAD_R,
	"input/mapa_nds_esq_grip": LibretroHost.JOYPAD_SELECT,
	"roms/ultima_pasta": "",
	"roms/recentes": [],
	"roms/modo_lista": LISTA_BIBLIOTECA,
	# Caminhos fixados no topo da biblioteca. Caminho, e não título: dois dumps
	# regionais do mesmo jogo são jogos diferentes para quem favoritou um deles.
	"roms/favoritos": [],
}

var _valores: Dictionary = {}
var _sujo := false
var _desde_salvar := 0.0

## Perfil do cartucho em uso: id do jogo (o mesmo de `EmuCore.id_rom()`) e as
## chaves que ele sobrescreve. `_overrides` vazio com `_perfil_id` preenchido
## significa jogo carregado *sem* perfil — que é o caso comum.
var _perfil_id := ""
var _overrides: Dictionary = {}
var _perfil_sujo := false


func _ready() -> void:
	carregar()


func _process(delta: float) -> void:
	if not _sujo and not _perfil_sujo:
		return
	_desde_salvar += delta
	if _desde_salvar >= INTERVALO_SALVAR:
		salvar()


func obter(chave: String) -> Variant:
	if _overrides.has(chave):
		return _overrides[chave]
	return _valores.get(chave, PADROES.get(chave))


## Grava no layer ativo: no perfil do cartucho quando há um e a chave é
## perfilável, no geral caso contrário.
func definir(chave: String, valor: Variant) -> void:
	if not PADROES.has(chave):
		push_error("ConfigEmu: chave desconhecida: " + chave)
		return
	# Compara com o valor *efetivo*, e não com o geral: com perfil ativo, uma
	# sobrescrita que por acaso coincide com o geral também precisa ser gravada,
	# ou o perfil ficaria sem a chave e voltaria a seguir o geral na sessão
	# seguinte.
	if obter(chave) == valor and (not _perfilavel(chave) or _overrides.has(chave)):
		return
	if _perfilavel(chave):
		_overrides[chave] = valor
		_perfil_sujo = true
	else:
		_valores[chave] = valor
		_sujo = true
	mudou.emit(chave, valor)


## Volta uma seção inteira ao padrão (o "Restaurar padrões" de cada página).
## Age no layer ativo: com perfil ligado, restaura o perfil e deixa o geral —
## que outros jogos usam — intacto.
func restaurar(secao: String) -> void:
	for chave in PADROES:
		if chave.begins_with(secao + "/"):
			definir(chave, PADROES[chave])


func _perfilavel(chave: String) -> bool:
	return tem_perfil() and chave.begins_with(PERFIL_PREFIXO)


# ---------------------------------------------------------------------------
# Perfil por cartucho
# ---------------------------------------------------------------------------
## Um arquivo por jogo, `user://perfis/<id>.cfg` — o mesmo id que nomeia o
## `.srm` e os slots de estado, então os arquivos de um cartucho ficam todos com
## o mesmo nome e legíveis para quem abrir a pasta. Um arquivo único com uma
## seção por jogo economizaria um open, mas o nome do cartucho viraria nome de
## seção (`[Star Fox 64 (USA)]`) e passaria a depender do escape do ConfigFile.
func caminho_perfil(id: String) -> String:
	return "%s/%s.cfg" % [PASTA_PERFIS, id]


func tem_perfil() -> bool:
	return not _overrides.is_empty()


func perfil_id() -> String:
	return _perfil_id


## Troca o cartucho em uso. Emite `mudou` para cada chave cujo valor **efetivo**
## mudou — é esse laço que faz a cena reaplicar o guidão e os sliders abertos se
## corrigirem sozinhos, sem que nenhum dos dois saiba de perfis.
func usar_perfil(id: String) -> void:
	if id == _perfil_id:
		return
	# O perfil que sai pode ter ajustes de segundos atrás: o timer de gravação
	# não terminou, e trocar de jogo não pode ser o jeito de perder o tuning.
	if _perfil_sujo:
		_salvar_perfil()

	var antes := _overrides
	_perfil_id = id
	_overrides = _ler_perfil(id)
	_avisar_diferencas(antes)


## Cria o perfil deste jogo copiando os valores efetivos de agora. Nasce igual
## ao que a pessoa já estava sentindo: ligar "ajustes deste jogo" não pode mudar
## o comportamento no mesmo instante, senão o interruptor viraria um sorteio.
func criar_perfil() -> void:
	if _perfil_id.is_empty() or tem_perfil():
		return
	for chave: String in PADROES:
		if chave.begins_with(PERFIL_PREFIXO):
			_overrides[chave] = obter(chave)
	_perfil_sujo = true
	_salvar_perfil()
	perfil_mudou.emit(true)


## Apaga o perfil: o jogo volta a seguir os ajustes gerais.
func apagar_perfil() -> void:
	if not tem_perfil():
		return
	var antes := _overrides
	_overrides = {}
	_perfil_sujo = false
	if FileAccess.file_exists(caminho_perfil(_perfil_id)):
		DirAccess.remove_absolute(caminho_perfil(_perfil_id))
	_avisar_diferencas(antes)
	perfil_mudou.emit(false)


func _ler_perfil(id: String) -> Dictionary:
	var fora := {}
	if id.is_empty():
		return fora
	var cfg := ConfigFile.new()
	if cfg.load(caminho_perfil(id)) != OK:
		return fora  # jogo sem perfil: segue o geral
	for chave: String in PADROES:
		if not chave.begins_with(PERFIL_PREFIXO):
			continue
		var partes := chave.split("/", false, 1)
		if not cfg.has_section_key(partes[0], partes[1]):
			continue
		var lido: Variant = cfg.get_value(partes[0], partes[1])
		# Mesma defesa do geral: arquivo de outra versão ou editado à mão traz
		# tipo errado, e o valor de fora vale mais que um crash adiante.
		if typeof(lido) == typeof(PADROES[chave]):
			fora[chave] = lido
		else:
			push_warning("ConfigEmu: tipo inesperado em %s do perfil %s" % [chave, id])
	return fora


## Emite `mudou` para as chaves cujo valor efetivo mudou entre dois conjuntos de
## sobrescritas. Sem isto, trocar de jogo mudaria os valores em silêncio e a
## cena continuaria pilotando com os ajustes do cartucho anterior.
func _avisar_diferencas(antes: Dictionary) -> void:
	for chave: String in PADROES:
		if not chave.begins_with(PERFIL_PREFIXO):
			continue
		var v_antes: Variant = antes.get(chave, _valores.get(chave))
		var v_agora: Variant = obter(chave)
		if v_antes != v_agora:
			mudou.emit(chave, v_agora)


func _salvar_perfil() -> void:
	if _perfil_id.is_empty() or _overrides.is_empty():
		_perfil_sujo = false
		return
	DirAccess.make_dir_recursive_absolute(PASTA_PERFIS)
	var cfg := ConfigFile.new()
	for chave: String in _overrides:
		var partes := chave.split("/", false, 1)
		cfg.set_value(partes[0], partes[1], _overrides[chave])
	var err := cfg.save(caminho_perfil(_perfil_id))
	if err != OK:
		push_error("ConfigEmu: falha ao salvar o perfil de %s (erro %d)" % [_perfil_id, err])
	_perfil_sujo = false


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


func eh_favorito(caminho: String) -> bool:
	return caminho in (obter("roms/favoritos") as Array)


## Liga/desliga o favorito e devolve como ficou. Grava direto em `_valores` pela
## mesma razão de `registrar_recente`: `definir()` compara por igualdade, e a
## lista aqui muda sempre.
func alternar_favorito(caminho: String) -> bool:
	var lista: Array = (obter("roms/favoritos") as Array).duplicate()
	var virou_favorito := not (caminho in lista)
	if virou_favorito:
		lista.push_back(caminho)
	else:
		lista.erase(caminho)
	_valores["roms/favoritos"] = lista
	_sujo = true
	mudou.emit("roms/favoritos", lista)
	return virou_favorito


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
	if _perfil_sujo:
		_salvar_perfil()
	if _sujo:
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
	if _sujo or _perfil_sujo:
		salvar()
