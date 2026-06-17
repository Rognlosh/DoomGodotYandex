@tool
class_name DirectionalSprite3D
extends Sprite3D
## Спрайт врага с думовскими ракурсами + покадровой анимацией.
## Висит прямо на узле Sprite3D (биллборд Y). Каждый кадр (в игре):
##   1) считает угол между «куда смотрит враг» (поворот родителя) и камерой,
##   2) выбирает столбец-ракурс атласа (+ flip_h для левой половины круга),
##   3) листает кадры текущей анимации по таймеру.
## Реюзабелен: любой враг вешает этот же скрипт на свой Sprite3D и заполняет
## массив animations своим атласом — кода под нового врага не пишем.
## @tool: в редакторе НЕ анимируется, а показывает один статичный idle-кадр
## (иначе Sprite3D рисует весь атлас сеткой — нарезка ставится только в рантайме).

## Текущая анимация доиграла (для невозвратных — атака/смерть).
signal animation_finished(anim_name: StringName)

@export_group("Атлас")
## Сколько РИСУЕМЫХ ракурсов-столбцов: думовские 5 (фронт, фронт-¾, профиль,
## спина-¾, спина). Левая половина круга — зеркало, в атласе её нет.
@export var columns: int = 5:
	set(value):
		columns = value
		_refresh_editor_preview()
## Набор анимаций (см. SpriteAnimation). Заполняется в инспекторе.
@export var animations: Array[SpriteAnimation] = []:
	set(value):
		animations = value
		_refresh_editor_preview()
## Что играть при старте (в игре).
@export var default_animation: StringName = &"walk"

@export_group("Боль")
## Имя анимации боли (флинч на получение урона).
@export var pain_animation: StringName = &"pain"
## Сколько секунд держится кадр боли, прежде чем вернуться к прежней анимации.
@export var pain_hold: float = 0.25

@export_group("Редактор")
## Какую анимацию показывать статичным превью в редакторе (берётся фронт-ракурс,
## столбец 0, первый кадр). Пусто — используется default_animation.
@export var editor_preview_animation: StringName = &"":
	set(value):
		editor_preview_animation = value
		_refresh_editor_preview()

var _by_name: Dictionary = {}
var _current: SpriteAnimation     # что показываем сейчас
var _desired: SpriteAnimation     # к чему вернуться после боли (ambient-состояние)
var _frame_index: int = 0
var _accum: float = 0.0
var _finished_emitted: bool = false
var _pain_timer: float = 0.0      # >0 — играем боль, обычные play() её не перебивают
var _enabled: bool = false
# Узел, чей поворот считаем «направлением взгляда» врага (тело-родитель).
@onready var _body: Node3D = get_parent() as Node3D


func _ready() -> void:
	# Нет атласа или анимаций — статичный плейсхолдер (один спрайт).
	# Плейсхолдер генерим только в игре, чтобы не запекать его в сцену из редактора.
	if texture == null or animations.is_empty():
		if texture == null and not Engine.is_editor_hint():
			texture = _make_placeholder_texture()
		hframes = 1
		vframes = 1
		frame = 0
		_enabled = false
		return

	# Раскладываем атлас сеткой: ширина — ракурсы, высота — суммарные строки.
	hframes = columns
	vframes = _compute_total_rows()
	for a in animations:
		if a != null:
			_by_name[a.name] = a

	# В редакторе анимацию НЕ запускаем — показываем один статичный idle-кадр.
	if Engine.is_editor_hint():
		_show_editor_preview()
		_enabled = false
		return

	_enabled = true
	play(default_animation)


func _process(delta: float) -> void:
	# В редакторе покадровая/ракурсная логика не нужна (нет игровой камеры) — превью статично.
	if Engine.is_editor_hint():
		return
	if not _enabled or _current == null:
		return
	if _pain_timer > 0.0:
		_pain_timer -= delta
		if _pain_timer <= 0.0 and _desired != null:
			_switch_to(_desired)  # боль кончилась — вернуться к прежней анимации
	_advance_frame(delta)
	_update_cell()


## Переключить ambient-анимацию (ходьба/атака). Во время боли только запоминаем
## желаемое — на экране держится боль. force=true перебивает боль (смерть).
func play(anim_name: StringName, force: bool = false) -> void:
	var a: SpriteAnimation = _by_name.get(anim_name)
	if a == null:
		return
	_desired = a
	if _pain_timer > 0.0 and not force:
		return
	if force:
		_pain_timer = 0.0
	_switch_to(a)


## Сыграть кадр боли на pain_hold секунд (перебивает текущее, кроме смерти —
## смерть зовётся через play(..., force=true) и сама обнуляет боль).
func hurt() -> void:
	var p: SpriteAnimation = _by_name.get(pain_animation)
	if p == null:
		return
	_pain_timer = pain_hold
	_set_anim(p)  # принудительно, даже если уже боль (повторный удар — заново)


# Переключение без перезапуска той же зацикленной (чтобы ходьба не дёргалась).
func _switch_to(a: SpriteAnimation) -> void:
	if a == _current and a.loop:
		return
	_set_anim(a)


func _set_anim(a: SpriteAnimation) -> void:
	_current = a
	_frame_index = 0
	_accum = 0.0
	_finished_emitted = false


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
		if a != null:
			rows = maxi(rows, a.row_start + a.frame_count)
	return rows


# --- Редактор: статичное превью одного idle-кадра ---

# Пересобрать превью при правке атласа/анимаций в инспекторе.
func _refresh_editor_preview() -> void:
	if not Engine.is_editor_hint() or not is_node_ready():
		return
	if texture == null or animations.is_empty():
		return
	hframes = columns
	vframes = _compute_total_rows()
	_by_name.clear()
	for a in animations:
		if a != null:
			_by_name[a.name] = a
	_show_editor_preview()


# Показать один кадр: фронт-ракурс (столбец 0), первый кадр выбранной анимации.
func _show_editor_preview() -> void:
	var preview := editor_preview_animation
	if preview == &"" or not _by_name.has(preview):
		preview = default_animation
	var a: SpriteAnimation = _by_name.get(preview)
	if a == null and not animations.is_empty():
		a = animations[0]
	if a == null:
		return
	flip_h = false
	frame = a.row_start * columns  # столбец 0, первый кадр


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
