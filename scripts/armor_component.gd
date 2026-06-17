class_name ArmorComponent
extends Node
## Броня игрока — отдельное звено ПЕРЕД здоровьем (модель DOOM). Поглощает долю
## урона, пока есть запас; на нуле — урон идёт целиком в HP. Класс задаёт долю
## поглощения (зелёная 1/3, синяя 1/2). Как HealthComponent — знает только числа
## и шлёт armor_changed наверх («signal up»); HUD подписывается сам.

## Запас брони изменился. (current, maximum) — для HUD.
signal armor_changed(current: float, maximum: float)

## Жёсткий потолок запаса брони.
@export var max_armor: float = 200.0
## Доля поглощаемого урона по классам: индекс = armor_class (0 — брони нет).
## DOOM: зелёная (1) — 1/3, синяя (2) — 1/2.
@export var absorption_by_class: Array[float] = [0.0, 1.0 / 3.0, 0.5]

var _armor: float = 0.0
var _class: int = 0

## Текущий запас — только чтение снаружи.
var current_armor: float:
	get:
		return _armor
## Текущий класс брони — только чтение.
var armor_class: int:
	get:
		return _class


func _ready() -> void:
	armor_changed.emit(_armor, max_armor)


## Поглотить часть урона. Возвращает остаток, который идёт дальше в HP.
func absorb(damage: float) -> float:
	if damage <= 0.0 or _armor <= 0.0 or _class <= 0:
		return damage
	var save: float = damage * _absorption(_class)
	if save > _armor:
		save = _armor  # брони не хватило — поглощаем сколько есть
	_armor -= save
	if _armor <= 0.0:
		_armor = 0.0
		_class = 0  # пул иссяк — класс сбрасывается
	armor_changed.emit(_armor, max_armor)
	return damage - save


## Бонус (шлем): +amount аддитивно до max_armor. Если брони не было — даёт
## минимальный класс (зелёный). true — если что-то добавили.
func add_bonus(amount: float) -> bool:
	if amount <= 0.0 or _armor >= max_armor:
		return false
	_armor = minf(_armor + amount, max_armor)
	if _class <= 0:
		_class = 1
	armor_changed.emit(_armor, max_armor)
	return true


## Комплект (зелёная/синяя): установить запас до points класса klass, но только
## если текущий меньше points (DOOM: зелёную не подобрать при брони ≥100). true — применилось.
func give_armor(points: float, klass: int) -> bool:
	if _armor >= points:
		return false
	_armor = minf(points, max_armor)
	_class = klass
	armor_changed.emit(_armor, max_armor)
	return true


func _absorption(klass: int) -> float:
	if klass >= 0 and klass < absorption_by_class.size():
		return absorption_by_class[klass]
	return 0.0
