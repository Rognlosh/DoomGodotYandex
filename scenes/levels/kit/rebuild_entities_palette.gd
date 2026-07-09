@tool
extends EditorScript
## Пересобирает ТОЛЬКО палитру сущностей doom_entities.tres из MARKERS
## (источник правды — build_doom_kit.gd). НЕ трогает doom_kit.tres и уровни —
## безопасно для уже нарисованных карт. Запуск: открыть скрипт → File → Run.
##
## Нужен после добавления нового типа маркера (строка в MARKERS + иконка):
## один прогон — и новый маркер появляется в палитре слоя Entities.

const Builder := preload("res://scenes/levels/kit/build_doom_kit.gd")


func _run() -> void:
	var lib := MeshLibrary.new()
	for m in Builder.MARKERS:
		var id: int = m[0]
		lib.create_item(id)
		lib.set_item_name(id, m[1])
		lib.set_item_mesh(id, _marker_mesh(m[2]))
		lib.set_item_mesh_transform(id, Transform3D(Basis(), Vector3(0, Builder.MARKER_Y, 0)))
	var path: String = Builder.ENTITIES_MESHLIB_PATH
	if ResourceSaver.save(lib, path) == OK:
		print("[entities] палитра пересобрана → ", path, " (", Builder.MARKERS.size(), " маркеров)")
	else:
		printerr("[entities] не удалось сохранить ", path)


# Плитка-маркер с иконкой (копия логики из build_doom_kit._marker_mesh —
# стабильная, MARKERS остаётся единственным источником правды).
func _marker_mesh(icon_file: String) -> PlaneMesh:
	var pm := PlaneMesh.new()
	pm.size = Vector2(Builder.MARKER_SIZE, Builder.MARKER_SIZE)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(Builder.ICON_DIR + icon_file)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED  # цвет иконки как есть
	pm.material = mat
	return pm
