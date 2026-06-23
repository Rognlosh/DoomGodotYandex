@tool
extends EditorScript
## Сборщик модульного кита уровней (GridMap).
##
## Запуск: открыть этот файл в редакторе и нажать File → Run (Ctrl+Shift+X).
## Что делает за один проход:
##   1. строит материалы из текстур кита (Nearest-фильтр, тайлинг по граням);
##   2. строит меши: `wall` (сплошной куб) и `floor` (плита пола + плита потолка);
##   3. собирает `MeshLibrary` с коллизиями и сохраняет в doom_kit.tres;
##   4. рисует стартовый уровень (две комнаты + коридор) на GridMap, ставит
##      спавн/выход/врагов/пикапы и сохраняет level_doom_01.tscn.
## Идемпотентен: повторный запуск перезаписывает оба файла.

# --- размеры/пути ---------------------------------------------------------
const CELL := 4.0          # сторона клетки сетки (м); потолок = высота клетки
const TH := 0.4            # толщина плиты пола/потолка (м)
const UV_REPEAT := 2.0     # повторов текстуры на грань клетки (тайлинг)
const LIFT := 1.6          # подъём GridMap, чтобы верх пола встал на y≈0

const TEX_WALL := "res://assets/textures/tex_wall.png"
const TEX_FLOOR := "res://assets/textures/tex_floor.png"
const TEX_CEIL := "res://assets/textures/tex_ceiling.png"

const MESHLIB_PATH := "res://scenes/levels/kit/doom_kit.tres"
const LEVEL_PATH := "res://scenes/levels/level_doom_01.tscn"

# id предметов в MeshLibrary
const FLOOR_ID := 0
const WALL_ID := 1


func _run() -> void:
	print("[kit] сборка началась")
	var lib := _build_library()
	var err := ResourceSaver.save(lib, MESHLIB_PATH)
	if err != OK:
		printerr("[kit] не удалось сохранить MeshLibrary: ", err)
		return
	print("[kit] MeshLibrary сохранён → ", MESHLIB_PATH)

	_build_level(lib)
	print("[kit] уровень сохранён → ", LEVEL_PATH)

	# обновить FileSystem-док, чтобы новые файлы появились сразу
	var fs := EditorInterface.get_resource_filesystem()
	if fs:
		fs.scan()
	print("[kit] готово. Перетащи level_doom_01.tscn в main.tscn → levels.")


# --- материалы ------------------------------------------------------------
func _make_material(tex_path: String) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(tex_path)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST  # чёткий пиксель-арт
	mat.uv1_scale = Vector3(UV_REPEAT, UV_REPEAT, UV_REPEAT)    # тайлинг по граням
	mat.roughness = 1.0
	mat.metallic = 0.0
	return mat


# --- меши -----------------------------------------------------------------
# Сдвинутая копия массивов BoxMesh — одна поверхность с нормалями и UV «как надо».
func _slab_arrays(size: Vector3, y_offset: float) -> Array:
	var bm := BoxMesh.new()
	bm.size = size
	var arr: Array = bm.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	for i in verts.size():
		var v: Vector3 = verts[i]   # packed-элемент берём копией и кладём обратно
		v.y += y_offset
		verts[i] = v
	arr[Mesh.ARRAY_VERTEX] = verts
	return arr


# Пол+потолок одним мешом (2 поверхности → 2 материала).
func _build_floor_mesh(mat_floor: StandardMaterial3D, mat_ceil: StandardMaterial3D) -> ArrayMesh:
	var am := ArrayMesh.new()
	# плита пола у низа клетки
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,
		_slab_arrays(Vector3(CELL, TH, CELL), -CELL * 0.5 + TH * 0.5))
	am.surface_set_material(0, mat_floor)
	# плита потолка у верха клетки
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,
		_slab_arrays(Vector3(CELL, TH, CELL), CELL * 0.5 - TH * 0.5))
	am.surface_set_material(1, mat_ceil)
	return am


func _build_wall_mesh(mat_wall: StandardMaterial3D) -> BoxMesh:
	var bm := BoxMesh.new()
	bm.size = Vector3(CELL, CELL, CELL)
	bm.material = mat_wall
	return bm


# --- библиотека -----------------------------------------------------------
func _build_library() -> MeshLibrary:
	var lib := MeshLibrary.new()

	var mat_wall := _make_material(TEX_WALL)
	var mat_floor := _make_material(TEX_FLOOR)
	var mat_ceil := _make_material(TEX_CEIL)

	# floor (id 0): пол + потолок, 2 коллизии-плиты
	lib.create_item(FLOOR_ID)
	lib.set_item_name(FLOOR_ID, "floor")
	lib.set_item_mesh(FLOOR_ID, _build_floor_mesh(mat_floor, mat_ceil))
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(CELL, TH, CELL)
	var ceil_shape := BoxShape3D.new()
	ceil_shape.size = Vector3(CELL, TH, CELL)
	lib.set_item_shapes(FLOOR_ID, [
		floor_shape, Transform3D(Basis(), Vector3(0, -CELL * 0.5 + TH * 0.5, 0)),
		ceil_shape, Transform3D(Basis(), Vector3(0, CELL * 0.5 - TH * 0.5, 0)),
	])

	# wall (id 1): сплошной куб + коллизия-куб
	lib.create_item(WALL_ID)
	lib.set_item_name(WALL_ID, "wall")
	lib.set_item_mesh(WALL_ID, _build_wall_mesh(mat_wall))
	var wall_shape := BoxShape3D.new()
	wall_shape.size = Vector3(CELL, CELL, CELL)
	lib.set_item_shapes(WALL_ID, [wall_shape, Transform3D.IDENTITY])

	return lib


# --- стартовый уровень ----------------------------------------------------
# Прямоугольная заливка пола.
func _fill(cells: Dictionary, x0: int, z0: int, x1: int, z1: int) -> void:
	for x in range(x0, x1 + 1):
		for z in range(z0, z1 + 1):
			cells[Vector2i(x, z)] = true


func _build_level(lib: MeshLibrary) -> void:
	var root := Node3D.new()
	root.name = "LevelDoom01"

	# --- свет + окружение (чтобы комнаты не были чёрными) ---
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation = Vector3(deg_to_rad(-55), deg_to_rad(35), 0)
	root.add_child(sun)
	sun.owner = root

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.05, 0.07)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.57, 0.62)
	env.ambient_light_energy = 0.7
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	root.add_child(we)
	we.owner = root

	# --- раскладка пола (в координатах сетки) ---
	var floor_cells: Dictionary = {}
	_fill(floor_cells, 0, 0, 5, 5)      # Комната A (6×6)
	_fill(floor_cells, 2, 6, 3, 8)      # Коридор (2×3)
	_fill(floor_cells, 0, 9, 4, 12)     # Комната B (5×4)

	# --- стены = клетки-соседи пола, которые сами не пол (8-связность) ---
	var wall_cells: Dictionary = {}
	for c: Vector2i in floor_cells.keys():
		for dx in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				if dx == 0 and dz == 0:
					continue
				var n := Vector2i(c.x + dx, c.y + dz)
				if not floor_cells.has(n):
					wall_cells[n] = true

	# --- GridMap ---
	var gm := GridMap.new()
	gm.name = "GridMap"
	gm.cell_size = Vector3(CELL, CELL, CELL)
	gm.mesh_library = lib
	gm.position = Vector3(0, LIFT, 0)   # верх пола → y≈0
	root.add_child(gm)
	gm.owner = root
	for c: Vector2i in floor_cells.keys():
		gm.set_cell_item(Vector3i(c.x, 0, c.y), FLOOR_ID)
	for c: Vector2i in wall_cells.keys():
		gm.set_cell_item(Vector3i(c.x, 0, c.y), WALL_ID)

	# --- спавн игрока (Комната A) ---
	var spawn := Marker3D.new()
	spawn.name = "PlayerSpawn"
	spawn.position = Vector3(_wx(2), 0.4, _wz(1))
	spawn.rotation = Vector3(0, PI, 0)  # лицом к +Z (вглубь, к выходу)
	root.add_child(spawn)
	spawn.owner = root

	# --- выход (дальний конец Комнаты B) ---
	_instance(root, "res://scenes/levels/level_exit.tscn", "LevelExit",
		Vector3(_wx(2), 0.0, _wz(12)))

	# --- враги ---
	_instance(root, "res://scenes/enemies/rusher.tscn", "Rusher",
		Vector3(_wx(4), 0.1, _wz(4)))
	_instance(root, "res://scenes/enemies/shooter.tscn", "Shooter",
		Vector3(_wx(1), 0.1, _wz(11)))
	_instance(root, "res://scenes/enemies/flyer.tscn", "Flyer",
		Vector3(_wx(2), 2.0, _wz(10)))

	# --- пикапы ---
	_instance(root, "res://scenes/pickups/ammo/ammo_pickup.tscn", "AmmoPickup",
		Vector3(_wx(1), 0.5, _wz(4)))
	_instance(root, "res://scenes/pickups/health/medikit.tscn", "Medikit",
		Vector3(_wx(3), 0.5, _wz(11)))

	# --- упаковка и сохранение ---
	var packed := PackedScene.new()
	var pack_err := packed.pack(root)
	if pack_err != OK:
		printerr("[kit] pack уровня не удался: ", pack_err)
		return
	var save_err := ResourceSaver.save(packed, LEVEL_PATH)
	if save_err != OK:
		printerr("[kit] сохранение уровня не удалось: ", save_err)


# центр клетки → мировые координаты (GridMap по X/Z в нуле, клетки центрируются)
func _wx(gx: int) -> float:
	return gx * CELL

func _wz(gz: int) -> float:
	return gz * CELL


# Инстанс сцены с установкой owner только на корне инстанса (иначе ломается инстансинг).
func _instance(root: Node, scene_path: String, node_name: String, pos: Vector3) -> void:
	var ps: PackedScene = load(scene_path)
	if ps == null:
		printerr("[kit] не загрузилась сцена: ", scene_path)
		return
	var inst := ps.instantiate()
	inst.name = node_name
	if inst is Node3D:
		(inst as Node3D).position = pos
	root.add_child(inst)
	inst.owner = root
