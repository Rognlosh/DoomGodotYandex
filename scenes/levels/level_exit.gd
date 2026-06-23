class_name LevelExit
extends Area3D
## Зона завершения уровня. Игрок входит в неё — выход сообщает наверх (reached),
## а решение "следующий уровень или экран победы" принимает сессия (main.gd).
##
## Архитектурно — родня PickupBase: Area3D, реагирует только на тело из группы
## target_group, срабатывает ОДИН раз. Но эффекта на игрока не применяет —
## просто шлёт сигнал вверх (signal up), как враг/оружие через take_damage.
##
## Уровень может содержать несколько выходов (задел под секретный выход —
## различие будет данными на самом выходе, сейчас любой выход = «дальше»).

## Группа тела, которое засчитывает выход. Игрок добавлен в группу "player".
@export var target_group: StringName = &"player"

## Игрок дошёл до выхода. Сессия ловит и двигает поток уровней.
signal reached(exit: LevelExit)

# Срабатываем единожды — повторный вход (игрок топчется в зоне) игнорируем.
var _triggered: bool = false


func _ready() -> void:
	# В группе — чтобы при желании выходы можно было найти и со стороны,
	# но сессия подключается к ним точечно (find_children по типу LevelExit).
	add_to_group(&"level_exit")
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if _triggered:
		return
	# Слой у Area3D общий (как у пикапов) — тело может быть и врагом.
	# Засчитываем только игрока (по группе), как PickupBase._apply.
	if not body.is_in_group(target_group):
		return
	_triggered = true
	# Больше не мониторим — на всякий случай, чтобы не словить второй вход.
	set_deferred(&"monitoring", false)
	reached.emit(self)
