class_name ArmorPickup
extends PickupBase
## Пикап брони. mode выбирает поведение (логика — в ArmorComponent):
##  BONUS — +amount аддитивно (шлем), сохраняет класс;
##  FULL  — комплект (зелёная/синяя): установить запас до amount класса armor_class.

enum Mode { BONUS, FULL }

## Тип пикапа: бонус или полный комплект.
@export var mode: Mode = Mode.FULL
## Очки брони (для FULL — целевой запас; для BONUS — прибавка).
@export var amount: float = 100.0
## Класс для FULL (1 — зелёная 1/3, 2 — синяя 1/2). Для BONUS не используется.
@export var armor_class: int = 1


func _apply(body: Node3D) -> bool:
	# Метод-конвенция add_armor на теле игрока (как add_ammo/heal).
	if not body.has_method(&"add_armor"):
		return false
	return body.add_armor(amount, armor_class, mode == Mode.FULL)
