class_name ImpactSmoke
extends ParticleBurst3D
## Дымок по неуязвимой поверхности (стена/пол). Настройки поверх ParticleBurst3D.
## Подключается к WeaponManager.surface_hit (через main).

@export_group("Дым")
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


func _quad_size() -> Vector2:
	return Vector2(particle_size, particle_size)


func _configure_emitter(p: CPUParticles3D) -> void:
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
	p.color = smoke_color
	p.color_ramp = _fade_ramp(smoke_color)
	# Лёгкий рост размера.
	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.2
	p.scale_amount_curve = _grow_curve()


# Мягкое круглое пятно (радиальное затухание альфы). Ноль веса билда.
func _make_texture() -> Texture2D:
	var s := 32
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var center := Vector2(s * 0.5, s * 0.5)
	var radius := s * 0.5
	for y in s:
		for x in s:
			var dd := Vector2(x + 0.5, y + 0.5).distance_to(center) / radius
			var a := clampf(1.0 - dd, 0.0, 1.0)
			a = a * a  # мягче к краю
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	return ImageTexture.create_from_image(img)


# Кривая роста размера по времени жизни.
func _grow_curve() -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.5))
	c.add_point(Vector2(1.0, 1.6))
	return c
