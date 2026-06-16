class_name PickupBase
extends Area3D
## Переиспользуемая база пикапа. Срабатывает, когда в область входит тело
## из группы target_group. Конкретный эффект задаёт наследник в _apply()
## (виртуальный хук — как virtual/override в C#). База: обнаружение,
## единоразовость, вращение-плейсхолдер, самоуничтожение.

## На какую группу тел реагирует пикап.
@export var target_group: StringName = &"player"
## Вращение визуала, градусов/с (живость плейсхолдера). 0 — выключить.
@export var spin_speed_deg: float = 60.0

# Защита от повторного срабатывания.
var _used: bool = false


func _ready() -> void:
	# Area3D шлёт body_entered, когда внутрь входит физическое тело.
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	if spin_speed_deg != 0.0:
		rotate_y(deg_to_rad(spin_speed_deg) * delta)


func _on_body_entered(body: Node3D) -> void:
	if _used or not body.is_in_group(target_group):
		return
	# Наследник применяет эффект. Вернул false (например, запас полон) —
	# пикап остаётся лежать, можно подобрать позже (повторно зайти в область).
	if not _apply(body):
		return
	_used = true
	_on_collected()
	queue_free()


## Переопределяется наследником: применить эффект к телу.
## true — эффект сработал (пикап исчезнет); false — не нужен (останется).
func _apply(_body: Node3D) -> bool:
	return true


## Хук на момент подбора (звук/частицы). По умолчанию пусто.
func _on_collected() -> void:
	pass
