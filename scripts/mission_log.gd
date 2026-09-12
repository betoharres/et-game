extends Node

## Estado da missão ativa, compartilhado entre cenas (órbita, fases, cidade).
## Autoload porque o HUD de missão precisa reagir a mudanças por sinal em
## qualquer cena, ao contrário do MissionFlow (scripts/levels/mission_flow.gd),
## que só carrega uma flag estática de uma cena para a próxima.

signal mission_started(title : String, objective : String)
signal objective_updated(objective : String)
signal mission_completed()

var is_active : bool = false
var active_title : String = ""
var active_objective : String = ""


func start_mission(title : String, objective : String) -> void:
	is_active = true
	active_title = title
	active_objective = objective
	mission_started.emit(title, objective)


func update_objective(objective : String) -> void:
	if not is_active:
		return
	active_objective = objective
	objective_updated.emit(objective)


func complete_mission() -> void:
	if not is_active:
		return
	is_active = false
	active_title = ""
	active_objective = ""
	mission_completed.emit()
