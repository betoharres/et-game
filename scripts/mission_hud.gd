extends Control

## Painel de missão ativa, no canto da tela. Genérico: só reflete o que
## MissionLog (scripts/mission_log.gd) publica, então serve para qualquer
## missão do jogo — quem inicia/atualiza/conclui a missão não sabe desta cena.

@onready var title_label : Label = $Panel/Margin/Rows/Title
@onready var objective_label : Label = $Panel/Margin/Rows/Objective


func _ready() -> void:
	hide()
	MissionLog.mission_started.connect(_on_mission_started)
	MissionLog.objective_updated.connect(_on_objective_updated)
	MissionLog.mission_completed.connect(_on_mission_completed)
	if MissionLog.is_active:
		_on_mission_started(MissionLog.active_title, MissionLog.active_objective)


func _on_mission_started(title : String, objective : String) -> void:
	title_label.text = title
	objective_label.text = objective
	show()


func _on_objective_updated(objective : String) -> void:
	objective_label.text = objective


func _on_mission_completed() -> void:
	hide()
