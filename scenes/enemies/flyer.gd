class_name EnemyFlyer
extends EnemyBase
## Летун: движется к цели в полном 3D (по высоте тоже), не падает.
## Переопределяет движение и гравитацию; атака — контактная (как у базы).
## Стрельбу снарядами добавим отдельной фичей (Имп/Какодемон-файрбол).

@export_group("Полёт")
## На какой высоте цели держаться (центр игрока ~1.0, голова ~1.6).
@export var target_height_offset: float = 1.0
## Как быстро гасится вертикальная скорость, когда полётом не управляют
## (в атаке/простое) — чтобы летун завис, а не уплывал. Ед/с.
@export var hover_damp: float = 12.0


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
