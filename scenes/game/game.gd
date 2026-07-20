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
# Техническое имя лидерборда (создаётся в консоли разработчика Яндекса; в
# dev-proxy — замокан). Метрика — суммарно пройдено уровней (больше = выше).
const _LEADERBOARD: String = "progress"
# Диапазон ползунка чувствительности мыши (радиан поворота на пиксель).
const _SENS_MIN: float = 0.0005
const _SENS_MAX: float = 0.01

## Эпизоды кампании по порядку (настраиваются в инспекторе game.tscn).
## Сессия играет один эпизод; между эпизодами лоадаут сбрасывается сам —
## новая сессия = свежий игрок (модель «классика DOOM»).
@export var episodes: Array[Episode]

# Текущая игровая сессия (Node3D "Main") или null, если мы в главном меню.
var _session: Node3D = null
# Эпизод, который играет текущая сессия (для «Заново» на экранах смерти/концовки).
var _episode: Episode = null
# Главное меню (базовый экран, когда сессии нет) или null.
var _main_menu: MenuScreen = null
# Стопка оверлеев поверх базового экрана; верхний (последний) — активный.
var _overlays: Array[MenuScreen] = []

# --- Прогресс кампании (для облачного персиста и резюма, Этап 4) ---
# Индекс текущего эпизода в `episodes` (задаётся при выборе эпизода). Пара
# (эпизод, уровень) — ключ облачного сейва: эпизод знает роутер, уровень — сессия.
var _episode_index: int = 0
# Зеркало индекса уровня внутри эпизода (сессия хранит свой; держим синхронно,
# чтобы сохранять позицию без обращения внутрь сессии).
var _current_level_index: int = 0


func _ready() -> void:
	# Роутер живёт и на паузе — иначе меню перестало бы реагировать,
	# когда мы ставим дерево на паузу для оверлея.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_show_main_menu()
	# Сообщаем площадке, что игра загрузилась и готова к взаимодействию — Яндекс
	# убирает свою «крутилку» загрузки. no-op вне веба. Идемпотентно (обёртка
	# сама дождётся готовности SDK, если init ещё не завершился).
	YandexSDK.notify_game_ready()
	# Облачный сейв подъезжает асинхронно (в вебе — после init). Когда придёт,
	# пере-соберём главное меню: если есть сохранение, в нём появится «Продолжить».
	YandexSDK.cloud_loaded.connect(_on_cloud_loaded_menu)


# Облако загрузилось: если мы всё ещё в главном меню — пересоберём его, чтобы
# показать/скрыть «Продолжить» по факту наличия сейва.
func _on_cloud_loaded_menu() -> void:
	if _session == null and _overlays.is_empty() and _main_menu != null:
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
	var items: Array = [{"id": &"start", "label": "Старт"}]
	# «Продолжить» — только если есть сохранённая позиция (последний эпизод/уровень).
	if _has_save():
		items.append({"id": &"continue", "label": "Продолжить"})
	items.append({"id": &"settings", "label": "Настройки"})
	items.append({"id": &"leaderboard", "label": "Рекорды"})
	items.append({"id": &"quit", "label": "Выход"})
	_main_menu = _make_menu(
		"DOOM-like",
		"",
		items,
		0.0,            # без затемнения — это и есть фон
		&"",            # Esc в главном меню ничего не делает
		_BASE_LAYER
	)
	_main_menu.selected.connect(_on_main_menu_selected)
	add_child(_main_menu)
	_refresh_mode()


# Запустить новую игровую сессию выбранного эпизода (новая игра / переигровка).
# start_level — с какого уровня эпизода начать (резюм из облака; 0 = сначала).
func start_game(episode: Episode, start_level: int = 0) -> void:
	if episode == null or episode.levels.is_empty():
		push_error("Game: эпизод пуст — нечего запускать.")
		return
	if _main_menu != null:
		_main_menu.queue_free()
		_main_menu = null
	_clear_overlays()
	_clear_session()

	_episode = episode
	# Кламп на случай, если сохранённый уровень уехал за границы (эпизод укоротили).
	_current_level_index = clampi(start_level, 0, episode.levels.size() - 1)
	_session = SESSION_SCENE.instantiate() as Node3D
	# Роутер — ALWAYS (живёт на паузе ради меню). Без явного PAUSABLE сессия
	# унаследовала бы ALWAYS от роутера и НЕ вставала бы на паузу — тогда игрок
	# продолжал бы ловить ввод и перехватывал клики по кнопкам меню.
	_session.process_mode = Node.PROCESS_MODE_PAUSABLE
	# Какой эпизод играть — задаём ДО add_child (перекрывает отладочный эпизод
	# из инспектора main.tscn). Утиный set, как и сигналы ниже.
	_session.set(&"episode", episode)
	# Стартовый уровень внутри эпизода (резюм). Тоже ДО add_child — иначе _load_level
	# в _ready сессии стартует с 0. no-op для start_level=0.
	_session.call(&"set_start_level", _current_level_index)
	# Сигналы сессии наверх. Подключаем по имени (строкой) — у роутера нет
	# статического знания о сигналах чужого скрипта, connect() это снимает.
	_session.connect(&"player_died", _on_player_died)
	_session.connect(&"pause_requested", _on_pause_requested)
	# Поток уровней: пройден уровень / пройден эпизод → роутер показывает экран.
	_session.connect(&"level_completed", _on_level_completed)
	_session.connect(&"episode_completed", _on_episode_completed)
	add_child(_session)
	_refresh_mode()
	# Фиксируем текущую позицию в сейв сразу на старте — чтобы «Продолжить»
	# возобновляло даже с 1-го уровня (полноценная система сохранений).
	_save_progress()


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
	var items: Array = [
		{"id": &"resume", "label": "Продолжить"},
		{"id": &"settings", "label": "Настройки"},
		{"id": &"save", "label": "Сохранить"},
		{"id": &"load", "label": "Загрузить"},
	]
	# Rewarded-реклама: пункт есть только когда платформа онлайн (в вебе под
	# Яндексом). Вне веба SDK офлайн → пункт скрыт, меню паузы как прежде.
	if YandexSDK.is_online():
		items.append({"id": &"resupply_ad", "label": "Пополнить запасы (реклама)"})
	items.append({"id": &"to_menu", "label": "В главное меню"})
	_open_overlay(
		"Пауза",
		"",
		items,
		0.6,
		&"resume",      # Esc = продолжить
		_on_pause_selected
	)


# Пройден уровень, впереди ещё есть — промежуточный экран. По "Дальше" говорим
# сессии переключиться (call down); индекс уровня знает сессия, не роутер.
func _on_level_completed() -> void:
	_open_overlay(
		"Уровень пройден",
		"",
		[{"id": &"next", "label": "Дальше"}],
		0.85,
		&"",            # Esc не закрывает — нужно осознанно нажать "Дальше"
		_on_intermission_selected
	)


func _on_intermission_selected(id: StringName) -> void:
	if id != &"next":
		return
	# Точка показа полноэкранной рекламы — на стыке уровней (Яндекс сам троттлит
	# частоту). Ждём закрытия и только потом свапаем уровень. Вне веба обёртка
	# отвечает мгновенно (shown=false) — поток не застревает.
	YandexSDK.show_interstitial()
	await YandexSDK.interstitial_finished
	# Оверлей мог закрыться иначе за время await (напр. выход в меню) — проверяем.
	if _session == null:
		return
	# Сперва свап уровня, потом закрытие оверлея: его _refresh_mode зафиксирует
	# режим мыши последним (иначе _ready нового игрока перебил бы захват на VISIBLE).
	_current_level_index += 1
	_session.call(&"advance_level")
	_save_progress()
	_close_top_overlay()


# Пройден последний уровень эпизода — концовка. Дальше — главное меню
# (новый эпизод начинается оттуда со свежим лоадаутом).
func _on_episode_completed() -> void:
	# Эпизод пройден целиком: фиксируем прогресс и шлём очки в лидерборд.
	_save_progress()
	YandexSDK.leaderboard_submit(_LEADERBOARD, _levels_cleared_total())
	var body := "Эпизод пройден."
	if _episode != null:
		body = _episode.ending_text if not _episode.ending_text.is_empty() \
				else "«%s» — пройден." % _episode.title
	_open_overlay(
		"ЭПИЗОД ПРОЙДЕН",
		body,
		[
			{"id": &"to_menu", "label": "В главное меню"},
			{"id": &"replay", "label": "Переиграть эпизод"},
		],
		0.92,           # почти непрозрачно — это финальный экран эпизода
		&"",            # Esc не закрывает
		_on_episode_end_selected
	)


func _on_episode_end_selected(id: StringName) -> void:
	match id:
		&"replay":
			start_game(_episode)    # тот же эпизод с уровня 0 (новая сессия)
		&"to_menu":
			_show_main_menu()


# --------------------------------------------------------------------------
# Обработка выбора в меню
# --------------------------------------------------------------------------

func _on_main_menu_selected(id: StringName) -> void:
	match id:
		&"start":
			_open_episode_select()
		&"continue":
			_continue_saved()
		&"settings":
			_open_settings()
		&"leaderboard":
			_open_leaderboard()
		&"quit":
			_quit_app()


# --------------------------------------------------------------------------
# Выбор эпизода
# --------------------------------------------------------------------------

# «Старт» → экран выбора эпизода (тот же MenuScreen: кнопка на эпизод + «Назад»).
func _open_episode_select() -> void:
	if episodes.is_empty():
		push_error("Game: не назначены эпизоды (инспектор game.tscn).")
		return
	var items: Array = []
	for i in episodes.size():
		var ep := episodes[i]
		if ep == null:
			continue
		# id несёт индекс эпизода — разбирается в _on_episode_selected.
		items.append({"id": StringName("ep_%d" % i), "label": ep.title})
	items.append({"id": &"back", "label": "Назад"})
	_open_overlay(
		"Выбор эпизода",
		"",
		items,
		0.92,           # почти непрозрачно — это отдельный экран
		&"back",        # Esc = назад в главное меню
		_on_episode_selected
	)


func _on_episode_selected(id: StringName) -> void:
	if id == &"back":
		_close_top_overlay()
		return
	var index := String(id).trim_prefix("ep_").to_int()
	if index < 0 or index >= episodes.size():
		return
	_episode_index = index
	# Выбор главы ВСЕГДА стартует с 1-го уровня (решение 2026-07-10). Продолжение
	# с сохранённой позиции — отдельной кнопкой «Продолжить» в главном меню.
	start_game(episodes[index], 0)


func _on_pause_selected(id: StringName) -> void:
	match id:
		&"resume":
			_close_top_overlay()
		&"settings":
			_open_settings()
		&"save":
			_save_progress()
			_open_stub("Сохранение", _save_status_text("Прогресс сохранён."))
		&"load":
			_load_saved()
		&"resupply_ad":
			_watch_ad_for_resupply()
		&"to_menu":
			_show_main_menu()


func _on_game_over_selected(id: StringName) -> void:
	match id:
		&"restart":
			# Рестарт уровня делает сессия НА МЕСТЕ: сохраняет индекс кампании
			# и не перезапускает эмбиент. Прежней грабли с self/get_viewport()
			# нет — узел сессии жив, reload_current_scene не зовём. Закрытие
			# оверлея — последним: его _refresh_mode зафиксирует захват мыши после
			# того, как _ready нового игрока поставит её VISIBLE.
			if _session != null:
				_session.call(&"restart_level")
			_close_top_overlay()
		&"to_menu":
			_show_main_menu()


# Заглушки (Настройки/Сохранение/Загрузка) — у всех одна кнопка "Назад".
func _on_overlay_back(_id: StringName) -> void:
	_close_top_overlay()


# --------------------------------------------------------------------------
# Общие под-экраны (тот самый "один код, два входа")
# --------------------------------------------------------------------------

func _open_settings() -> void:
	# Ползунки берут текущее из синглтона Settings; правки летят обратно ему
	# через value_changed (применяются на лету, дебаунс-запись на диск — в Settings).
	_open_overlay(
		"Настройки",
		"",
		[
			{"type": &"slider", "id": &"vol_master", "label": "Громкость (общая)",
				"min": 0.0, "max": 1.0, "step": 0.05, "value": Settings.master_volume},
			{"type": &"slider", "id": &"vol_sfx", "label": "Громкость боя",
				"min": 0.0, "max": 1.0, "step": 0.05, "value": Settings.sfx_volume},
			{"type": &"slider", "id": &"vol_ambient", "label": "Громкость фона",
				"min": 0.0, "max": 1.0, "step": 0.05, "value": Settings.ambient_volume},
			{"type": &"slider", "id": &"sens", "label": "Чувствительность мыши",
				"min": _SENS_MIN, "max": _SENS_MAX, "step": 0.0005,
				"value": Settings.mouse_sensitivity},
			{"id": &"back", "label": "Назад"},
		],
		0.92,           # почти непрозрачно — это отдельный экран
		&"back",        # Esc = назад
		_on_settings_selected,
		_on_settings_value_changed
	)


func _on_settings_selected(id: StringName) -> void:
	if id == &"back":
		_close_top_overlay()


func _on_settings_value_changed(id: StringName, value: float) -> void:
	match id:
		&"vol_master":
			Settings.set_master_volume(value)
		&"vol_sfx":
			Settings.set_sfx_volume(value)
		&"vol_ambient":
			Settings.set_ambient_volume(value)
		&"sens":
			Settings.set_mouse_sensitivity(value)


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
# Yandex SDK: прогресс кампании (облачный сейв) и лидерборд
# --------------------------------------------------------------------------

# Секция "progress" облачного блоба (общий блоб делят Settings и прогресс).
# Форма: { "furthest": {"<эпизод>": уровень}, "last_episode": i, "last_level": j }.
func _progress() -> Dictionary:
	return YandexSDK.get_section("progress")


# Самый дальний пройденный уровень эпизода (для резюма). Нет данных → 0.
func _furthest_level(episode_index: int) -> int:
	var furthest: Dictionary = _progress().get("furthest", {})
	return int(furthest.get(str(episode_index), 0))


# Есть ли сохранённая позиция для «Продолжить» (валидный последний эпизод).
func _has_save() -> bool:
	var p := _progress()
	if not p.has("last_episode"):
		return false
	var ep := int(p.get("last_episode", -1))
	return ep >= 0 and ep < episodes.size() and episodes[ep] != null


# «Продолжить» из главного меню: возобновить последнюю сохранённую позицию.
func _continue_saved() -> void:
	var p := _progress()
	var ep := int(p.get("last_episode", 0))
	var lvl := int(p.get("last_level", 0))
	if ep < 0 or ep >= episodes.size() or episodes[ep] == null:
		return
	_episode_index = ep
	start_game(episodes[ep], lvl)


# Записать текущую позицию (эпизод, уровень) в облако. Хранит максимум по каждому
# эпизоду (резюм не откатывает) + последнюю позицию. Флаш — no-op вне веба (локально).
func _save_progress() -> void:
	var p := _progress()
	var furthest: Dictionary = p.get("furthest", {})
	var key := str(_episode_index)
	furthest[key] = maxi(int(furthest.get(key, 0)), _current_level_index)
	p["furthest"] = furthest
	p["last_episode"] = _episode_index
	p["last_level"] = _current_level_index
	YandexSDK.set_section("progress", p)
	YandexSDK.flush()


# Очко лидерборда — суммарно достигнуто уровней по всем эпизодам (монотонно растёт).
func _levels_cleared_total() -> int:
	var furthest: Dictionary = _progress().get("furthest", {})
	var total := 0
	for k in furthest.keys():
		total += int(furthest[k]) + 1
	return total


# «Загрузить» из паузы: перезапустить текущий эпизод с сохранённого уровня.
func _load_saved() -> void:
	if _episode == null:
		return
	# Закрываем паузу и стартуем сессию заново с дальнего уровня (свежий лоадаут).
	_clear_overlays()
	start_game(_episode, _furthest_level(_episode_index))


func _save_status_text(msg: String) -> String:
	return msg + ("\n(облако Яндекса)" if YandexSDK.is_online() else "\n(локально)")


# Rewarded-реклама из паузы: за просмотр — полное пополнение HP/патронов.
func _watch_ad_for_resupply() -> void:
	YandexSDK.show_rewarded()
	var rewarded: bool = await YandexSDK.rewarded_finished
	# Сессия могла исчезнуть за время показа (выход в меню) — проверяем.
	if not rewarded or _session == null:
		return
	_session.call(&"grant_resupply")
	# Закрываем паузу — возвращаемся в бой с полными запасами.
	_close_top_overlay()


# «Рекорды»: тянем таблицу и показываем её текстом. Гость видит таблицу, но в неё
# не попадает (setScore только для авторизованных) — предлагаем войти. Вне веба — заглушка.
func _open_leaderboard() -> void:
	YandexSDK.leaderboard_fetch(_LEADERBOARD)
	var entries: Array = await YandexSDK.leaderboard_loaded
	var body := _format_leaderboard(entries)
	var items: Array = []
	if YandexSDK.is_online() and not YandexSDK.is_authorized():
		body += "\n\nВойдите, чтобы попадать в таблицу."
		items.append({"id": &"login", "label": "Войти"})
	items.append({"id": &"back", "label": "Назад"})
	_open_overlay("Рекорды", body, items, 0.92, &"back", _on_leaderboard_selected)


func _on_leaderboard_selected(id: StringName) -> void:
	match id:
		&"login":
			YandexSDK.open_auth()
			var ok: bool = await YandexSDK.auth_finished
			_close_top_overlay()
			if ok:
				_open_leaderboard()  # перечитать таблицу уже авторизованным
		&"back":
			_close_top_overlay()


func _format_leaderboard(entries: Array) -> String:
	if entries.is_empty():
		# Онлайн, но пусто — борд ещё не создан в консоли или нет записей.
		# Офлайн (десктоп/вне Яндекса) — SDK недоступен.
		if YandexSDK.is_online():
			return "Пока нет записей\n(или лидерборд «progress» не создан в консоли)."
		return "Таблица недоступна\n(офлайн или запуск вне Яндекс Игр)."
	var lines: PackedStringArray = []
	for e in entries:
		if e is Dictionary:
			lines.append("%d. %s — %d" % [
				int(e.get("rank", 0)), str(e.get("name", "Аноним")), int(e.get("score", 0))])
	return "\n".join(lines)


# --------------------------------------------------------------------------
# Стопка оверлеев
# --------------------------------------------------------------------------

# Открыть оверлей поверх текущего экрана. Esc/клики идут только верхнему.
# on_changed (опц.) — обработчик value_changed ползунков (нужен экрану настроек).
func _open_overlay(title: String, body: String, items: Array, dim: float,
		back_id: StringName, on_selected: Callable, on_changed: Callable = Callable()) -> void:
	# Текущий верх деактивируем — Esc должен уходить только новому верхнему.
	if not _overlays.is_empty():
		var current_top: MenuScreen = _overlays.back()
		current_top.set_active(false)

	var m := _make_menu(title, body, items, dim, back_id, _BASE_LAYER + _overlays.size() + 1)
	m.selected.connect(on_selected)
	if on_changed.is_valid():
		m.value_changed.connect(on_changed)
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
	# GameplayAPI площадки: «активный геймплей» ровно тогда, когда мышь захвачена
	# (в игре и без оверлея). Влияет на метрики/троттлинг рекламы. no-op вне веба.
	if in_game and not overlay_open:
		YandexSDK.gameplay_start()
	else:
		YandexSDK.gameplay_stop()


func _quit_app() -> void:
	# В вебе обычно no-op (вкладку не закрыть). На Этапе 4 заменим на
	# вызов Yandex SDK (выход / показ рекламы).
	get_tree().quit()
