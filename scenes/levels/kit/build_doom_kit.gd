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
##      спавн/выход/врагов/пикапы и сохраняет level_E1_L1.tscn.
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
const ENTITIES_MESHLIB_PATH := "res://scenes/levels/kit/doom_entities.tres"
const LEVEL_PATH := "res://scenes/levels/level_E1_L1.tscn"

# id предметов в MeshLibrary
const FLOOR_ID := 0
const WALL_ID := 1
const CEILING_ID := 2
const PILLAR_ID := 3
const DOORARCH_ID := 4

# вертикальные смещения плит внутри клетки (от центра меша)
const FLOOR_OFF := -CELL * 0.5 + TH * 0.5   # плита пола у низа клетки
const CEIL_OFF := CELL * 0.5 - TH * 0.5     # плита потолка у верха клетки

# колонна (pillar)
const COL_W := 1.2                          # сторона колонны
# дверной проём (door_arch): косяки по бокам + перемычка сверху, проём посередине
const POST_W := 1.0                         # ширина косяка
const POST_X := CELL * 0.5 - POST_W * 0.5   # центр косяка по X (1.5)
const OPEN_TOP := 1.0                       # верх проёма (локально), низ — пол
const LINTEL_H := CELL * 0.5 - OPEN_TOP     # высота перемычки (от OPEN_TOP до верха)
const LINTEL_CY := (OPEN_TOP + CELL * 0.5) * 0.5  # центр перемычки по Y
const OPEN_W := CELL - 2.0 * POST_W         # ширина проёма (2.0)

# --- маркеры сущностей (слой Entities) ------------------------------------
const MARKER_SIZE := 3.6   # размер плитки-маркера (чуть меньше клетки)
const MARKER_Y := 0.05     # приподнят над полом, чтобы не z-fight
const ICON_DIR := "res://assets/textures/entities/"
# [id, имя в палитре, файл иконки]. id совпадают с EntitySpawner.SCENES.
const MARKERS := [
	[0, "spawn", "icon_spawn.png"],
	[1, "exit", "icon_exit.png"],
	[2, "enemy_rusher", "icon_rusher.png"],
	[3, "enemy_shooter", "icon_shooter.png"],
	[4, "enemy_flyer", "icon_flyer.png"],
	[5, "pickup_ammo", "icon_ammo.png"],
	[6, "pickup_shells", "icon_shells.png"],
	[7, "pickup_health_bonus", "icon_health_bonus.png"],
	[8, "pickup_stimpack", "icon_stimpack.png"],
	[9, "pickup_medikit", "icon_medikit.png"],
	[10, "pickup_soulsphere", "icon_soulsphere.png"],
	[11, "pickup_armor_bonus", "icon_armor_bonus.png"],
	[12, "pickup_armor_green", "icon_armor_green.png"],
	[13, "pickup_armor_blue", "icon_armor_blue.png"],
	[14, "pickup_weapon_shotgun", "icon_weapon_shotgun.png"],
	[15, "pickup_weapon_machinegun", "icon_weapon_machinegun.png"],
	[16, "pickup_weapon_rocket", "icon_weapon_rocket.png"],
]


func _run() -> void:
	print("[kit] сборка началась")
	var lib := _build_library()
	if ResourceSaver.save(lib, MESHLIB_PATH) != OK:
		printerr("[kit] не удалось сохранить кит-библиотеку")
		return
	# Перечитываем с диска: тогда уровень СОШЛЁТСЯ на файл (ext_resource), а не
	# встроит копию библиотеки в .tscn (иначе правки doom_kit.tres не видны в палитре).
	lib = load(MESHLIB_PATH) as MeshLibrary
	print("[kit] кит сохранён → ", MESHLIB_PATH)

	var ents := _build_entities_library()
	if ResourceSaver.save(ents, ENTITIES_MESHLIB_PATH) != OK:
		printerr("[kit] не удалось сохранить doom_entities")
		return
	ents = load(ENTITIES_MESHLIB_PATH) as MeshLibrary
	print("[kit] маркеры сущностей сохранены → ", ENTITIES_MESHLIB_PATH)

	# Уровень не перезаписываем, если он уже есть — твои правки останутся целы.
	if FileAccess.file_exists(LEVEL_PATH):
		print("[kit] %s уже есть — уровень НЕ тронут, обновлены только библиотеки." % LEVEL_PATH)
	else:
		_build_level(lib, ents)
		print("[kit] стартовый уровень создан → ", LEVEL_PATH)

	# обновить FileSystem-док, чтобы новые файлы появились сразу
	var fs := EditorInterface.get_resource_filesystem()
	if fs:
		fs.scan()
	print("[kit] готово.")


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


# Плита (пол или потолок) — один меш-поверхность с материалом.
func _slab_mesh(mat: StandardMaterial3D, y_offset: float) -> ArrayMesh:
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,
		_slab_arrays(Vector3(CELL, TH, CELL), y_offset))
	am.surface_set_material(0, mat)
	return am


# Массивы BoxMesh, сдвинутые на произвольный вектор (для составных предметов).
func _box_arrays(size: Vector3, offset: Vector3) -> Array:
	var bm := BoxMesh.new()
	bm.size = size
	var arr: Array = bm.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	for i in verts.size():
		verts[i] = verts[i] + offset
	arr[Mesh.ARRAY_VERTEX] = verts
	return arr


func _box_shape(size: Vector3) -> BoxShape3D:
	var s := BoxShape3D.new()
	s.size = size
	return s


# Составной меш из коробок. parts: [[Vector3 size, Vector3 offset, Material], ...]
func _composite_mesh(parts: Array) -> ArrayMesh:
	var am := ArrayMesh.new()
	for i in parts.size():
		var p: Array = parts[i]
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _box_arrays(p[0], p[1]))
		am.surface_set_material(i, p[2])
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

	# floor (id 0): плита пола снизу клетки (потолок вынесен в отдельный предмет)
	lib.create_item(FLOOR_ID)
	lib.set_item_name(FLOOR_ID, "floor")
	lib.set_item_mesh(FLOOR_ID, _slab_mesh(mat_floor, FLOOR_OFF))
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(CELL, TH, CELL)
	lib.set_item_shapes(FLOOR_ID, [floor_shape, Transform3D(Basis(), Vector3(0, FLOOR_OFF, 0))])

	# wall (id 1): сплошной куб + коллизия-куб
	lib.create_item(WALL_ID)
	lib.set_item_name(WALL_ID, "wall")
	lib.set_item_mesh(WALL_ID, _build_wall_mesh(mat_wall))
	var wall_shape := BoxShape3D.new()
	wall_shape.size = Vector3(CELL, CELL, CELL)
	lib.set_item_shapes(WALL_ID, [wall_shape, Transform3D.IDENTITY])

	# ceiling (id 2): плита потолка сверху клетки. Рисуется на отдельном GridMap,
	# который прячется в редакторе (чтобы не мешал расстановке сверху).
	lib.create_item(CEILING_ID)
	lib.set_item_name(CEILING_ID, "ceiling")
	lib.set_item_mesh(CEILING_ID, _slab_mesh(mat_ceil, CEIL_OFF))
	var ceil_shape := BoxShape3D.new()
	ceil_shape.size = Vector3(CELL, TH, CELL)
	lib.set_item_shapes(CEILING_ID, [ceil_shape, Transform3D(Basis(), Vector3(0, CEIL_OFF, 0))])

	# pillar (id 3): пол + колонна по центру (укрытие). Пол под ногами, колонна блокирует.
	lib.create_item(PILLAR_ID)
	lib.set_item_name(PILLAR_ID, "pillar")
	lib.set_item_mesh(PILLAR_ID, _composite_mesh([
		[Vector3(CELL, TH, CELL), Vector3(0, FLOOR_OFF, 0), mat_floor],
		[Vector3(COL_W, CELL, COL_W), Vector3.ZERO, mat_wall],
	]))
	lib.set_item_shapes(PILLAR_ID, [
		_box_shape(Vector3(CELL, TH, CELL)), Transform3D(Basis(), Vector3(0, FLOOR_OFF, 0)),
		_box_shape(Vector3(COL_W, CELL, COL_W)), Transform3D.IDENTITY,
	])

	# door_arch (id 4): пол + два косяка по X + перемычка сверху; проём по центру (вдоль Z).
	# Ставится в линию стены вместо куба; поворотом клетки меняешь направление прохода.
	lib.create_item(DOORARCH_ID)
	lib.set_item_name(DOORARCH_ID, "door_arch")
	lib.set_item_mesh(DOORARCH_ID, _composite_mesh([
		[Vector3(CELL, TH, CELL), Vector3(0, FLOOR_OFF, 0), mat_floor],
		[Vector3(POST_W, CELL, CELL), Vector3(-POST_X, 0, 0), mat_wall],
		[Vector3(POST_W, CELL, CELL), Vector3(POST_X, 0, 0), mat_wall],
		[Vector3(OPEN_W, LINTEL_H, CELL), Vector3(0, LINTEL_CY, 0), mat_wall],
	]))
	lib.set_item_shapes(DOORARCH_ID, [
		_box_shape(Vector3(CELL, TH, CELL)), Transform3D(Basis(), Vector3(0, FLOOR_OFF, 0)),
		_box_shape(Vector3(POST_W, CELL, CELL)), Transform3D(Basis(), Vector3(-POST_X, 0, 0)),
		_box_shape(Vector3(POST_W, CELL, CELL)), Transform3D(Basis(), Vector3(POST_X, 0, 0)),
		_box_shape(Vector3(OPEN_W, LINTEL_H, CELL)), Transform3D(Basis(), Vector3(0, LINTEL_CY, 0)),
	])

	return lib


# --- библиотека маркеров сущностей ----------------------------------------
# Маркер — плоская плитка-декаль с иконкой (видна сверху в редакторе), без
# коллизии. В игре EntitySpawner заменяет её на настоящую сцену.
func _marker_mesh(icon_file: String) -> PlaneMesh:
	var pm := PlaneMesh.new()
	pm.size = Vector2(MARKER_SIZE, MARKER_SIZE)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(ICON_DIR + icon_file)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED  # цвет иконки как есть
	pm.material = mat
	return pm


func _build_entities_library() -> MeshLibrary:
	var lib := MeshLibrary.new()
	for m in MARKERS:
		var id: int = m[0]
		lib.create_item(id)
		lib.set_item_name(id, m[1])
		lib.set_item_mesh(id, _marker_mesh(m[2]))
		lib.set_item_mesh_transform(id, Transform3D(Basis(), Vector3(0, MARKER_Y, 0)))
	return lib


# --- стартовый уровень ----------------------------------------------------
# Прямоугольная заливка пола.
func _fill(cells: Dictionary, x0: int, z0: int, x1: int, z1: int) -> void:
	for x in range(x0, x1 + 1):
		for z in range(z0, z1 + 1):
			cells[Vector2i(x, z)] = true


func _build_level(lib: MeshLibrary, ents: MeshLibrary) -> void:
	var root := Node3D.new()
	root.name = "LevelE1L1"

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
	# Центрируем по X/Z, но НЕ по Y: иначе клетка смещается на полклетки вверх
	# и пол оказывается на ~2 м выше спавна (всё спавнится «под уровнем»).
	gm.cell_center_x = true
	gm.cell_center_y = false
	gm.cell_center_z = true
	gm.mesh_library = lib
	gm.position = Vector3(0, LIFT, 0)   # верх пола → y≈0
	root.add_child(gm)
	gm.owner = root
	for c: Vector2i in floor_cells.keys():
		gm.set_cell_item(Vector3i(c.x, 0, c.y), FLOOR_ID)
	for c: Vector2i in wall_cells.keys():
		gm.set_cell_item(Vector3i(c.x, 0, c.y), WALL_ID)

	# --- Потолок отдельным GridMap со скриптом CeilingGridMap ---
	# В редакторе он скрыт; в игре сам повторяет пол. Клетки тут не рисуем —
	# скрипт строит потолок по полу в рантайме (включая дорисованное вручную).
	var ceil_gm := GridMap.new()
	ceil_gm.name = "Ceiling"
	ceil_gm.cell_size = Vector3(CELL, CELL, CELL)
	ceil_gm.cell_center_x = true
	ceil_gm.cell_center_y = false
	ceil_gm.cell_center_z = true
	ceil_gm.mesh_library = lib
	ceil_gm.position = Vector3(0, LIFT, 0)
	ceil_gm.set_script(load("res://scripts/levels/ceiling_gridmap.gd"))
	root.add_child(ceil_gm)
	ceil_gm.owner = root

	# --- Слой сущностей (Entities) со скриптом EntitySpawner ---
	# Пустой, готов к покраске маркерами (спавн/выход/враги/пикапы).
	# В игре маркеры превращаются в настоящие сцены, сами маркеры прячутся.
	var ent_gm := GridMap.new()
	ent_gm.name = "Entities"
	ent_gm.cell_size = Vector3(CELL, CELL, CELL)
	ent_gm.cell_center_x = true
	ent_gm.cell_center_y = false
	ent_gm.cell_center_z = true
	ent_gm.mesh_library = ents
	ent_gm.set_script(load("res://scripts/levels/entity_spawner.gd"))
	root.add_child(ent_gm)
	ent_gm.owner = root

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


# центр клетки → мировые координаты. X/Z центрированы (+полклетки),
# по Y центрирование выключено, поэтому объекты ставим на верх пола (y≈0).
func _wx(gx: int) -> float:
	return gx * CELL + CELL * 0.5

func _wz(gz: int) -> float:
	return gz * CELL + CELL * 0.5


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
