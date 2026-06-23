class_name Explosion
extends ParticleBurst3D
## Взрыв снаряда: оранжевая вспышка-облако. Тот же пул, что у дыма/звёзд
## (ParticleBurst3D) — отличается текстурой и настройками. Узел в main.tscn,
## группа "explosions"; снаряд находит его по группе (как CombatAudio).

@export_group("Взрыв")
@export var lifetime: float = 0.55
@export var particles: int = 20
@export var particle_size: float = 0.6
@export var speed: float = 6.0
@export var core_color: Color = Color(1.0, 0.62, 0.18, 1.0)


func _ready() -> void:
	add_to_group(&"explosions")
	super._ready()   # база строит пул эмиттеров через хуки ниже


func _quad_size() -> Vector2:
	return Vector2(particle_size, particle_size)


func _configure_emitter(p: CPUParticles3D) -> void:
	p.amount = particles
	p.lifetime = lifetime
	p.direction = Vector3(0.0, 0.0, -1.0)
	p.spread = 180.0            # во все стороны от точки удара
	p.initial_velocity_min = speed * 0.3
	p.initial_velocity_max = speed
	p.gravity = Vector3(0.0, 1.0, 0.0)
	p.damping_min = 2.0
	p.damping_max = 4.0
	p.color = core_color
	p.color_ramp = _fade_ramp(core_color)
	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.4
	p.scale_amount_curve = _grow_curve()


func _make_texture() -> Texture2D:
	var s := 32
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var c := Vector2(s * 0.5, s * 0.5)
	var radius := s * 0.5
	for y in s:
		for x in s:
			var dd := Vector2(x + 0.5, y + 0.5).distance_to(c) / radius
			var a := clampf(1.0 - dd, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a * a))
	return ImageTexture.create_from_image(img)


func _grow_curve() -> Curve:
	var cv := Curve.new()
	cv.add_point(Vector2(0.0, 0.6))
	cv.add_point(Vector2(1.0, 1.7))
	return cv
