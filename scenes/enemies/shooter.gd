class_name EnemyShooter
extends EnemyBase
## Стрелок: дальний бой хитсканом. Переопределяет только _perform_attack.
## Большой attack_range — бьёт издалека и стоит на месте (стрейф/кайтинг — позже).
## Промахивается, если стену закрыла линия видимости или просто не повезло.

@export_group("Стрелок")
## Шанс попасть при чистой линии видимости (думовский разброс точности).
@export_range(0.0, 1.0) var hit_chance: float = 0.6


func _perform_attack() -> void:
	_sprite.play(&"attack")
	if _target == null:
		return
	# Стена встала между нами после входа в атаку — выстрел в молоко.
	if not _has_line_of_sight():
		return
	# randf() -> float в [0, 1). Не повезло — промах, как у думовских зомби.
	if randf() <= hit_chance and _target.has_method("take_damage"):
		_target.take_damage(attack_damage)
