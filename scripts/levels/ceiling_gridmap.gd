@tool
class_name CeilingGridMap
extends GridMap
## Потолок уровня.
## В редакторе — скрыт (не мешает виду сверху и установке предметов).
## В игре — автоматически повторяет пол соседнего GridMap: над каждой клеткой
## пола ставит клетку потолка. Рисовать потолок вручную НЕ нужно — где есть пол,
## там в игре будет потолок (включая дорисованные вручную комнаты).

## Путь к GridMap с полом (по умолчанию — соседний узел "GridMap").
@export var floor_map_path: NodePath = NodePath("../GridMap")
## id предметов-«пола», над которыми нужен потолок (floor, pillar, door_arch).
@export var floor_items: Array[int] = [0, 3, 4]
## id предмета "ceiling" в MeshLibrary (что ставим сверху).
@export var ceiling_item: int = 2


func _ready() -> void:
	if Engine.is_editor_hint():
		visible = false   # в редакторе потолок не показываем
		return
	visible = true
	_rebuild()


# Перерисовать потолок по текущему полу.
func _rebuild() -> void:
	var src := get_node_or_null(floor_map_path) as GridMap
	if src == null:
		push_warning("CeilingGridMap: не найден пол по пути %s" % str(floor_map_path))
		return
	clear()
	for item in floor_items:
		for cell in src.get_used_cells_by_item(item):
			set_cell_item(cell, ceiling_item)
