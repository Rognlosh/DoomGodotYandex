class_name HitStars
extends ParticleBurst3D
## Мульт-«pow»: жёлтые звёздочки в точке попадания по врагу.
## Тот же пул, что у дыма (ParticleBurst3D) — отличаются только текстура и настройки.
## Подключается к WeaponManager.damageable_hit (через main).

@export_group("Звёзды")
## Время жизни звёздочки, с.
@export var lifetime: float = 0.4
## Звёздочек за попадание.
@export var stars_per_hit: int = 6
## Размер звезды, м.
@export var star_size: float = 0.28
## Скорость разлёта, м/с.
@export var speed: float = 2.2
## Цвет звёзд.
@export var star_color: Color = Color(1.0, 0.86, 0.25, 1.0)


func _quad_size() -> Vector2:
	return Vector2(star_size, star_size)


func _configure_emitter(p: CPUParticles3D) -> void:
	p.amount = stars_per_hit
	p.lifetime = lifetime
	p.direction = Vector3(0.0, 0.0, -1.0)
	p.spread = 90.0
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.gravity = Vector3(0.0, 2.0, 0.0)  # лёгкий «всплыв» вверх — мультяшно
	p.damping_min = 1.0
	p.damping_max = 2.0
	p.color = star_color
	p.color_ramp = _fade_ramp(star_color)
	# Звёздочки стартуют под случайным углом и крутятся.
	p.angle_min = 0.0
	p.angle_max = 360.0
	p.angular_velocity_min = -360.0
	p.angular_velocity_max = 360.0
	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.3


func _make_texture() -> Texture2D:
	return _make_star_texture(5, 32)


# Пятиконечная звезда (белая на прозрачном). Растеризуем point-in-polygon. Ноль веса.
func _make_star_texture(points: int, s: int) -> Texture2D:
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 0.0, 0.0, 0.0))
	var cx := s * 0.5
	var cy := s * 0.5
	var r_out := s * 0.46
	var r_in := r_out * 0.42
	var verts: Array[Vector2] = []
	for i in points * 2:
		var ang := -PI / 2.0 + PI * float(i) / float(points)
		var rr := r_out if i % 2 == 0 else r_in
		verts.append(Vector2(cx + cos(ang) * rr, cy + sin(ang) * rr))
	for y in s:
		for x in s:
			if _in_poly(Vector2(x + 0.5, y + 0.5), verts):
				img.set_pixel(x, y, Color(1.0, 1.0, 1.0, 1.0))
	return ImageTexture.create_from_image(img)


# Чётно-нечётный тест принадлежности точки многоугольнику.
func _in_poly(pt: Vector2, verts: Array[Vector2]) -> bool:
	var inside := false
	var j := verts.size() - 1
	for i in verts.size():
		var a := verts[i]
		var b := verts[j]
		if (a.y > pt.y) != (b.y > pt.y):
			var xx := a.x + (pt.y - a.y) / (b.y - a.y) * (b.x - a.x)
			if pt.x < xx:
				inside = not inside
		j = i
	return inside
