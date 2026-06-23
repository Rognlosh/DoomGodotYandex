class_name EnemyFlyer
extends EnemyBase
## Летун: движется к цели в полном 3D (по высоте тоже), не падает.
## Атака — дальний бой файрболом, если назначен projectile_scene; иначе контактная
## (как у базы) — задел под будущего контактного летуна («череп» из DOOM).

@export_group("Полёт")
## На какой высоте цели держаться (центр игрока ~1.0, голова ~1.6).
@export var target_height_offset: float = 1.0
## Как быстро гасится вертикальная скорость, когда полётом не управляют
## (в атаке/простое) — чтобы летун завис, а не уплывал. Ед/с.
@export var hover_damp: float = 12.0

@export_group("Дальний бой")
## Снаряд-файрбол. Пусто — летун бьёт в упор (контактная атака базы).
@export var projectile_scene: PackedScene
## Высота точки прицела/вылета над origin (своим и цели), м.
@export var aim_height: float = 1.0
## Смещение точки вылета вперёд по направлению на цель, м.
@export var muzzle_forward: float = 0.6


# Летун не падает. Гасим вертикаль только когда движением не управляют
# (база зовёт _apply_gravity в IDLE/ATTACK). В CHASE _move_towards_target
# перезадаёт velocity целиком — поэтому здесь её не трогаем, конфликта нет.
func _apply_gravity(delta: float) -> void:
	velocity.y = move_toward(velocity.y, 0.0, hover_damp * delta)


func _move_towards_target(_delta: float) -> void:
	var to_target := _target.global_position \
		+ Vector3(0.0, target_height_offset, 0.0) - global_position
	var dir := to_target.normalized()
	velocity = dir * move_speed
	_face_dir(dir)  # _face_dir сам сплющивает до XZ — нужен лишь для выбора ракурса
	move_and_slide()


# Атака: файрбол, если назначен снаряд; иначе — контактная атака базы.
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
	super._on_death()  # стандартная смерть базы (стоп, коллизия off, анимация, таймер трупа)
	_drop_corpse_to_floor()


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
