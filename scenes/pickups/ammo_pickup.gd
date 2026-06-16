class_name AmmoPickup
extends PickupBase
## Пикап патронов: доливает запас определённого типа игроку.
## Тип/количество — в инспекторе. Базу (Area3D, обнаружение, вращение,
## самоуничтожение) даёт PickupBase; здесь только эффект.

## Какой тип патронов даёт пикап.
@export var ammo_type: StringName = &"bullets"
## Сколько патронов даёт.
@export var amount: int = 20


func _apply(body: Node3D) -> bool:
	# Метод-конвенция на теле игрока: add_ammo делегирует в AmmoComponent
	# (как take_damage — в HealthComponent). Источник не знает о внутренностях цели.
	if not body.has_method(&"add_ammo"):
		return false
	var added: int = body.add_ammo(ammo_type, amount)
	# Ничего не добавилось (запас полон) — пикап остаётся лежать.
	return added > 0
