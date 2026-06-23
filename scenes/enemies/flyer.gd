class_name EnemyFlyer
extends EnemyBase
## Летун-бомбардир: держится ВЫСОКО над целью и на горизонтальном отступе, зависает
## и стреляет файрболом; периодически смещается вбок (страйф), не прекращая огонь.
## Не таранит. Если projectile_scene не задан — контактная атака базы (задел под
## будущего контактного летуна — «череп» из DOOM).

@export_group("Полёт")
## На какой высоте над целью держаться (бомбардировка сверху), м.
@export var hover_height: float = 5.0
## Желаемая горизонтальная дистанция до цели в атаке (отступ — не таранит), м.
@export var standoff_range: float = 9.0
## Жёсткость удержания высоты (выше — резче доводит до hover_height).
@export var height_gain: float = 2.0
## Как быстро гасится вертикаль, когда полётом не управляют (простой). Ед/с.
@export var hover_damp: float = 12.0

@export_group("Страйф")
## Скорость смещения вбок во время стрельбы, м/с.
@export var strafe_speed: float = 2.2
## Базовый интервал смены направления страйфа (с разбросом ±40%), с.
@export var strafe_interval: float = 1.4

@export_group("Дальний бой")
## Снаряд-файрбол. Пусто — летун бьёт в упор (контактная атака базы).
@export var projectile_scene: PackedScene
## Высота точки прицела/вылета над origin (своим и цели), м.
@export var aim_height: float = 1.0
## Смещение точки вылета вперёд по направлению на цель, м.
@export var muzzle_forward: float = 0.6

# Направление страйфа: -1 / 0 (висит) / +1; меняется по таймеру.
var _strafe_dir: float = 0.0
var _strafe_timer: float = 0.0


# Летун не падает. Гасим вертикаль только когда полётом не управляют (база зовёт
# _apply_gravity в IDLE). В CHASE/ATTACK velocity задаётся целиком ниже.
func _apply_gravity(delta: float) -> void:
	velocity.y = move_toward(velocity.y, 0.0, hover_damp * delta)


# Преследование: летим к точке ВЫСОКО над целью, гася сближение у standoff_range.
func _move_towards_target(_delta: float) -> void:
	var horiz := _flat_to_target()
	var hdist := horiz.length()
	var hdir := horiz.normalized() if hdist > 0.01 else Vector3.FORWARD
	# Сближаемся, пока дальше отступа; внутри — притормаживаем (плавно у границы).
	var approach := hdir * clampf(hdist - standoff_range, -1.0, 1.0) * move_speed
	velocity = Vector3(approach.x, _climb_velocity(), approach.z)
	_face_dir(hdir)
	move_and_slide()


# Движение в атаке: зависание на высоте + удержание отступа + периодический страйф.
# Не таранит; стрельбу при этом не прекращает (её делает _state_attack базы).
func _attack_movement(delta: float) -> void:
	if _target == null:
		velocity = Vector3.ZERO
		return
	var horiz := _flat_to_target()
	var hdist := horiz.length()
	var hdir := horiz.normalized() if hdist > 0.01 else Vector3.FORWARD
	# Мягко держим горизонтальный отступ: близко → назад, далеко → вперёд.
	var move := hdir * clampf(hdist - standoff_range, -1.0, 1.0) * move_speed
	# Страйф вбок (перпендикуляр в плоскости XZ); направление меняется по таймеру,
	# иногда 0 — просто висит.
	_strafe_timer -= delta
	if _strafe_timer <= 0.0:
		_strafe_timer = strafe_interval * randf_range(0.6, 1.4)
		_strafe_dir = [-1.0, 0.0, 1.0].pick_random()
	var side := Vector3(hdir.z, 0.0, -hdir.x)
	move += side * _strafe_dir * strafe_speed
	velocity = Vector3(move.x, _climb_velocity(), move.z)


# Файрбол, если назначен снаряд; иначе — контактная атака базы.
func _perform_attack() -> void:
	if projectile_scene == null:
		super._perform_attack()
		return
	_sprite.play(&"attack")
	if _target == null:
		return
	# Стена закрыла линию — не плюём в стену впустую.
	if not _has_line_of_sight():
		return
	var muzzle := global_position + Vector3.UP * aim_height
	var aim_at := _target.global_position + Vector3.UP * aim_height
	var dir := (aim_at - muzzle).normalized()
	muzzle += dir * muzzle_forward
	Projectile.launch(projectile_scene, self, muzzle, dir, get_rid())


func _on_death() -> void:
	super._on_death()  # стандартная смерть базы (+ запуск трупа, если убит взрывом)
	if not _launched:  # запущенный взрывом труп падает сам — на пол не тащим
		_drop_corpse_to_floor()


# --- Вспомогательное ---

# Горизонтальный вектор от летуна к цели (XZ, без высоты).
func _flat_to_target() -> Vector3:
	var d := _target.global_position - global_position
	return Vector3(d.x, 0.0, d.z)


# Вертикальная скорость для удержания hover_height над целью.
func _climb_velocity() -> float:
	var desired_y := _target.global_position.y + hover_height
	return clampf((desired_y - global_position.y) * height_gain, -move_speed, move_speed)


# Мёртвый летун не падает сам (физика на State.DEAD заглушена) — роняем труп
# вручную: луч вниз ищет пол, Tween опускает тело на него.
func _drop_corpse_to_floor() -> void:
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3.UP * 0.5
	var to := global_position + Vector3.DOWN * 100.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return
	var floor_y: float = hit["position"].y
	var fall_time := maxf(0.15, (global_position.y - floor_y) * 0.08)
	var tween := create_tween()
	var step := tween.tween_property(self, "global_position:y", floor_y, fall_time)
	step.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
