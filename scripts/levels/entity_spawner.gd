@tool
class_name EntitySpawner
extends GridMap
## Слой сущностей уровня.
## В РЕДАКТОРЕ — видны цветные маркеры (рисуешь по сетке, как пол): спавн, выход,
## враги, пикапы. Один маркер на клетку, пол/стены на своём слое не трогаются.
## В ИГРЕ — каждый маркер превращается в настоящую сцену (враг/пикап/выход) или
## точку спавна, а сами маркеры прячутся.
##
## id предметов в doom_entities.tres соответствуют SCENES ниже.

const SPAWN_ID := 0   # точка появления игрока (особый случай → Marker3D "PlayerSpawn")
const EXIT_ID := 1
const FLYER_ID := 4

# id маркера → сцена для инстанса (выход/враги/пикапы). Спавн обрабатывается особо.
const SCENES := {
	1: "res://scenes/levels/level_exit.tscn",
	2: "res://scenes/enemies/rusher.tscn",
	3: "res://scenes/enemies/shooter.tscn",
	4: "res://scenes/enemies/flyer.tscn",
	5: "res://scenes/pickups/ammo/ammo_pickup.tscn",
	6: "res://scenes/pickups/ammo/shells_pickup.tscn",
	7: "res://scenes/pickups/health/health_bonus.tscn",
	8: "res://scenes/pickups/health/stimpack.tscn",
	9: "res://scenes/pickups/health/medikit.tscn",
	10: "res://scenes/pickups/health/soulsphere.tscn",
	11: "res://scenes/pickups/armor/armor_bonus.tscn",
	12: "res://scenes/pickups/armor/armor_green.tscn",
	13: "res://scenes/pickups/armor/armor_blue.tscn",
}

## Высота, на которой висит летун.
@export var flyer_height: float = 2.0


func _ready() -> void:
	if Engine.is_editor_hint():
		return            # в редакторе показываем маркеры как есть
	visible = false       # маркеры в игре не нужны
	# Отложенно: на момент _ready родитель ещё «занят» (main.gd добавляет уровень),
	# add_child в него запрещён. На следующем кадре дерево готово — спавним.
	_spawn_all.call_deferred()


func _spawn_all() -> void:
	var parent := get_parent()
	if parent == null:
		return
	for cell in get_used_cells():
		var id := get_cell_item(cell)
		var world := to_global(map_to_local(cell))
		var pos := Vector3(world.x, _y_for(id), world.z)
		if id == SPAWN_ID:
			_make_spawn(parent, pos, cell)
		elif SCENES.has(id):
			_make_scene(parent, SCENES[id], pos)


# Высота над полом по типу маркера (верх пола ≈ y0).
func _y_for(id: int) -> float:
	if id == SPAWN_ID:
		return 0.4
	if id == EXIT_ID:
		return 0.0
	if id == FLYER_ID:
		return flyer_height
	if id >= 5:
		return 0.5     # пикапы (с покачиванием)
	return 0.1         # наземные враги (осядут гравитацией)


func _make_spawn(parent: Node, pos: Vector3, cell: Vector3i) -> void:
	# Прямой PlayerSpawn (если был в сцене) уступает место маркеру.
	var old := parent.get_node_or_null("PlayerSpawn")
	if old != null:
		old.name = "PlayerSpawn_old"
		old.queue_free()
	var m := Marker3D.new()
	m.name = "PlayerSpawn"
	parent.add_child(m)
	# Поворот берём из ориентации клетки (можно крутить маркер при покраске).
	var marker_basis := get_basis_with_orthogonal_index(get_cell_item_orientation(cell))
	m.global_transform = Transform3D(marker_basis, pos)


func _make_scene(parent: Node, scene_path: String, pos: Vector3) -> void:
	var ps: PackedScene = load(scene_path)
	if ps == null:
		push_warning("EntitySpawner: не загрузилась сцена %s" % scene_path)
		return
	var inst := ps.instantiate()
	parent.add_child(inst)
	if inst is Node3D:
		(inst as Node3D).global_position = pos
