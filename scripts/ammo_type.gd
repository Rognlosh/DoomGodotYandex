class_name AmmoType
extends Resource
## Описание одного типа патронов (пула). Настраивается в инспекторе как элемент
## массива AmmoComponent.ammo_types. Аналог ScriptableObject из C#/Unity:
## сериализуемый объект-данные.

## Ключ пула. Оружие и пикап ссылаются на патроны по этому id.
@export var id: StringName = &"bullets"
## Максимальный запас этого типа.
@export var max_amount: int = 200
## Сколько этого типа у игрока на старте.
@export var start_amount: int = 50
