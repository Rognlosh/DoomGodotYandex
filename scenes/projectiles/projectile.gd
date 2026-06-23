class_name Projectile
extends Node3D
## Снаряд: летит по прямой, на удар наносит урон и взрывается.
## Общая сущность для ракеты игрока и файрбола врага — различие только в @export.
## Движение — заметающий луч (как хитскан в weapon.gd): без туннелирования сквозь
## стены, без физ-тел и GPU-частиц — безопасно для Compatibility/WebGL.
## Спавнится статической фабрикой launch() — общий код для оружия и врага.

@export_group("Полёт")
## Скорость, м/с.
@export var speed: float = 22.0
## Время жизни, если ни во что не попал, с (страховка от вечного полёта).
@export var lifetime: float = 6.0

@export_group("Урон")
## Базовый урон.
@export var damage: float = 80.0
## Радиус взрыва, м. 0 — прямое попадание (урон одному задетому телу, без AoE).
@export var splash_radius: float = 0.0
## Множитель урона на краю радиуса (1 — без затухания; 0 — до нуля у края).
@export_range(0.0, 1.0) var splash_min_factor: float = 0.25

@export_group("Визуал")
## Цвет снаряда (красит процедурный плейсхолдер-спрайт через modulate).
@export var color: Color = Color(1.0, 0.5, 0.15)
## Размер биллборда, м.
@export var sprite_size: float = 0.5

# Единичное направление полёта; задаётся в launch().
var _dir: Vector3 = Vector3.FORWARD
# RID стрелка — исключаем из луча В ПОЛЁТЕ, чтобы снаряд не детонировал на теле
# самого стрелка у дула. На УРОН это не влияет: сплэш бьёт всех без разбора.
var _owner_rid: RID
var _life: float = 0.0
var _exploded: bool = false
@onready var _sprite: Sprite3D = $Sprite3D


## Создать снаряд, добавить в мир и запустить. Общий код спавна (чтобы оружие и
## враг не дублировали инстанс-логику). spawner — любой узел в дереве (для get_tree).
static func launch(scene: PackedScene, spawner: Node, from: Vector3,
		dir: Vector3, owner_rid: RID) -> Projectile:
	if scene == null:
		return null
	var proj := scene.instantiate() as Projectile
	if proj == null:
		return null
	# Снаряды живут в контейнере (группа world_projectiles), не в стрелке — чтобы
	# переживали его смерть. Нет контейнера — кладём в текущую сцену.
	var tree := spawner.get_tree()
	var container: Node = tree.get_first_node_in_group(&"world_projectiles")
	if container == null:
		container = tree.current_scene
	container.add_child(proj)          # _ready() здесь: строит спрайт
	proj.global_position = from        # global_* — только после добавления в дерево
	proj._dir = dir.normalized()
	proj._owner_rid = owner_rid
	return proj


func _ready() -> void:
	if _sprite.texture == null:
		_sprite.texture = _make_texture()
	_sprite.modulate = color
	_sprite.pixel_size = sprite_size / 32.0   # текстура 32px → sprite_size метров


func _physics_process(delta: float) -> void:
	if _exploded:
		return
	_life += delta
	if _life >= lifetime:
		_explode(global_position, Vector3.UP, null)
		return
	# Заметающий луч из текущей позиции в следующую — ловит даже быстрый снаряд.
	var from := global_position
	var to := from + _dir * speed * delta
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	if _owner_rid.is_valid():
		query.exclude = [_owner_rid]
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		global_position = to
		return
	_explode(hit.get("position"), hit.get("normal"), hit.get("collider"))


# Взрыв: урон (прямой или по площади) + эффект + звук, затем самоуничтожение.
func _explode(at: Vector3, normal: Vector3, direct_body: Object) -> void:
	if _exploded:
		return
	_exploded = true
	if splash_radius > 0.0:
		_apply_splash(at)
	elif direct_body != null and direct_body.has_method("take_damage"):
		direct_body.take_damage(damage)
	_spawn_explosion_fx(at, normal)
	_play_sound(&"explosion")
	queue_free()


# Урон по площади: бьёт ВСЕХ в радиусе с take_damage, без исключений (своих тоже,
# и самого стрелка). В этом и фича ракеты — фракций снаряд не различает.
func _apply_splash(center: Vector3) -> void:
	var space := get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = splash_radius
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = Transform3D(Basis.IDENTITY, center)
	var results := space.intersect_shape(params, 32)
	var seen: Dictionary = {}   # тело может вернуться неск. раз (разные шейпы) — бьём раз
	for r in results:
		var col: Object = r.get("collider")
		if col == null or seen.has(col) or not col.has_method("take_damage"):
			continue
		seen[col] = true
		var factor := 1.0
		if col is Node3D:
			var d := (col as Node3D).global_position.distance_to(center)
			var t := clampf(1.0 - d / splash_radius, 0.0, 1.0)
			factor = lerpf(splash_min_factor, 1.0, t)
		col.take_damage(damage * factor)


func _spawn_explosion_fx(at: Vector3, normal: Vector3) -> void:
	var fx := get_tree().get_first_node_in_group(&"explosions") as ParticleBurst3D
	if fx != null:
		fx.spawn(at, normal if normal.length() > 0.0 else Vector3.UP)


func _play_sound(id: StringName) -> void:
	var ca := get_tree().get_first_node_in_group(&"combat_audio") as CombatAudio
	if ca != null:
		ca.play(id)


# Мягкое круглое пятно (радиальное затухание альфы). Ноль веса; красится modulate.
func _make_texture() -> Texture2D:
	var s := 32
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var c := Vector2(s * 0.5, s * 0.5)
	var radius := s * 0.5
	for y in s:
		for x in s:
			var dd := Vector2(x + 0.5, y + 0.5).distance_to(c) / radius
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, clampf(1.0 - dd, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)
