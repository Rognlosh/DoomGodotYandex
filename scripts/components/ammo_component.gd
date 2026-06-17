class_name AmmoComponent
extends Node
## Переиспользуемый компонент боеприпасов на игроке (сосед HealthComponent).
## Хранит типизированные пулы патронов (ключ — id типа). Оружие тянет из пула,
## пикап доливает. Знает только числа и шлёт ammo_changed наверх ("signal up") —
## HUD/оружие подписываются сами.

## Запас патронов типа изменился. (type, current, maximum) — для HUD и логики оружия.
signal ammo_changed(type: StringName, current: int, maximum: int)

## Описания пулов. Массив ресурсов AmmoType (Array[AmmoType] ≈ List<AmmoType>).
@export var ammo_types: Array[AmmoType] = []

# Текущий запас по типам: id -> int.
var _current: Dictionary = {}
# Максимум по типам: id -> int.
var _maximum: Dictionary = {}


func _ready() -> void:
	for ammo: AmmoType in ammo_types:
		if ammo == null:
			continue
		_maximum[ammo.id] = ammo.max_amount
		# clampi на случай, если start задали больше max.
		_current[ammo.id] = clampi(ammo.start_amount, 0, ammo.max_amount)


## Текущий запас типа (0, если тип неизвестен). get(key, default) ≈ GetValueOrDefault.
func get_ammo(type: StringName) -> int:
	return _current.get(type, 0)


## Максимум типа (0, если тип неизвестен).
func get_max(type: StringName) -> int:
	return _maximum.get(type, 0)


## Хватает ли amount патронов типа.
func has_ammo(type: StringName, amount: int) -> bool:
	return get_ammo(type) >= amount


## Списать amount патронов типа. true — если хватило и списали.
func consume(type: StringName, amount: int) -> bool:
	if not has_ammo(type, amount):
		return false
	_current[type] = get_ammo(type) - amount
	ammo_changed.emit(type, _current[type], get_max(type))
	return true


## Добавить amount патронов типа (кламп по максимуму). Возвращает, сколько реально
## добавили (0 — если тип неизвестен или запас уже полон).
func add_ammo(type: StringName, amount: int) -> int:
	if amount <= 0 or not _maximum.has(type):
		return 0
	var before: int = get_ammo(type)
	var after: int = clampi(before + amount, 0, get_max(type))
	var added: int = after - before
	if added > 0:
		_current[type] = after
		ammo_changed.emit(type, after, get_max(type))
	return added
