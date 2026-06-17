class_name WeaponManager
extends Node
## Держит несколько экранных оружий (дочерние Weapon), переключает активное
## и роутит в него ввод выстрела. Само оружие ввод не читает.
## Слоты: каждый Weapon объявляет свой @export slot (1–5). Клавиши weapon_1..5
## прыгают в слот; колёсико (weapon_next/prev) листает по ЗАНЯТЫМ слотам.

## Сменилось активное оружие. (weapon) — для HUD (показать его патроны).
signal weapon_changed(weapon: Weapon)

## Проброс попадания по поверхности от стволов наверх (для эффекта дымка).
signal surface_hit(position: Vector3, normal: Vector3)

## Проброс попадания по врагу от стволов наверх (для эффекта звёзд).
signal damageable_hit(position: Vector3, normal: Vector3)

## С какого слота начинаем. Пуст — берём первый занятый по возрастанию.
@export var start_slot: int = 2

# slot -> Weapon. Заполняется в _ready по детям.
var _by_slot: Dictionary = {}
# Занятые слоты по возрастанию (для колёсика).
var _ordered_slots: Array[int] = []
# Текущий активный слот (0 — нет активного).
var _active_slot: int = 0
# Кнопка выстрела зажата (для авто-огня). Ставится только по легитимному нажатию.
var _firing: bool = false


func _ready() -> void:
	# Раскладываем дочерние Weapon по слотам, всё прячем.
	for child in get_children():
		var weapon := child as Weapon
		if weapon == null or weapon.slot <= 0:
			continue
		_by_slot[weapon.slot] = weapon
		weapon.visible = false
		weapon.surface_hit.connect(_forward_surface_hit)
		weapon.damageable_hit.connect(_forward_damageable_hit)
	_ordered_slots.assign(_by_slot.keys())
	_ordered_slots.sort()

	# Активируем стартовый слот (или первый занятый).
	var slot: int = start_slot
	if not _by_slot.has(slot):
		slot = _ordered_slots[0] if not _ordered_slots.is_empty() else 0
	_activate(slot)


func _unhandled_input(event: InputEvent) -> void:
	# Прямой выбор слота клавишами 1–5 (с проверкой, что action заведён).
	for s in range(1, 6):
		var action := "weapon_%d" % s
		if InputMap.has_action(action) and event.is_action_pressed(action):
			_activate(s)
			return
	# Колёсико — листаем по занятым слотам.
	if InputMap.has_action(&"weapon_next") and event.is_action_pressed(&"weapon_next"):
		_cycle(1)
		return
	if InputMap.has_action(&"weapon_prev") and event.is_action_pressed(&"weapon_prev"):
		_cycle(-1)
		return

	# Выстрел. «Захватывающий» клик сюда не доходит (его поглощает player.gd в _input),
	# поэтому первый клик не запускает автоогонь по ошибке.
	if event.is_action_pressed(&"shoot") and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		_firing = true
		_fire_active()
	elif event.is_action_released(&"shoot"):
		_firing = false


func _process(_delta: float) -> void:
	# Автоогонь: пока кнопка зажата и курсор захвачен — повторяем (темп задаёт кулдаун оружия).
	if not _firing:
		return
	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		_firing = false
		return
	var weapon := _active_weapon()
	if weapon != null and weapon.fire_mode == Weapon.FireMode.AUTO:
		_fire_active()


## Активное оружие или null. Нужен main для стартовой синхронизации HUD.
func get_active_weapon() -> Weapon:
	return _active_weapon()


func _active_weapon() -> Weapon:
	return _by_slot.get(_active_slot, null) as Weapon


func _fire_active() -> void:
	var weapon := _active_weapon()
	if weapon != null:
		weapon.try_fire()


func _activate(slot: int) -> void:
	if slot == _active_slot or not _by_slot.has(slot):
		return  # тот же слот или пустой — игнор
	var prev := _active_weapon()
	if prev != null:
		prev.visible = false
	_active_slot = slot
	var now := _active_weapon()
	if now != null:
		now.visible = true
	weapon_changed.emit(now)


func _cycle(direction: int) -> void:
	if _ordered_slots.is_empty():
		return
	var idx := _ordered_slots.find(_active_slot)
	if idx == -1:
		idx = 0
	idx = wrapi(idx + direction, 0, _ordered_slots.size())
	_activate(_ordered_slots[idx])
	
func _forward_surface_hit(position: Vector3, normal: Vector3) -> void:
	surface_hit.emit(position, normal)


func _forward_damageable_hit(position: Vector3, normal: Vector3) -> void:
	damageable_hit.emit(position, normal)
