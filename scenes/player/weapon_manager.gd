class_name WeaponManager
extends Node
## Держит несколько экранных оружий (дочерние Weapon), переключает активное
## и роутит в него ввод выстрела. Само оружие ввод не читает.
## Слоты: каждый Weapon объявляет свой @export slot (1–5). Клавиши weapon_1..5
## прыгают в слот; колёсико (weapon_next/prev) листает по ВЛАДЕЕМЫМ слотам.
##
## ВЛАДЕНИЕ: все дочерние Weapon — «каталог» стволов, но доступны только
## владеемые (_owned). На старте владеем start_owned_slots (кулак+пистолет),
## остальные выдаются пикапами через give_weapon() — классика DOOM.

## Сменилось активное оружие. (weapon) — для HUD (показать его патроны).
signal weapon_changed(weapon: Weapon)

## Проброс попадания по поверхности от стволов наверх (для эффекта дымка).
signal surface_hit(position: Vector3, normal: Vector3)

## Проброс попадания по врагу от стволов наверх (для эффекта звёзд).
signal damageable_hit(position: Vector3, normal: Vector3)

## Изменился набор владеемых стволов (подобрали оружие) — для блока ARMS на HUD.
signal owned_changed(slots: Array[int])

## С какого слота начинаем. Должен быть среди стартовых владеемых.
@export var start_slot: int = 2
## Слоты, которыми игрок владеет на старте (кулак + пистолет). Остальные стволы
## существуют как дочерние узлы, но недоступны, пока не подобраны.
@export var start_owned_slots: Array[int] = [1, 2]
## Переключаться на только что подобранный ствол (как в DOOM).
@export var auto_switch_on_pickup: bool = true

# slot -> Weapon: ВСЕ дочерние стволы (каталог). Владение — отдельно, в _owned.
var _by_slot: Dictionary = {}
# slot -> true: владеемые стволы.
var _owned: Dictionary = {}
# Владеемые слоты по возрастанию (ARMS + колёсико).
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

	# Стартовое владение: только слоты из start_owned_slots, у которых есть ствол.
	for s in start_owned_slots:
		if _by_slot.has(s):
			_owned[s] = true
	_rebuild_owned()

	# Активируем стартовый слот (или первый владеемый по возрастанию).
	var slot: int = start_slot
	if not _owned.has(slot):
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


## Владеемые слоты по возрастанию (для блока ARMS на HUD). Копия — наружу без риска.
func get_owned_slots() -> Array[int]:
	var out: Array[int] = []
	out.assign(_ordered_slots)
	return out


## Владеет ли игрок стволом этого слота.
func has_weapon(slot: int) -> bool:
	return _owned.has(slot)


## Выдать игроку ствол слота (пикап оружия). true — ствол новый (выдан);
## false — такого ствола нет в каталоге ИЛИ уже во владении. Конвенция: тело
## игрока делегирует сюда (как add_ammo — в AmmoComponent).
func give_weapon(slot: int) -> bool:
	if not _by_slot.has(slot) or _owned.has(slot):
		return false
	_owned[slot] = true
	_rebuild_owned()
	owned_changed.emit(get_owned_slots())
	if auto_switch_on_pickup:
		_activate(slot)
	return true


func _rebuild_owned() -> void:
	_ordered_slots.assign(_owned.keys())
	_ordered_slots.sort()


func _active_weapon() -> Weapon:
	return _by_slot.get(_active_slot, null) as Weapon


func _fire_active() -> void:
	var weapon := _active_weapon()
	if weapon != null:
		weapon.try_fire()


func _activate(slot: int) -> void:
	if slot == _active_slot or not _owned.has(slot):
		return  # тот же слот или невладеемый — игнор
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
