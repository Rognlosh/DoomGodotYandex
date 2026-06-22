extends Node3D
## Единая точка входа. Грузит уровень, спавнит игрока, поднимает HUD
## и владеет game-over/рестартом.

## Сцена уровня (назначается в инспекторе).
@export var level_scene: PackedScene
## Сцена игрока (назначается в инспекторе).
@export var player_scene: PackedScene
## Сцена HUD (назначается в инспекторе). Корень — CanvasLayer, внутри узел "Root" (Hud).
@export var hud_scene: PackedScene

# Ссылка на узел HUD (Control), чтобы дёргать его методы.
var _hud: Hud
# Боезапас игрока — для пуша актуального счётчика на HUD при смене оружия.
var _ammo: AmmoComponent
# Звук боя — создаём здесь, источники находят его по группе.
var _combat: CombatAudio


func _ready() -> void:
	if level_scene == null or player_scene == null:
		push_error("Main: в инспекторе не назначены level_scene и/или player_scene.")
		return

	# Звук боя: узел в дереве, остальные находят его по группе "combat_audio".
	# Создаём первым — стартует эмбиент и группа готова до спавна врагов/оружия.
	_combat = CombatAudio.new()
	add_child(_combat)

	var level := level_scene.instantiate()
	add_child(level)

	var player := player_scene.instantiate() as Node3D
	add_child(player)

	# Если у уровня есть точка спавна — ставим игрока туда.
	var spawn := level.get_node_or_null("PlayerSpawn")
	if spawn is Node3D:
		player.global_transform = (spawn as Node3D).global_transform

	_setup_hud(player)


# Поднимаем HUD и связываем его со здоровьем и патронами игрока.
# signal up: компоненты эмитят — HUD/main подписываются, сами компоненты о них не знают.
func _setup_hud(player: Node3D) -> void:
	if hud_scene == null:
		push_error("Main: в инспекторе не назначен hud_scene.")
		return

	var hud_root := hud_scene.instantiate()
	add_child(hud_root)
	_hud = hud_root.get_node_or_null("Root") as Hud
	if _hud == null:
		push_error("Main: в hud_scene не найден узел 'Root' со скриптом Hud.")
		return
	_hud.restart_requested.connect(_on_restart_requested)

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

	_setup_ammo(player)


# Связываем боезапас игрока с HUD. signal up — как со здоровьем.
func _setup_ammo(player: Node3D) -> void:
	_ammo = player.get_node_or_null("AmmoComponent") as AmmoComponent
	if _ammo == null:
		push_error("Main: у игрока не найден AmmoComponent.")
		return

	# HUD слышит изменения любого пула, но рисует только активный тип.
	_ammo.ammo_changed.connect(_hud.on_ammo_changed)

	# Менеджер оружия: при смене ствола обновляем активный тип патронов на HUD.
	var weapons := player.get_node_or_null("WeaponLayer/Weapons") as WeaponManager
	if weapons == null:
		_sync_ammo_type(&"bullets")  # фолбэк, если менеджера нет
		return

	weapons.weapon_changed.connect(_on_weapon_changed)
	_on_weapon_changed(weapons.get_active_weapon())  # стартовая синхронизация
	_setup_effects(weapons)


# Подключаем эффекты попадания к сигналам стволов. Узлы ImpactSmoke/HitStars —
# в main.tscn; signal up: weapon → WeaponManager → сюда → эффект.
func _setup_effects(weapons: WeaponManager) -> void:
	# Дымок по неуязвимой поверхности.
	var impacts := get_node_or_null("ImpactSmoke") as ImpactSmoke
	if impacts != null:
		weapons.surface_hit.connect(impacts.spawn)
	# Звёзды-pow по врагу.
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
	_sync_ammo_type(weapon.ammo_type)


func _sync_ammo_type(type: StringName) -> void:
	_hud.set_active_ammo_type(type)
	# Компонент шлёт сигнал только при изменении — текущее значение пушим вручную.
	_hud.on_ammo_changed(type, _ammo.get_ammo(type), _ammo.get_max(type))


# Игрок умер: стоп всей игры, свободная мышь, оверлей. Рестарт — по клавише (сигнал от HUD).
func _on_player_died() -> void:
	if _combat != null:
		_combat.play(&"player_death")
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_hud.show_game_over()


func _on_restart_requested() -> void:
	# Снять паузу ДО перезагрузки, иначе новая сцена стартует замороженной.
	get_tree().paused = false
	get_tree().reload_current_scene()
