class_name EnergyPool
extends Node

## Reserva de energia genérica e reutilizável.
##
## Qualquer sistema pode gastar energia daqui de duas formas:
## [br]- gasto contínuo: [method set_drain] registra uma taxa por segundo com
## uma chave própria (a lanterna dos olhos, um escudo, um propulsor...);
## [br]- gasto instantâneo: [method try_consume] desconta de uma vez e
## devolve [code]false[/code] se não houver saldo suficiente.
## [br][br]
## Enquanto houver qualquer dreno ativo a recarga fica suspensa. Quando a
## reserva zera, [signal depleted] avisa os consumidores para se desligarem.

signal energy_changed(current_energy : float, maximum_energy : float)
signal depleted
signal recharged

@export var max_energy : float = 100.0
@export var start_full : bool = true
@export_range(0.0, 100.0, 0.5) var recharge_per_second : float = 4.0
@export_range(0.0, 10.0, 0.1) var recharge_delay : float = 2.5
## Fração da reserva que precisa ser reposta depois de zerar antes que os
## consumidores possam voltar a ligar.
@export_range(0.0, 1.0, 0.01) var recharge_threshold : float = 0.15

var _energy : float = 0.0
var _drains : Dictionary = {}
var _recharge_timer : float = 0.0
var _is_depleted : bool = false
var _initialized : bool = false


func _ready() -> void:
	_ensure_initialized()
	energy_changed.emit(_energy, max_energy)


## A reserva pode ser lida antes do [method _ready] (nós irmãos e HUDs filhos
## ficam prontos primeiro), por isso a carga inicial é aplicada sob demanda.
func _ensure_initialized() -> void:
	if _initialized:
		return

	_initialized = true
	_energy = max_energy if start_full else 0.0
	_is_depleted = _energy <= 0.0


func _process(delta : float) -> void:
	_ensure_initialized()
	var drain_rate : float = get_drain_rate()
	var previous_energy : float = _energy

	if drain_rate > 0.0:
		_energy = maxf(_energy - drain_rate * delta, 0.0)
		_recharge_timer = recharge_delay
	elif _energy < max_energy:
		_recharge_timer = maxf(_recharge_timer - delta, 0.0)
		if _recharge_timer <= 0.0:
			_energy = minf(_energy + recharge_per_second * delta, max_energy)

	if not is_equal_approx(previous_energy, _energy):
		energy_changed.emit(_energy, max_energy)

	_update_depleted_state()


## Registra (ou atualiza) um gasto contínuo em unidades por segundo.
## Use uma [param source_key] estável por sistema consumidor.
func set_drain(source_key : StringName, rate_per_second : float) -> void:
	if rate_per_second <= 0.0:
		clear_drain(source_key)
		return

	_drains[source_key] = rate_per_second


func clear_drain(source_key : StringName) -> void:
	_drains.erase(source_key)


func has_drain(source_key : StringName) -> bool:
	return _drains.has(source_key)


func clear_all_drains() -> void:
	_drains.clear()


func get_drain_rate() -> float:
	var total : float = 0.0
	for rate : float in _drains.values():
		total += rate
	return total


## Desconta [param amount] de uma vez. Devolve [code]false[/code] (sem gastar
## nada) quando não há saldo suficiente.
func try_consume(amount : float) -> bool:
	_ensure_initialized()
	if amount <= 0.0:
		return true
	if _energy < amount:
		return false

	_energy -= amount
	_recharge_timer = recharge_delay
	energy_changed.emit(_energy, max_energy)
	_update_depleted_state()
	return true


func add(amount : float) -> void:
	_ensure_initialized()
	if amount <= 0.0:
		return

	var previous_energy : float = _energy
	_energy = minf(_energy + amount, max_energy)
	if not is_equal_approx(previous_energy, _energy):
		energy_changed.emit(_energy, max_energy)
	_update_depleted_state()


func refill() -> void:
	add(max_energy)


func has_energy(amount : float = 0.0) -> bool:
	_ensure_initialized()
	return _energy > 0.0 and _energy >= amount


## Falso enquanto a reserva zerada ainda não recuperou [member
## recharge_threshold]. Consumidores devem checar isto antes de ligar.
func can_be_used() -> bool:
	_ensure_initialized()
	return not _is_depleted


func get_energy() -> float:
	_ensure_initialized()
	return _energy


func get_max_energy() -> float:
	return max_energy


func get_ratio() -> float:
	_ensure_initialized()
	if max_energy <= 0.0:
		return 0.0
	return _energy / max_energy


func _update_depleted_state() -> void:
	if _is_depleted:
		if get_ratio() >= recharge_threshold:
			_is_depleted = false
			recharged.emit()
	elif _energy <= 0.0:
		_is_depleted = true
		clear_all_drains()
		depleted.emit()
