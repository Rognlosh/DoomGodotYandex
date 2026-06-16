class_name HealthComponent
extends Node
## Переиспользуемый компонент здоровья — один и тот же для врага и игрока.
## Хранит только числа и сообщает об изменениях сигналами. Что значит
## «получить урон» и «умереть» — решает владелец, подписавшись на сигналы
## (принцип «signal up»): враг — стоп ИИ и труп, игрок — game over и HUD.

## Здоровье изменилось. (current, maximum) — для HUD-баров и пр.
signal health_changed(current: float, maximum: float)
## Здоровье достигло нуля. Владелец сам решает, что делать.
signal died

## Максимум здоровья. Стартовое значение берётся отсюда же.
@export var max_health: float = 30.0

var _current_health: float

## Текущее здоровье — только чтение снаружи (как get-only property в C#).
var current_health: float:
	get:
		return _current_health


func _ready() -> void:
	_current_health = max_health


## Нанести урон. Уже мёртвый — игнорируем.
func take_damage(amount: float) -> void:
	if _current_health <= 0.0:
		return
	_current_health = clampf(_current_health - amount, 0.0, max_health)
	health_changed.emit(_current_health, max_health)
	if _current_health <= 0.0:
		died.emit()


## Удобно для проверок в ИИ.
func is_alive() -> bool:
	return _current_health > 0.0
