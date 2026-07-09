@tool
extends EditorScript
## Добавляет слой "Entities" (маркеры сущностей) в ТЕКУЩУЮ ОТКРЫТУЮ сцену,
## ничего больше не трогая. Удобно, чтобы добавить слой в уже нарисованный уровень.
##
## Перед запуском:
##   1) один раз прогони build_doom_kit.gd (он соберёт doom_entities.tres);
##   2) открой нужный уровень (напр. level_E1_L1.tscn);
##   3) File → Run на этом файле.
## Потом сохрани сцену (Ctrl+S) и рисуй маркеры на слое Entities.

const ENTITIES_MESHLIB_PATH := "res://scenes/levels/kit/doom_entities.tres"
const SPAWNER_SCRIPT := "res://scripts/levels/entity_spawner.gd"
const CELL := 4.0


func _run() -> void:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		printerr("[entities] нет открытой сцены — открой уровень и запусти снова")
		return
	if root.has_node("Entities"):
		print("[entities] слой Entities уже есть в этой сцене")
		return
	var lib := load(ENTITIES_MESHLIB_PATH)
	if lib == null:
		printerr("[entities] нет %s — сначала прогони build_doom_kit.gd" % ENTITIES_MESHLIB_PATH)
		return

	var gm := GridMap.new()
	gm.name = "Entities"
	gm.cell_size = Vector3(CELL, CELL, CELL)
	gm.cell_center_x = true
	gm.cell_center_y = false
	gm.cell_center_z = true
	gm.mesh_library = lib
	gm.set_script(load(SPAWNER_SCRIPT))
	root.add_child(gm)
	gm.owner = root   # чтобы узел сохранился в сцене
	print("[entities] слой Entities добавлен. Сохрани сцену (Ctrl+S) и рисуй маркеры.")
