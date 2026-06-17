class_name ParticleBurst3D
extends Node3D
## База для разовых «всплесков» частиц в точке попадания (дымок, звёзды-pow и т.п.).
## Пул переиспользуемых CPUParticles3D (CPU-частицы идут на всех рендерах, включая
## Compatibility/WebGL — без риска GPU-частиц). Текстуру и настройки эмиттера задаёт
## наследник через хуки. Вызывается через signal up: weapon.* → WeaponManager → main → spawn().

@export_group("Пул")
## Эмиттеров в пуле (переиспользуются по кругу).
@export var pool_size: int = 16
## Отступ от поверхности вдоль нормали (чтобы не утопало), м.
@export var surface_offset: float = 0.02

var _pool: Array[CPUParticles3D] = []
var _next: int = 0
var _mesh: QuadMesh
var _material: StandardMaterial3D


func _ready() -> void:
	_mesh = QuadMesh.new()
	_mesh.size = _quad_size()
	_material = StandardMaterial3D.new()
	_material.albedo_texture = _make_texture()
	# Биллборд для частиц: всегда лицом к камере.
	_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Цвет/альфа частицы (из CPUParticles) красят альбедо.
	_material.vertex_color_use_as_albedo = true
	_mesh.material = _material

	for _i in pool_size:
		var p := CPUParticles3D.new()
		p.mesh = _mesh
		p.emitting = false
		p.one_shot = true
		p.explosiveness = 1.0  # весь всплеск разом
		_configure_emitter(p)
		add_child(p)
		_pool.append(p)


## Сыграть всплеск в точке, развёрнутый по нормали поверхности.
## Подключается к WeaponManager.{surface_hit|damageable_hit}.
func spawn(position: Vector3, normal: Vector3) -> void:
	if _pool.is_empty():
		return
	var p := _pool[_next]
	_next = (_next + 1) % _pool.size()

	var n := normal.normalized() if normal.length() > 0.0 else Vector3.UP
	# Ставим в точку (с отступом) и разворачиваем -Z вдоль нормали — частицы летят от поверхности.
	p.global_position = position + n * surface_offset
	p.look_at(p.global_position + n, _pick_up(n))
	p.restart()  # перезапуск разовой эмиссии


# «Вверх» для look_at, не параллельный нормали (иначе вырожденный базис).
func _pick_up(n: Vector3) -> Vector3:
	return Vector3.RIGHT if absf(n.dot(Vector3.UP)) > 0.99 else Vector3.UP


# --- Хуки наследника ---

## Размер одной частицы (меш-квадрат), м.
func _quad_size() -> Vector2:
	return Vector2(0.12, 0.12)

## Текстура частицы (белая на прозрачном — красится цветом частицы).
func _make_texture() -> Texture2D:
	return null

## Настройка одного эмиттера (amount/lifetime/скорость/цвет/рампы).
func _configure_emitter(_p: CPUParticles3D) -> void:
	pass


# --- Утилиты для наследников ---

## Градиент альфы: от base к нулю (всплеск растворяется).
func _fade_ramp(base: Color) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, base)
	g.set_color(1, Color(base.r, base.g, base.b, 0.0))
	return g
