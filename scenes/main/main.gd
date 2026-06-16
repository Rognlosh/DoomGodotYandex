extends Node3D
## Единая точка входа в игру.
## Сейчас задача минимальна: загрузить текущий уровень и поставить игрока
## в точку спавна. Позже здесь появятся смена уровней, HUD, пауза, game-over.

## Сцена уровня (назначается в инспекторе).
@export var level_scene: PackedScene
## Сцена игрока (назначается в инспекторе).
@export var player_scene: PackedScene


func _ready() -> void:
	if level_scene == null or player_scene == null:
		push_error("Main: в инспекторе не назначены level_scene и/или player_scene.")
		return

	var level := level_scene.instantiate()
	add_child(level)

	var player := player_scene.instantiate() as Node3D
	add_child(player)

	# Если у уровня есть точка спавна — ставим игрока туда.
	var spawn := level.get_node_or_null("PlayerSpawn")
	if spawn is Node3D:
		player.global_transform = (spawn as Node3D).global_transform
