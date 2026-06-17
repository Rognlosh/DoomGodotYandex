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

## Обычный максимум здоровья. Стартовое значение берётся отсюда же.
## Лечение без оверхила упирается в него.
@export var max_health: float = 30.0
## Жёсткий потолок при оверхиле. 0 или ≤ max_health — оверхил выключен
## (у врагов оставляем 0 — поведение не меняется).
@export var overheal_max: float = 0.0
## Скорость «таяния» оверхила обратно к max_health, ед./с. 0 — выключено.
@export var overheal_decay: float = 0.0

var _current_health: float

## Текущее здоровье — только чтение снаружи (как get-only property в C#).
var current_health: float:
	get:
		return _current_health


func _ready() -> void:
	_current_health = max_health


func _process(delta: float) -> void:
	# Оверхил (HP выше обычного максимума) плавно тает обратно к max_health.
	if overheal_decay <= 0.0 or _current_health <= max_health:
		return
	_current_health = maxf(max_health, _current_health - overheal_decay * delta)
	health_changed.emit(_current_health, max_health)


## Нанести урон. Уже мёртвый — игнорируем.
func take_damage(amount: float) -> void:
	if _current_health <= 0.0:
		return
	# Верхняя граница — потолок оверхила: урон не должен «срезать» оверхил до max_health.
	_current_health = clampf(_current_health - amount, 0.0, _cap())
	health_changed.emit(_current_health, max_health)
	if _current_health <= 0.0:
		died.emit()


## Полечить. allow_overheal — можно ли превысить обычный максимум (до overheal_max).
## Возвращает true, если что-то реально добавили (для пикапа: подобрался/нет).
func heal(amount: float, allow_overheal: bool = false) -> bool:
	if amount <= 0.0 or not is_alive():
		return false
	var ceiling: float = _cap() if allow_overheal else max_health
	# Никогда не уменьшаем: если HP уже выше потолка (остаточный оверхил) — стоим.
	var before: float = _current_health
	var after: float = clampf(before + amount, before, maxf(ceiling, before))
	if after <= before:
		return false
	_current_health = after
	health_changed.emit(_current_health, max_health)
	return true


## Удобно для проверок в ИИ.
func is_alive() -> bool:
	return _current_health > 0.0


# Жёсткий потолок здоровья с учётом оверхила.
func _cap() -> float:
	return maxf(overheal_max, max_health)
