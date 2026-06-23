extends Node
## Координатор-роутер игры. Новая точка входа приложения.
## Владеет тем, что сейчас на экране: либо главное меню, либо игровая сессия,
## плюс стопка оверлеев поверх (пауза, Game Over, заглушки настроек/сейва/лоада).
##
## Все меню/оверлеи — один переиспользуемый MenuScreen, конфигурируется ДАННЫМИ
## отсюда. Поэтому "Настройки / Сохранение / Загрузка" открываются ОДНИМ и тем же
## кодом и из главного меню, и из паузы — "написаны один раз, два входа".
##
## Сессия — "тупой" геймплей: грузит уровень/игрока/HUD и шлёт наверх сигналы
## (player_died, pause_requested). Решения "пауза / оверлей / смена экрана" — здесь.

# Сессия — это нынешняя точка входа геймплея (уровень + игрок + HUD + звук).
const SESSION_SCENE: PackedScene = preload("res://scenes/main/main.tscn")
# Переиспользуемый экран меню (строит кнопки кодом).
const MENU_SCENE: PackedScene = preload("res://scenes/ui/menus/menu_screen.tscn")

# CanvasLayer.layer базового меню; оверлеи кладутся выше (см. _open_overlay).
const _BASE_LAYER: int = 20
# Текст-заглушка для разделов, которые приедут с интеграцией Yandex SDK.
const _YANDEX_STUB: String = "Появится с интеграцией Yandex Games SDK (Этап 4)."

# Текущая игровая сессия (Node3D "Main") или null, если мы в главном меню.
var _session: Node3D = null
# Главное меню (базовый экран, когда сессии нет) или null.
var _main_menu: MenuScreen = null
# Стопка оверлеев поверх базового экрана; верхний (последний) — активный.
var _overlays: Array[MenuScreen] = []


func _ready() -> void:
	# Роутер живёт и на паузе — иначе меню перестало бы реагировать,
	# когда мы ставим дерево на паузу для оверлея.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_show_main_menu()


# --------------------------------------------------------------------------
# Базовые экраны
# --------------------------------------------------------------------------

# Показать главное меню: снести сессию и оверлеи, поднять меню заново.
func _show_main_menu() -> void:
	_clear_session()
	_clear_overlays()
	if _main_menu != null:
		_main_menu.queue_free()
	_main_menu = _make_menu(
		"DOOM-like",
		"",
		[
			{"id": &"start", "label": "Старт"},
			{"id": &"settings", "label": "Настройки"},
			{"id": &"quit", "label": "Выход"},
		],
		0.0,            # без затемнения — это и есть фон
		&"",            # Esc в главном меню ничего не делает
		_BASE_LAYER
	)
	_main_menu.selected.connect(_on_main_menu_selected)
	add_child(_main_menu)
	_refresh_mode()


# Запустить новую игровую сессию (новая игра / рестарт).
func start_game() -> void:
	if _main_menu != null:
		_main_menu.queue_free()
		_main_menu = null
	_clear_overlays()
	_clear_session()

	_session = SESSION_SCENE.instantiate() as Node3D
	# Роутер — ALWAYS (живёт на паузе ради меню). Без явного PAUSABLE сессия
	# унаследовала бы ALWAYS от роутера и НЕ вставала бы на паузу — тогда игрок
	# продолжал бы ловить ввод и перехватывал клики по кнопкам меню.
	_session.process_mode = Node.PROCESS_MODE_PAUSABLE
	# Сигналы сессии наверх. Подключаем по имени (строкой) — у роутера нет
	# статического знания о сигналах чужого скрипта, connect() это снимает.
	_session.connect(&"player_died", _on_player_died)
	_session.connect(&"pause_requested", _on_pause_requested)
	add_child(_session)
	_refresh_mode()


# --------------------------------------------------------------------------
# Сигналы сессии
# --------------------------------------------------------------------------

func _on_player_died() -> void:
	_open_overlay(
		"YOU DIED",
		"",
		[
			{"id": &"restart", "label": "Заново"},
			{"id": &"to_menu", "label": "В главное меню"},
		],
		0.55,           # полупрозрачно — труп и сцена видны позади
		&"",            # Esc на экране смерти не закрывает
		_on_game_over_selected
	)


func _on_pause_requested() -> void:
	# Уже есть оверлей — второй паузой не накрываем.
	if not _overlays.is_empty():
		return
	_open_overlay(
		"Пауза",
		"",
		[
			{"id": &"resume", "label": "Продолжить"},
			{"id": &"settings", "label": "Настройки"},
			{"id": &"save", "label": "Сохранить"},
			{"id": &"load", "label": "Загрузить"},
			{"id": &"to_menu", "label": "В главное меню"},
		],
		0.6,
		&"resume",      # Esc = продолжить
		_on_pause_selected
	)


# --------------------------------------------------------------------------
# Обработка выбора в меню
# --------------------------------------------------------------------------

func _on_main_menu_selected(id: StringName) -> void:
	match id:
		&"start":
			start_game()
		&"settings":
			_open_settings()
		&"quit":
			_quit_app()


func _on_pause_selected(id: StringName) -> void:
	match id:
		&"resume":
			_close_top_overlay()
		&"settings":
			_open_settings()
		&"save":
			_open_stub("Сохранение", _YANDEX_STUB)
		&"load":
			_open_stub("Загрузка", _YANDEX_STUB)
		&"to_menu":
			_show_main_menu()


func _on_game_over_selected(id: StringName) -> void:
	match id:
		&"restart":
			start_game()
		&"to_menu":
			_show_main_menu()


# Заглушки (Настройки/Сохранение/Загрузка) — у всех одна кнопка "Назад".
func _on_overlay_back(_id: StringName) -> void:
	_close_top_overlay()


# --------------------------------------------------------------------------
# Общие под-экраны (тот самый "один код, два входа")
# --------------------------------------------------------------------------

func _open_settings() -> void:
	_open_stub("Настройки", "Раздел в разработке.")


func _open_stub(title: String, body: String) -> void:
	_open_overlay(
		title,
		body,
		[{"id": &"back", "label": "Назад"}],
		0.92,           # почти непрозрачно — это отдельный экран
		&"back",        # Esc = назад
		_on_overlay_back
	)


# --------------------------------------------------------------------------
# Стопка оверлеев
# --------------------------------------------------------------------------

# Открыть оверлей поверх текущего экрана. Esc/клики идут только верхнему.
func _open_overlay(title: String, body: String, items: Array, dim: float,
		back_id: StringName, on_selected: Callable) -> void:
	# Текущий верх деактивируем — Esc должен уходить только новому верхнему.
	if not _overlays.is_empty():
		var current_top: MenuScreen = _overlays.back()
		current_top.set_active(false)

	var m := _make_menu(title, body, items, dim, back_id, _BASE_LAYER + _overlays.size() + 1)
	m.selected.connect(on_selected)
	_overlays.push_back(m)
	add_child(m)
	_refresh_mode()


# Закрыть верхний оверлей и вернуть управление тому, что под ним.
func _close_top_overlay() -> void:
	if _overlays.is_empty():
		return
	var top: MenuScreen = _overlays.pop_back()
	top.queue_free()
	if not _overlays.is_empty():
		var below: MenuScreen = _overlays.back()
		below.set_active(true)
	_refresh_mode()


func _clear_overlays() -> void:
	for m in _overlays:
		m.queue_free()
	_overlays.clear()


func _clear_session() -> void:
	if _session != null:
		_session.queue_free()
		_session = null


# --------------------------------------------------------------------------
# Вспомогательное
# --------------------------------------------------------------------------

# Собрать сконфигурированный MenuScreen (поля задаются ДО add_child).
func _make_menu(title: String, body: String, items: Array, dim: float,
		back_id: StringName, layer_index: int) -> MenuScreen:
	var m := MENU_SCENE.instantiate() as MenuScreen
	m.title_text = title
	m.body_text = body
	m.items = items
	m.dim = dim
	m.back_id = back_id
	m.layer_index = layer_index
	return m


# Единая точка истины для паузы и режима мыши.
# Пауза дерева — только когда мы в игре И открыт оверлей.
# Мышь свободна в меню/оверлее, захвачена в чистом геймплее.
func _refresh_mode() -> void:
	var in_game := _session != null
	var overlay_open := not _overlays.is_empty()
	get_tree().paused = in_game and overlay_open
	if overlay_open or not in_game:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _quit_app() -> void:
	# В вебе обычно no-op (вкладку не закрыть). На Этапе 4 заменим на
	# вызов Yandex SDK (выход / показ рекламы).
	get_tree().quit()
