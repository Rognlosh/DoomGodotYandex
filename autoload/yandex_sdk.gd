extends Node
## Обёртка над Yandex Games SDK. ВТОРОЙ autoload проекта (после Settings).
##
## Единая точка доступа игры к платформе Яндекса: облачные сейвы, реклама,
## лидерборды, LoadingAPI/GameplayAPI, язык интерфейса. Игра НИКОГДА не дёргает
## JavaScriptBridge напрямую — только этот синглтон (как весь звук идёт через
## CombatAudio, а настройки — через Settings).
##
## Реализация — своя тонкая обёртка поверх JavaScriptBridge (решение 2026-07-09:
## не тянуть сторонний аддон, привязанный к чужой поддержке версий Godot). JS-часть
## моста (подключение sdk.js + хелперы window.GodotYSDK) лежит в web/head_include.html
## и вставляется в <head> при веб-экспорте (html/head_include).
##
## КЛЮЧЕВОЙ ПРИНЦИП — БЕЗОПАСНЫЙ ФОЛБЭК. Вне веба (редактор, десктоп-сборка, запуск
## HTML не в среде Яндекса) SDK недоступен: тогда сейвы уходят в локальный
## user://cloud_save.json, реклама — мгновенный no-op (поток игры не застревает),
## лидерборды/LoadingAPI/GameplayAPI — тихо игнорируются. Поэтому уже
## протестированный десктоп-флоу (F6, ручные прогоны) ведёт себя как прежде, а
## веб-поведение добавляется поверх.
##
## Асинхронность JS (промисы) разворачивается в СИГНАЛЫ Godot: вызвал метод —
## жди сигнал. JS-хелперы возвращают результат одной строкой JSON в переданный
## колбэк (JavaScriptBridge.create_callback), тут строка парсится обратно в Dictionary.

# --- Готовность платформы ---
## SDK инициализировался и готов к работе (online). offline → работаем на фолбэке.
## Приходит один раз после YaGames.init(); до него is_online() == false.
signal platform_resolved(online: bool)

# --- Облачное хранилище ---
## Облачный блоб загружен (или взят из локального фолбэка). Потребители (Settings,
## прогресс кампании) читают свою секцию через get_section().
signal cloud_loaded()
## Флаш сейва завершён (ok — успешно записано в облако/локально).
signal save_finished(ok: bool)

# --- Реклама ---
## Полноэкранная (interstitial) реклама закрыта. shown — была ли реально показана
## (Яндекс сам троттлит частоту: слишком часто → shown=false, но поток продолжаем).
signal interstitial_finished(shown: bool)
## Rewarded-реклама завершена. rewarded — засчитан ли просмотр (выдавать награду).
signal rewarded_finished(rewarded: bool)

# --- Лидерборды ---
## Таблица лидерборда загружена. entries: Array[Dictionary] {rank, score, name}.
signal leaderboard_loaded(entries: Array)

# --- Авторизация ---
## Диалог входа завершён. ok — игрок авторизовался (можно слать очки в лидерборд).
signal auth_finished(ok: bool)

# Путь локального фолбэк-сейва (тот же блоб, что ушёл бы в облако). В вебе Godot
# кладёт user:// в IndexedDB; на десктопе — в реальную папку user://.
const _FALLBACK_PATH := "user://cloud_save.json"

# Мы в веб-сборке? Только там есть JavaScriptBridge и смысл в SDK.
var _web: bool = false
# SDK реально готов (YaGames.init() зарезолвился). false → фолбэк.
var _online: bool = false
# Инициализация уже завершилась (online или окончательно упала) — чтобы не
# резолвить дважды и знать, что platform_resolved уже отправлен.
var _resolved: bool = false
# Язык интерфейса от площадки ("ru"/"en"/...). Дефолт — русский (осн. аудитория).
var _lang: String = "ru"

# Весь облачный блоб: { "settings": {...}, "progress": {...}, ... }. Одна запись
# на игрока (лимит 200 КБ), секции делят Settings и прогресс кампании.
var _cloud: Dictionary = {}
# Блоб уже загружен (из облака или фолбэка) — потребители могут читать секции.
var _cloud_ready: bool = false
# Дедуп записи: JSON последнего УСПЕШНО записанного блоба и «в полёте».
# Идентичный flush пропускаем (dev-proxy ругается на неизменные данные).
var _last_flushed_json: String = ""
var _pending_flush_json: String = ""

# LoadingAPI.ready() надо позвать один раз, когда игра готова к взаимодействию.
# Флаг «просили» — если init ещё не готов, позовём, как только станет online.
var _want_game_ready: bool = false
var _game_ready_sent: bool = false

# Интерфейс window и хелпер window.GodotYSDK (JS-side). Создаются в _ready на вебе.
var _window: JavaScriptObject = null
var _js: JavaScriptObject = null
# Таймер опроса готовности init (промис резолвится не мгновенно).
var _poll_timer: Timer = null
# Таймер опроса результата диалога авторизации (промис тоже асинхронный).
var _auth_poll: Timer = null

# Ссылки на активные JS-колбэки: create_callback нельзя дать уехать в GC, пока
# промис не вызвал его. Держим по одному на тип операции (операции не пересекаются).
var _cb_load: JavaScriptObject = null
var _cb_save: JavaScriptObject = null
var _cb_fullscreen: JavaScriptObject = null
var _cb_rewarded: JavaScriptObject = null
var _cb_lb_set: JavaScriptObject = null
var _cb_lb_get: JavaScriptObject = null


func _ready() -> void:
	# Живём на паузе — рекламу/сейвы могут дёргать из меню (дерево на паузе).
	process_mode = Node.PROCESS_MODE_ALWAYS

	_web = OS.has_feature("web") and JavaScriptBridge.has_method("eval")
	if not _web:
		# Десктоп/редактор: сразу уходим в фолбэк, грузим локальный блоб.
		_load_fallback()
		_finish_resolve(false)
		return

	_window = JavaScriptBridge.get_interface("window")
	if _window == null:
		_load_fallback()
		_finish_resolve(false)
		return
	# window.GodotYSDK создаётся синхронно IIFE в head_include — доступен сразу.
	_js = _window.GodotYSDK
	if _js == null:
		# head_include не подключён (sdk.js/хелпер отсутствуют) — фолбэк.
		push_warning("YandexSDK: window.GodotYSDK не найден — работаем на локальном фолбэке.")
		_load_fallback()
		_finish_resolve(false)
		return

	# init асинхронный — опрашиваем флаги ready/failed из JS каждые 0.1 с.
	_poll_timer = Timer.new()
	_poll_timer.wait_time = 0.1
	_poll_timer.one_shot = false
	_poll_timer.timeout.connect(_poll_init)
	add_child(_poll_timer)
	_poll_timer.start()


# --------------------------------------------------------------------------
# Инициализация платформы
# --------------------------------------------------------------------------

func _poll_init() -> void:
	if _js == null:
		_poll_timer.stop()
		_load_fallback()
		_finish_resolve(false)
		return
	# JS выставит ровно один из флагов, когда YaGames.init() зарезолвится/упадёт.
	if bool(_js.ready):
		_poll_timer.stop()
		var l: String = str(_js.lang)
		if not l.is_empty():
			_lang = l
		_online = true
		_request_cloud_load()   # тянем облачный блоб
		_finish_resolve(true)
	elif bool(_js.failed):
		# Не в среде Яндекса или init упал — фолбэк.
		_poll_timer.stop()
		_load_fallback()
		_finish_resolve(false)


func _finish_resolve(online: bool) -> void:
	if _resolved:
		return
	_resolved = true
	_online = online
	platform_resolved.emit(online)
	# Офлайн: облачный блоб — это локальный фолбэк, он уже загружен → помечаем
	# «облако готово» синхронно. Онлайн: готовность придёт асинхронно из loadData.
	if not online:
		_finish_cloud_load()
	# Если игру уже пометили готовой до резолва — отправим LoadingAPI.ready() теперь.
	if _want_game_ready:
		_send_game_ready()


func is_online() -> bool:
	return _online


func is_resolved() -> bool:
	return _resolved


func get_lang() -> String:
	return _lang


# --------------------------------------------------------------------------
# LoadingAPI / GameplayAPI
# --------------------------------------------------------------------------

## Игра загрузилась и готова к взаимодействию — убираем «крутилку» площадки.
## Зовётся из роутера, когда поднято главное меню. Идемпотентно.
func notify_game_ready() -> void:
	_want_game_ready = true
	if _resolved:
		_send_game_ready()


func _send_game_ready() -> void:
	if _game_ready_sent:
		return
	_game_ready_sent = true
	if _online and _js != null:
		_js.ready_()


## Игрок в активном геймплее (не меню/пауза/реклама) — площадке это важно
## (метрики, троттлинг рекламы). Зовётся роутером из _refresh_mode. no-op вне веба.
func gameplay_start() -> void:
	if _online and _js != null:
		_js.gameplayStart()


func gameplay_stop() -> void:
	if _online and _js != null:
		_js.gameplayStop()


# --------------------------------------------------------------------------
# Облачное хранилище (секционный блоб)
# --------------------------------------------------------------------------

## Готов ли облачный блоб к чтению (загружен из облака или фолбэка).
func is_cloud_ready() -> bool:
	return _cloud_ready


## Прочитать секцию блоба (напр. "settings", "progress"). Нет секции → {}.
func get_section(key: String) -> Dictionary:
	var v: Variant = _cloud.get(key, {})
	return v if v is Dictionary else {}


## Записать секцию в блоб (в память) и запланировать флаш. Флаш общий — несколько
## секций, изменённых подряд, уедут одной записью (см. flush()).
func set_section(key: String, data: Dictionary) -> void:
	_cloud[key] = data


## Сохранить весь блоб (облако или локальный фолбэк). Завершение — save_finished(ok).
func flush() -> void:
	var json := JSON.stringify(_cloud)
	# Блоб не изменился с прошлой УСПЕШНОЙ записи — не тревожим setData повторно
	# (dev-proxy Яндекса на это ругается «data does not differ»; в проде — лишний трафик).
	if json == _last_flushed_json:
		save_finished.emit.call_deferred(true)
		return
	if _online and _js != null:
		_pending_flush_json = json
		_cb_save = JavaScriptBridge.create_callback(_on_save_result)
		_js.saveData(json, _cb_save)
	else:
		var ok := _write_fallback(json)
		if ok:
			_last_flushed_json = json
		# Единый контракт «метод → сигнал»: даже локально отвечаем сигналом,
		# отложенно (потребитель успевает подписаться после вызова).
		save_finished.emit.call_deferred(ok)


func _request_cloud_load() -> void:
	if _online and _js != null:
		_cb_load = JavaScriptBridge.create_callback(_on_load_result)
		_js.loadData(_cb_load)
	else:
		_finish_cloud_load()


func _on_load_result(args: Array) -> void:
	var payload: Dictionary = _parse(args)
	if bool(payload.get("ok", false)):
		var data: Variant = payload.get("data", {})
		if data is Dictionary and not (data as Dictionary).is_empty():
			_cloud = data
		else:
			# В облаке пусто (новый игрок) — пробуем локальный блоб как затравку.
			_load_fallback()
	else:
		_load_fallback()
	_finish_cloud_load()


func _finish_cloud_load() -> void:
	_cloud_ready = true
	cloud_loaded.emit()


func _on_save_result(args: Array) -> void:
	var payload: Dictionary = _parse(args)
	var ok := bool(payload.get("ok", false))
	if ok:
		# Запоминаем успешно записанный блоб — следующий идентичный flush пропустим.
		_last_flushed_json = _pending_flush_json
	save_finished.emit(ok)


# --- Локальный фолбэк (тот же блоб на диск/IndexedDB) ---

func _load_fallback() -> void:
	if not FileAccess.file_exists(_FALLBACK_PATH):
		return
	var f := FileAccess.open(_FALLBACK_PATH, FileAccess.READ)
	if f == null:
		return
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		_cloud = parsed


func _write_fallback(json: String) -> bool:
	var f := FileAccess.open(_FALLBACK_PATH, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(json)
	f.close()
	return true


# --------------------------------------------------------------------------
# Реклама
# --------------------------------------------------------------------------

## Показать полноэкранную (interstitial) рекламу. Завершение — interstitial_finished
## (shown: была ли показана). Вне веба — мгновенный no-op (shown=false), поток игры
## не застревает: подписчик всё равно получает сигнал и продолжает.
func show_interstitial() -> void:
	if _online and _js != null:
		_cb_fullscreen = JavaScriptBridge.create_callback(_on_interstitial_result)
		_js.showFullscreen(_cb_fullscreen)
	else:
		interstitial_finished.emit.call_deferred(false)


func _on_interstitial_result(args: Array) -> void:
	var payload: Dictionary = _parse(args)
	interstitial_finished.emit(bool(payload.get("shown", false)))


## Показать rewarded-рекламу. Завершение — rewarded_finished(rewarded). Вне веба —
## no-op (rewarded=false): награду не выдаём, но UI не застревает.
func show_rewarded() -> void:
	if _online and _js != null:
		_cb_rewarded = JavaScriptBridge.create_callback(_on_rewarded_result)
		_js.showRewarded(_cb_rewarded)
	else:
		rewarded_finished.emit.call_deferred(false)


func _on_rewarded_result(args: Array) -> void:
	var payload: Dictionary = _parse(args)
	# JS шлёт несколько событий: "rewarded" (засчитан) и "close"/"error" (конец).
	# Награду выдаём по "rewarded"; поток продолжаем по "close"/"error".
	var ev: String = str(payload.get("event", ""))
	match ev:
		"rewarded":
			rewarded_finished.emit(true)
		_:
			# close без предшествующего rewarded, либо error — награды нет.
			if not bool(payload.get("rewarded", false)):
				rewarded_finished.emit(false)


# --------------------------------------------------------------------------
# Лидерборды
# --------------------------------------------------------------------------

## Отправить очки в лидерборд по его техническому имени (создаётся в консоли
## разработчика Яндекса). Вне веба — no-op. Отдельного сигнала-подтверждения нет.
func leaderboard_submit(board: String, score: int) -> void:
	if _online and _js != null:
		_cb_lb_set = JavaScriptBridge.create_callback(_on_lb_set_result)
		_js.lbSetScore(board, score, _cb_lb_set)


func _on_lb_set_result(_args: Array) -> void:
	pass  # результат не нужен — отправка «выстрелил и забыл»


## Запросить таблицу лидерборда. Завершение — leaderboard_loaded(entries).
## Вне веба — пустой список (экран покажет заглушку «недоступно офлайн»).
func leaderboard_fetch(board: String) -> void:
	if _online and _js != null:
		_cb_lb_get = JavaScriptBridge.create_callback(_on_lb_get_result)
		_js.lbGetEntries(board, _cb_lb_get)
	else:
		leaderboard_loaded.emit.call_deferred([])


func _on_lb_get_result(args: Array) -> void:
	var payload: Dictionary = _parse(args)
	var entries: Variant = payload.get("entries", [])
	leaderboard_loaded.emit(entries if entries is Array else [])


# --------------------------------------------------------------------------
# Авторизация (нужна, чтобы слать очки в лидерборд)
# --------------------------------------------------------------------------

## Авторизован ли игрок сейчас. Лидерборд принимает setScore только от авторизованных;
## гость может лишь читать таблицу. Синхронно через eval (isAuthorized — синхронный).
func is_authorized() -> bool:
	if not (_online and _js != null):
		return false
	var code := "(window.GodotYSDK && window.GodotYSDK.player && " \
		+ "typeof window.GodotYSDK.player.isAuthorized === 'function') " \
		+ "? !!window.GodotYSDK.player.isAuthorized() : false"
	return bool(JavaScriptBridge.eval(code, true))


## Открыть диалог входа Яндекса. Завершение — auth_finished(ok). Через eval, чтобы
## не менять head_include: снаружи стартуем промис, результат кладём в флаг и опрашиваем.
func open_auth() -> void:
	if not (_online and _js != null):
		auth_finished.emit.call_deferred(false)
		return
	# Стартуем диалог; по успеху перечитываем игрока (станет авторизованным) и
	# выставляем флаг __auth_state, который опрашиваем таймером.
	var code := """
	(function () {
		var G = window.GodotYSDK;
		if (!G || !G.ysdk || !G.ysdk.auth) { return; }
		G.__auth_state = 'pending';
		G.ysdk.auth.openAuthDialog().then(function () {
			return G.ysdk.getPlayer({ scopes: false }).then(function (p) { G.player = p; });
		}).then(function () { G.__auth_state = 'ok'; })
		.catch(function () { G.__auth_state = 'fail'; });
	})();
	"""
	JavaScriptBridge.eval(code, true)
	if _auth_poll == null:
		_auth_poll = Timer.new()
		_auth_poll.wait_time = 0.2
		_auth_poll.one_shot = false
		_auth_poll.timeout.connect(_poll_auth)
		add_child(_auth_poll)
	_auth_poll.start()


func _poll_auth() -> void:
	var state := str(JavaScriptBridge.eval(
		"window.GodotYSDK ? (window.GodotYSDK.__auth_state || '') : ''", true))
	if state == "ok":
		_auth_poll.stop()
		auth_finished.emit(true)
	elif state == "fail":
		_auth_poll.stop()
		auth_finished.emit(false)


# --------------------------------------------------------------------------
# Вспомогательное
# --------------------------------------------------------------------------

# JS-колбэк приходит с единственным аргументом — Array из JS-аргументов; наш
# аргумент — строка JSON (первый элемент). Разбираем её в Dictionary.
func _parse(args: Array) -> Dictionary:
	if args.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(str(args[0]))
	return parsed if parsed is Dictionary else {}
