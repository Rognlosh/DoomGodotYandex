class_name HealthPickup
extends PickupBase
## Пикап аптечки: лечит игрока. allow_overheal — можно ли превысить обычный
## максимум (бонус-склянка/сфера души); иначе лечит только до обычного максимума.
## Базу (Area3D, обнаружение, вращение, самоуничтожение) даёт PickupBase.

## Сколько лечит.
@export var heal_amount: float = 25.0
## Разрешён ли оверхил (HP выше обычного максимума).
@export var allow_overheal: bool = false


func _apply(body: Node3D) -> bool:
	# Метод-конвенция на теле игрока (как add_ammo): heal делегирует в HealthComponent.
	if not body.has_method(&"heal"):
		return false
	# false (HP уже на нужном потолке) — пикап остаётся лежать.
	return body.heal(heal_amount, allow_overheal)
