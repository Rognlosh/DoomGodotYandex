class_name ImpactSmoke
extends Node3D
## Эффект попадания по поверхности: короткий «дымок» в точке удара.
## Пул переиспользуемых CPUParticles3D (CPU-частицы идут на всех рендерах,
## включая Compatibility/WebGL — без риска, в отличие от GPU-частиц).
## Текстура клуба дыма генерится кодом (мягкое пятно) — ноль веса билда.
## Вызывается через signal up: weapon.surface_hit → WeaponManager → main → spawn().

@export_group("Эффект")
## Эмиттеров в пуле (переиспользуются по кругу). Пулемёт сыплет часто —
## при коротком времени жизни горстки хватает.
@export var pool_size: int = 16
## Время жизни одной «затяжки», с.
@export var lifetime: float = 0.45
## Частиц в одной затяжке.
@export var particles_per_puff: int = 8
## Размер частицы, м.
@export var particle_size: float = 0.12
## Скорость разлёта от стены, м/с.
@export var speed: float = 1.4
## Цвет дыма (альфа — стартовая прозрачность).
@export var smoke_color: Color = Color(0.6, 0.6, 0.62, 0.5)
## Отступ от поверхности вдоль нормали (от утопания в стену), м.
@export var surface_offset: float = 0.02

# Пул эмиттеров.
var _pool: Array[CPUParticles3D] = []
# Следующий слот пула (round-robin).
var _next: int = 0
# Общие для всех эмиттеров ресурсы (одна меш + материал + текстура).
var _mesh: QuadMesh
var _material: StandardMaterial3D


func _ready() -> void:
	_build_shared_resources()
	for _i in pool_size:
		var p := _make_emitter()
		add_child(p)
		_pool.append(p)


## Сыграть дымок в точке попадания, развёрнутый по нормали поверхности.
## Подключается к WeaponManager.surface_hit.
func spawn(position: Vector3, normal: Vector3) -> void:
	if _pool.is_empty():
		return
	var p := _pool[_next]
	_next = (_next + 1) % _pool.size()

	var n := normal.normalized() if normal.length() > 0.0 else Vector3.UP
	# Ставим в точку (с отступом) и разворачиваем -Z вдоль нормали — частицы летят от стены.
	p.global_position = position + n * surface_offset
	p.look_at(p.global_position + n, _pick_up(n))
	p.restart()  # перезапуск разовой эмиссии


# «Вверх» для look_at, не параллельный нормали (иначе вырожденный базис).
func _pick_up(n: Vector3) -> Vector3:
	return Vector3.RIGHT if absf(n.dot(Vector3.UP)) > 0.99 else Vector3.UP


func _build_shared_resources() -> void:
	_mesh = QuadMesh.new()
	_mesh.size = Vector2(particle_size, particle_size)

	_material = StandardMaterial3D.new()
	_material.albedo_texture = _make_smoke_texture()
	# Биллборд для частиц: всегда лицом к камере.
	_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Цвет/альфа частицы (из CPUParticles) красят альбедо.
	_material.vertex_color_use_as_albedo = true
	_mesh.material = _material


func _make_emitter() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.mesh = _mesh
	p.emitting = false
	p.one_shot = true
	p.explosiveness = 1.0  # вся «затяжка» разом
	p.amount = particles_per_puff
	p.lifetime = lifetime
	# Локально летят по -Z (после look_at — вдоль нормали) с разбросом в полусферу.
	p.direction = Vector3(0.0, 0.0, -1.0)
	p.spread = 60.0
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector3.ZERO
	p.damping_min = 1.5
	p.damping_max = 2.5
	# Цвет с затуханием альфы к концу жизни.
	p.color = smoke_color
	p.color_ramp = _make_fade_ramp(smoke_color)
	# Лёгкий рост размера.
	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.2
	p.scale_amount_curve = _make_grow_curve()
	return p


# Градиент альфы: от стартовой к нулю (дым растворяется).
func _make_fade_ramp(base: Color) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, base)
	g.set_color(1, Color(base.r, base.g, base.b, 0.0))
	return g


# Кривая роста размера по времени жизни.
func _make_grow_curve() -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.5))
	c.add_point(Vector2(1.0, 1.6))
	return c


# Мягкое круглое пятно (радиальное затухание альфы). Ноль веса билда.
func _make_smoke_texture() -> Texture2D:
	var s := 32
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var center := Vector2(s * 0.5, s * 0.5)
	var radius := s * 0.5
	for y in s:
		for x in s:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(center) / radius
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = a * a  # мягче к краю
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	return ImageTexture.create_from_image(img)
