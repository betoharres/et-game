class_name LevelDefinition
extends Resource

## Uma entrada do catalogo de fases mostrado no terminal da plataforma
## orbital. Cada fase futura ganha um arquivo .tres novo instanciando este
## recurso; nenhum script precisa mudar para o catalogo crescer.

@export var display_name : String = "FASE"
@export_multiline var briefing : String = ""
## Cena carregada ao selecionar esta fase. String em vez de PackedScene: nao
## pre-carrega todas as fases so por listar o catalogo.
@export_file("*.tscn") var scene_path : String = ""

@export var available : bool = true
## Mostrado no lugar do briefing quando a fase ainda nao esta disponivel.
@export var locked_reason : String = "Em desenvolvimento"


func can_launch() -> bool:
	return (
		available
		and not scene_path.is_empty()
		and ResourceLoader.exists(scene_path, "PackedScene")
	)
