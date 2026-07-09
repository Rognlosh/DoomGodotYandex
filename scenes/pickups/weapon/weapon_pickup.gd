class_name WeaponPickup
extends PickupBase
## Пикап оружия: выдаёт игроку ствол слота (и, опц., немного патронов к нему,
## как в DOOM). Базу (Area3D, обнаружение, самоуничтожение) даёт PickupBase;
## здесь только эффект.

## Слот выдаваемого ствола (совпадает с @export slot у соответствующего Weapon).
@export var slot: int = 3
## Тип патронов, добавляемых вместе со стволом. Пусто или amount 0 — не давать.
@export var ammo_type: StringName = &""
## Сколько патронов дать при подборе.
@export var ammo_amount: int = 0


func _apply(body: Node3D) -> bool:
	var got_weapon: bool = body.has_method(&"give_weapon") and body.give_weapon(slot)
	var got_ammo: bool = false
	if ammo_amount > 0 and ammo_type != &"" and body.has_method(&"add_ammo"):
		got_ammo = body.add_ammo(ammo_type, ammo_amount) > 0
	# Исчезаем, если выдали ствол ИЛИ патроны. Уже есть ствол и патроны полны —
	# пикап остаётся лежать (можно вернуться за патронами позже). Как AmmoPickup.
	return got_weapon or got_ammo
