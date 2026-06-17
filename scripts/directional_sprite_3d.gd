class_name DirectionalSprite3D
extends Sprite3D
## Спрайт врага с думовскими ракурсами + покадровой анимацией.
## Висит прямо на узле Sprite3D (биллборд Y). Каждый кадр:
##   1) считает угол между «куда смотрит враг» (поворот родителя) и камерой,
##   2) выбирает столбец-ракурс атласа (+ flip_h для левой половины круга),
##   3) листает кадры текущей анимации по таймеру.
## Реюзабелен: любой враг вешает этот же скрипт на свой Sprite3D и заполняет
## массив animations своим атласом — кода под нового врага не пишем.

## Текущая анимация доиграла (для невозвратных — атака/смерть).
signal animation_finished(anim_name: StringName)

@export_group("Атлас")
## Сколько РИСУЕМЫХ ракурсов-столбцов: думовские 5 (фронт, фронт-¾, профиль,
## спина-¾, спина). Левая половина круга — зеркало, в атласе её нет.
@export var columns: int = 5
## Набор анимаций (см. SpriteAnimation). Заполняется в инспекторе.
@export var animations: Array[SpriteAnimation] = []
## Что играть при старте.
@export var default_animation: StringName = &"walk"

@export_group("Вспышка боли")
## Цвет короткой вспышки при получении урона.
@export var pain_color: Color = Color(1.0, 0.4, 0.4)
## Длительность затухания вспышки, с.
@export var pain_duration: float = 0.12

var _by_name: Dictionary = {}
var _current: SpriteAnimation
var _frame_index: int = 0
var _accum: float = 0.0
var _finished_emitted: bool = false
var _enabled: bool = false
# Узел, чей поворот считаем «направлением взгляда» врага (тело-родитель).
@onready var _body: Node3D = get_parent() as Node3D


func _ready() -> void:
	# Нет атласа или анимаций — работаем простым статичным плейсхолдером,
	# чтобы игра оставалась играбельной до появления арта.
	if texture == null or animations.is_empty():
		if texture == null:
			texture = _make_placeholder_texture()
		_enabled = false
		return

	# Раскладываем атлас сеткой: ширина — ракурсы, высота — суммарные строки.
	hframes = columns
	vframes = _compute_total_rows()
	for a in animations:
		_by_name[a.name] = a
	_enabled = true
	play(default_animation)


func _process(delta: float) -> void:
	if not _enabled or _current == null:
		return
	_advance_frame(delta)
	_update_cell()


## Переключить анимацию. Зацикленную ту же не перезапускаем (чтобы ходьба
## не дёргалась от вызова каждый кадр); невозвратную (атака/смерть) — да.
func play(anim_name: StringName) -> void:
	var a: SpriteAnimation = _by_name.get(anim_name)
	if a == null:
		return
	if a == _current and a.loop:
		return
	_current = a
	_frame_index = 0
	_accum = 0.0
	_finished_emitted = false


## Короткая вспышка цвета поверх кадра (реакция на урон). Кадры не трогает.
func flash_pain() -> void:
	modulate = pain_color
	# create_tween — одноразовый твин: плавно гоним modulate обратно в белый.
	var tw: Tween = create_tween()
	tw.tween_property(self, ^"modulate", Color.WHITE, pain_duration)


# --- Внутреннее ---

func _advance_frame(delta: float) -> void:
	if _current.frame_count <= 1:
		return
	_accum += delta
	var step: float = 1.0 / maxf(_current.fps, 0.001)
	while _accum >= step:
		_accum -= step
		_frame_index += 1
		if _frame_index >= _current.frame_count:
			if _current.loop:
				_frame_index = 0
			else:
				_frame_index = _current.frame_count - 1
				if not _finished_emitted:
					_finished_emitted = true
					animation_finished.emit(_current.name)
				break


func _update_cell() -> void:
	var col: int = 0
	var flip: bool = false
	if _current.directional:
		var pick := _pick_direction()
		col = pick.x
		flip = pick.y == 1
	# frame — единый индекс ячейки: строка * ширина + столбец.
	frame = (_current.row_start + _frame_index) * columns + col
	flip_h = flip


# Vector2i(столбец, flip:0/1) по углу «взгляд врага vs камера».
func _pick_direction() -> Vector2i:
	var cam := get_viewport().get_camera_3d()
	if cam == null or _body == null:
		return Vector2i(0, 0)
	var to_cam := cam.global_position - global_position
	to_cam.y = 0.0
	if to_cam.length() < 0.001:
		return Vector2i(0, 0)
	# Куда смотрит враг (его -Z) и куда камера — в 2D-плоскости XZ.
	var fwd := -_body.global_transform.basis.z
	var f2 := Vector2(fwd.x, fwd.z)
	var c2 := Vector2(to_cam.x, to_cam.z)
	# Знаковый угол между ними, режем на 8 секторов.
	var ang := f2.angle_to(c2)
	var idx := int(round(ang / (TAU / 8.0)))
	idx = ((idx % 8) + 8) % 8
	# 0..4 — рисуемая половина; 5..7 — зеркало (flip_h).
	# Если в игре лево/право перепутаны — поставь ang = -ang строкой выше.
	if idx <= 4:
		return Vector2i(idx, 0)
	return Vector2i(8 - idx, 1)


func _compute_total_rows() -> int:
	var rows: int = 1
	for a in animations:
		rows = maxi(rows, a.row_start + a.frame_count)
	return rows


## Временный силуэт, пока нет атласа (ноль веса билда). Появится текстура —
## назначь её и заполни animations: плейсхолдер сам отключится.
func _make_placeholder_texture() -> Texture2D:
	var w := 32
	var h := 48
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 0.0, 0.0, 0.0))
	var body := Color(0.7, 0.15, 0.15)
	var border := Color(0.1, 0.0, 0.0)
	for y in h:
		for x in w:
			var is_edge := x == 0 or y == 0 or x == w - 1 or y == h - 1
			img.set_pixel(x, y, border if is_edge else body)
	return ImageTexture.create_from_image(img)
