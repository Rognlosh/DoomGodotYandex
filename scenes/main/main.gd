extends Node3D
## Игровая сессия (один прогон кампании). Владеет последовательностью уровней,
## игроком, HUD и звуком; свапает уровни НА МЕСТЕ (игрок/HUD/CombatAudio переживают
## переход — эмбиент не перезапускается, лоадаут переносится между уровнями).
##
## "Тупой" геймплей: решения "пауза / оверлей / какой экран показать" принимает
## роутер (Game). Сессия лишь шлёт наверх сигналы и выполняет команды роутера
## (advance_level / restart_level) — call down, signal up.

## Уровни кампании по порядку (назначаются в инспекторе main.tscn).
@export var levels: Array[PackedScene]
## Сцена игрока (назначается в инспекторе).
@export var player_scene: PackedScene
## Сцена HUD (назначается в инспекторе). Корень — CanvasLayer, внутри узел "Root" (Hud).
@export var hud_scene: PackedScene

## Игрок умер. Роутер поднимет экран Game Over и поставит паузу.
signal player_died
## Игрок нажал Esc в геймплее. Роутер откроет меню паузы.
signal pause_requested
## Уровень пройден, впереди ещё есть уровни. Роутер покажет промежуточный экран;
## по "Дальше" вызовет advance_level().
signal level_completed
## Пройден последний уровень. Роутер покажет экран победы.
signal campaign_completed

# Индекс текущего уровня в массиве levels. Прогресс кампании живёт ЗДЕСЬ, в сессии
# (состояние — в сцене, не в роутере и не в autoload). Облачный резюм (Этап 4)
# выставит стартовый индекс через set_start_level до добавления сессии в дерево.
var _level_index: int = 0

# Ссылка на узел HUD (Control) — поднимается один раз, переживает смену уровней.
var _hud: Hud
# Боезапас активного игрока — для пуша счётчика на HUD при смене оружия.
var _ammo: AmmoComponent
# Звук боя — создаём один раз; источники находят его по группе. Не пересоздаётся
# на свапе уровня → эмбиент играет непрерывно.
var _combat: CombatAudio
# Текущий инстанс уровня (его и свапаем).
var _level: Node = null
# Игрок — переживает переходы между уровнями; пересоздаётся только на рестарте.
var _player: Node3D = null
# Контейнер снарядов (узел в main.tscn, группа world_projectiles). На свапе чистим.
var _projectiles: Node = null


func _ready() -> void:
	if levels.is_empty() or player_scene == null or hud_scene == null:
		push_error("Main: назначь в инспекторе levels (непустой), player_scene и hud_scene.")
		return

	# Звук боя — первым: стартует эмбиент и группа "combat_audio" готова до спавна.
	_combat = CombatAudio.new()
	add_child(_combat)

	_projectiles = get_node_or_null("Projectiles")

	# HUD поднимаем один раз; к игроку он привязывается в _wire_player.
	_build_hud()
	# Первая загрузка — со свежим игроком (создаст и привяжет его к HUD).
	_load_level(true)


# Стартовый индекс уровня (для будущего облачного резюма, Этап 4).
# Зовётся роутером ДО add_child(session), иначе перетрётся дефолтом 0 в _load_level.
func set_start_level(index: int) -> void:
	_level_index = index


# --------------------------------------------------------------------------
# Поток уровней
# --------------------------------------------------------------------------

# Команда роутера: следующий уровень (после промежуточного экрана). Игрок и его
# лоадаут сохраняются (continuous-режим — перенос прогресса между уровнями).
func advance_level() -> void:
	_level_index += 1
	if _level_index >= levels.size():
		_level_index = levels.size() - 1
		return
	_load_level(false)


# Команда роутера: перезапустить текущий уровень (после смерти). Игрок
# пересоздаётся со свежим лоадаутом (@export-дефолты), уровень — заново.
func restart_level() -> void:
	_load_level(true)


# Загрузить уровень по текущему индексу. fresh_player=true — пересоздать игрока
# (старт/рестарт); false — оставить текущего (переход между уровнями).
func _load_level(fresh_player: bool) -> void:
	_clear_projectiles()

	if _level != null:
		_level.queue_free()
		_level = null

	# Игрока готовим ДО уровня: враги уровня при _ready найдут его в группе
	# (хотя _acquire_target и самоисцеляется каждый кадр — порядок не критичен).
	if fresh_player or _player == null:
		_replace_player()

	_level = levels[_level_index].instantiate()
	add_child(_level)

	# Точку спавна и выходы читаем ОТЛОЖЕННО. Если уровень использует слой Entities,
	# маркеры превращаются в узлы (PlayerSpawn/LevelExit/враги) тоже отложенно — на
	# момент add_child дерево ещё «занято» и add_child в него запрещён. К следующему
	# кадру и прямые узлы, и созданные спавнером уже на месте.
	_resolve_spawn_and_exits.call_deferred()


# Поставить игрока в точку спавна и подписаться на выходы. Идемпотентно.
func _resolve_spawn_and_exits() -> void:
	if _level == null:
		return
	var spawn := _level.get_node_or_null("PlayerSpawn")
	if spawn is Node3D and _player != null:
		# Игрок вызывается по-утиному (как take_damage/add_ammo) — роутер/сессия
		# не держат статической ссылки на его скрипт.
		_player.call(&"teleport_to", (spawn as Node3D).global_transform)
	_connect_exits()


# Пересоздать игрока и заново привязать к HUD/эффектам/звуку.
func _replace_player() -> void:
	if _player != null:
		# Снимаем из группы сразу, чтобы враги не цеплялись за умирающий инстанс.
		_player.remove_from_group(&"player")
		_player.queue_free()
	_player = player_scene.instantiate() as Node3D
	add_child(_player)
	_wire_player(_player)


# Найти выходы нового уровня и подписаться на них (signal up). Старые выходы
# уехали вместе с прежним уровнем — их соединения исчезли сами.
func _connect_exits() -> void:
	if _level == null:
		return
	var exits := _level.find_children("*", "LevelExit", true, false)
	for node in exits:
		var exit := node as LevelExit
		if exit != null and not exit.reached.is_connected(_on_level_exit):
			exit.reached.connect(_on_level_exit)
	if exits.is_empty():
		push_warning("Main: на уровне нет LevelExit — пройти его будет нельзя.")


func _clear_projectiles() -> void:
	if _projectiles == null:
		return
	for p in _projectiles.get_children():
		p.queue_free()


# Игрок дошёл до выхода. Решаем: ещё есть уровни → промежуточный экран,
# иначе → победа. Сам свап делаем по команде роутера (advance_level).
func _on_level_exit(_exit: LevelExit) -> void:
	if _level_index + 1 < levels.size():
		level_completed.emit()
	else:
		campaign_completed.emit()


# --------------------------------------------------------------------------
# HUD и проводка игрока
# --------------------------------------------------------------------------

# Поднять HUD один раз (он переживает смену уровней). Привязка к конкретному
# игроку — в _wire_player (вызывается при каждом пересоздании игрока).
func _build_hud() -> void:
	var hud_root := hud_scene.instantiate()
	add_child(hud_root)
	_hud = hud_root.get_node_or_null("Root") as Hud
	if _hud == null:
		push_error("Main: в hud_scene не найден узел 'Root' со скриптом Hud.")


# Привязать здоровье/броню/патроны/оружие игрока к HUD и эффектам.
# signal up: компоненты эмитят — HUD/эффекты подписываются, сами компоненты о них
# не знают. Соединения со старым (освобождённым) игроком исчезают вместе с ним.
func _wire_player(player: Node3D) -> void:
	if _hud == null:
		return

	# Здоровье игрока — тот же HealthComponent, что у врага.
	var health := player.get_node_or_null("HealthComponent") as HealthComponent
	if health == null:
		push_error("Main: у игрока не найден HealthComponent.")
		return
	health.health_changed.connect(_hud.set_health)
	health.died.connect(_on_player_died)
	# Компонент шлёт health_changed только при изменении — стартовое значение пушим вручную.
	_hud.set_health(health.current_health, health.max_health)

	# Броня игрока — отдельный компонент перед HP (если есть). signal up, как со здоровьем.
	var armor := player.get_node_or_null("ArmorComponent") as ArmorComponent
	if armor != null:
		armor.armor_changed.connect(_hud.set_armor)
		_hud.set_armor(armor.current_armor, armor.max_armor)

	_wire_ammo(player)


# Связать боезапас игрока с HUD и подключить эффекты оружия. signal up.
func _wire_ammo(player: Node3D) -> void:
	_ammo = player.get_node_or_null("AmmoComponent") as AmmoComponent
	if _ammo == null:
		push_error("Main: у игрока не найден AmmoComponent.")
		return

	# HUD слышит изменения любого пула, но рисует только активный тип.
	_ammo.ammo_changed.connect(_hud.on_ammo_changed)
	
	# HUD слышит изменения любого пула, но рисует только активный тип.
	_ammo.ammo_changed.connect(_hud.on_ammo_changed)

	# Стартовые значения по ВСЕМ пулам — для мини-строки (пул шлёт сигнал только
	# при изменении, поэтому по одному разу пушим каждый вручную).
	for ammo in _ammo.ammo_types:
		if ammo != null:
			_hud.on_ammo_changed(ammo.id, _ammo.get_ammo(ammo.id), _ammo.get_max(ammo.id))

	# Стартовые значения по ВСЕМ пулам — для мини-строки (пул шлёт сигнал только
	# при изменении, поэтому по одному разу пушим каждый вручную).
	for ammo in _ammo.ammo_types:
		if ammo != null:
			_hud.on_ammo_changed(ammo.id, _ammo.get_ammo(ammo.id), _ammo.get_max(ammo.id))

	# Менеджер оружия: при смене ствола обновляем активный тип патронов на HUD.
	var weapons := player.get_node_or_null("WeaponLayer/Weapons") as WeaponManager
	if weapons == null:
		_sync_ammo_type(&"bullets")  # фолбэк, если менеджера нет
		return

	weapons.weapon_changed.connect(_on_weapon_changed)
	_on_weapon_changed(weapons.get_active_weapon())  # стартовая синхронизация
	_wire_effects(weapons)


# Подключить эффекты попадания к сигналам стволов. Узлы ImpactSmoke/HitStars/
# Explosion — в main.tscn (переживают смену уровней и игрока); signal up.
func _wire_effects(weapons: WeaponManager) -> void:
	var impacts := get_node_or_null("ImpactSmoke") as ImpactSmoke
	if impacts != null:
		weapons.surface_hit.connect(impacts.spawn)
	var stars := get_node_or_null("HitStars") as HitStars
	if stars != null:
		weapons.damageable_hit.connect(stars.spawn)
	# Звук попаданий — рядом с эффектами (CombatAudio дедупит дробь по кадру).
	weapons.surface_hit.connect(_on_surface_hit_audio)
	weapons.damageable_hit.connect(_on_damageable_hit_audio)


func _on_surface_hit_audio(_position: Vector3, _normal: Vector3) -> void:
	if _combat != null:
		_combat.play(&"impact_wall")


func _on_damageable_hit_audio(_position: Vector3, _normal: Vector3) -> void:
	if _combat != null:
		_combat.play(&"impact_flesh")


# Сменилось активное оружие: показываем на HUD патроны его типа.
func _on_weapon_changed(weapon: Weapon) -> void:
	if weapon == null:
		return
	_sync_ammo_type(weapon.ammo_type, weapon.uses_ammo)


func _sync_ammo_type(type: StringName, uses_ammo: bool = true) -> void:
	if _hud == null or _ammo == null:
		return
	_hud.set_active_ammo_type(type, uses_ammo)
	# Компонент шлёт сигнал только при изменении — текущее значение пушим вручную.
	_hud.on_ammo_changed(type, _ammo.get_ammo(type), _ammo.get_max(type))


# --------------------------------------------------------------------------
# Ввод и смерть
# --------------------------------------------------------------------------

# Esc в геймплее — просим роутер открыть паузу. Когда оверлей открыт,
# сессия на паузе и этот ввод сюда не доходит (Esc ловит меню паузы).
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		pause_requested.emit()


# Игрок умер: озвучиваем и сообщаем наверх. Паузу/мышь/оверлей берёт на себя роутер.
func _on_player_died() -> void:
	if _combat != null:
		_combat.play(&"player_death")
	player_died.emit()
