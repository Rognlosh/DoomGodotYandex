# Интеграция Yandex Games SDK — алгоритм и что куда вписано

Памятка по тому, КАК был интегрирован SDK (Этап 4, ветка `claude/yandex-sdk`):
последовательность шагов, конкретные файлы/вставки и что устанавливалось.

Сводка изменений фичи (vs `main`): 4 новых файла + правки 5 существующих.

| Файл | Роль | Новый/правка |
|---|---|---|
| `autoload/yandex_sdk.gd` | Обёртка-синглтон над SDK (~460 строк) | новый |
| `web/head_include.html` | JS-мост (подключение `sdk.js` + `window.GodotYSDK`) | новый |
| `export_presets.cfg` | Web-пресет «Web (Yandex)» | новый |
| `web/README.md` | Инструкция сборки/теста | новый |
| `project.godot` | Регистрация автолоада | правка (+1 строка) |
| `autoload/settings.gd` | Облачная синхронизация настроек | правка (+66) |
| `scenes/game/game.gd` | Точки интеграции (роутер) | правка (+244) |
| `scenes/main/main.gd` | `grant_resupply()` для rewarded | правка (+12) |
| `.gitignore` | Игнор `/build/` | правка (+3) |

---

## Про установку (коротко: в репозиторий — ничего)

- **Godot-аддон/плагин НЕ ставили.** Сознательное решение — своя обёртка вместо
  стороннего плагина. В `addons/` ничего не добавлялось, зависимостей у проекта не прибавилось.
- **SDK не бандлится в репо.** Он грузится в рантайме тегом `<script src="/sdk.js">`
  (его отдаёт хостинг Яндекса или dev-proxy). В git его нет.
- **Что реально ставится — только инструменты, вне проекта:**
  - на машине разработчика для теста: **Node.js** + `@yandex-games/sdk-dev-proxy`
    (тянется через `npx` разово, это dev-инструмент, не зависимость игры);
  - **шаблоны экспорта Godot 4.7** (стандартные, нужны для любого веб-экспорта);
  - на стороне Claude для проверки кода — `gdtoolkit` (`gdparse`/`gdlint`), к проекту
    отношения не имеет.

---

## Этап 1. Сверка API по документации

Ничего не вписывалось и не ставилось — только чтение доки (правило проекта: не по памяти).
Подтверждены: `<script src="/sdk.js">` → `YaGames.init()` → объект `ysdk`;
`ysdk.getPlayer().getData/setData`; `ysdk.adv.showFullscreenAdv/showRewardedVideo`;
`ysdk.leaderboards.setScore/getEntries`; `features.LoadingAPI.ready()` / `GameplayAPI`;
механизм Godot — `JavaScriptBridge` + поле экспорта Head Include (вставка в `<head>`).

## Этап 2. JS-сторона моста — `web/head_include.html` (новый файл)

Что вписано в файл:
- тег `<script src="/sdk.js"></script>` — подключение SDK площадки;
- IIFE, создающий **синхронно** объект-контракт `window.GodotYSDK` с полями-флагами
  `ready`/`failed`/`ysdk`/`player`/`lang`;
- функция `boot()`: `YaGames.init()` → сохраняет `ysdk`, читает язык
  `environment.i18n.lang`, поднимает игрока `getPlayer({scopes:false})`, ставит `ready=true`
  (или `failed=true`, если не в среде Яндекса);
- функции-хелперы на `window.GodotYSDK`, которые дёргает GDScript: `loadData`, `saveData`,
  `showFullscreen`, `showRewarded`, `lbSetScore`, `lbGetEntries`, `ready_`,
  `gameplayStart`, `gameplayStop`. Каждый асинхронный хелпер возвращает результат
  **одной строкой JSON** в переданный godot-колбэк.

Куда этот файл попадает в сборку: его содержимое вставляется в `<head>` при экспорте
(поле Head Include, см. Этап 6).

## Этап 3. GDScript-обёртка — `autoload/yandex_sdk.gd` (новый файл)

Автолоад-синглтон `YandexSDK`. Что внутри (по разделам файла):
- **Сигналы** (промисы JS → сигналы Godot): `platform_resolved(online)`, `cloud_loaded()`,
  `save_finished(ok)`, `interstitial_finished(shown)`, `rewarded_finished(rewarded)`,
  `leaderboard_loaded(entries)`, `auth_finished(ok)`.
- **Детект и init:** в `_ready` проверка `OS.has_feature("web")`; на вебе берёт
  `JavaScriptBridge.get_interface("window").GodotYSDK` и опрашивает таймером флаги
  `ready`/`failed` (init асинхронный). Вне веба сразу уходит в фолбэк.
- **LoadingAPI/GameplayAPI:** `notify_game_ready()`, `gameplay_start/stop()`.
- **Облачное хранилище:** секционный блоб — `get_section/set_section(key)` + `flush()`;
  локальный фолбэк в `user://cloud_save.json`; дедуп записи по JSON (не слать одинаковое).
- **Реклама:** `show_interstitial()` / `show_rewarded()`.
- **Лидерборды:** `leaderboard_submit/fetch()` (сейчас в игре отключены, метод жив).
- **Авторизация:** `is_authorized()` / `open_auth()` (через `JavaScriptBridge.eval`,
  чтобы не менять head-include).
- **Служебное:** ссылки на JS-колбэки хранятся в полях (иначе GC), парсер JSON-ответа.

Ключевой принцип во всех методах: если SDK недоступен — **немедленный фолбэк**
(сейв в `user://`, реклама/лидерборд — no-op с мгновенным сигналом), чтобы поток игры
не застревал и десктоп-поведение не менялось.

## Этап 4. Регистрация автолоада — `project.godot` (правка)

В секцию `[autoload]` дописана одна строка **после** `Settings`:

```
[autoload]
Settings="*res://autoload/settings.gd"
YandexSDK="*res://autoload/yandex_sdk.gd"   ← добавлено
```

(Godot при первом открытии сгенерировал `autoload/yandex_sdk.gd.uid` — он тоже в репозитории.)

## Этап 5. Подключение фич к игре (правки существующих файлов)

Игра общается только с синглтоном `YandexSDK` (как звук — через `CombatAudio`).

**`autoload/settings.gd`** (+66) — облачная синхронизация настроек:
- константа секции `_CLOUD_SECTION = "settings"`;
- в `_ready` — отложенное подключение к облаку (`_connect_cloud`, т.к. `YandexSDK` —
  автолоад позже);
- `_pull_from_cloud()` (применить облачные настройки), `_cloud_state()` (собрать секцию),
  `_push_to_cloud()`;
- в существующий `_write_config()` дописан вызов `_push_to_cloud()` — правки летят и в облако.

**`scenes/game/game.gd`** (+244) — точки интеграции в роутере:
- в `_ready` — `YandexSDK.notify_game_ready()` (LoadingAPI) + подписка на `cloud_loaded`
  (пересобрать меню, когда подъедет сейв);
- в `_refresh_mode()` — `gameplay_start/stop()` по состоянию (захвачена мышь = геймплей);
- в `_on_intermission_selected()` — `show_interstitial()` + `await` перед свапом уровня;
- в меню паузы — пункт «Пополнить запасы (реклама)» → `_watch_ad_for_resupply()`
  (`show_rewarded()` → по награде `_session.grant_resupply()`);
- прогресс кампании: `_save_progress()` (секция `progress`) на старте сессии и переходах,
  `_has_save()` + «Продолжить» в главном меню, старт главы всегда с 1-го уровня;
- реальные «Сохранить»/«Загрузить» в паузе (вместо прежних заглушек);
- лидерборд — код есть, но **закомментирован** (маркеры «ЛИДЕРБОРД ОТЛОЖЕН»).

**`scenes/main/main.gd`** (+12) — добавлен метод `grant_resupply()`: полное восстановление
HP и патронов (награда за rewarded-рекламу; зовётся роутером).

## Этап 6. Экспорт — `export_presets.cfg` (новый) + `.gitignore` (правка)

- Пресет **«Web (Yandex)»** с ключевыми полями: `platform="Web"`,
  `variant/thread_support=false` (Яндекс не даёт cross-origin isolation → однопоточный
  билд обязателен), `html/head_include="…"` — сюда **вшито содержимое `web/head_include.html`**,
  `export_path="build/web/index.html"`.
- Рендер не трогали — `gl_compatibility` (WebGL 2.0) уже стоял в `project.godot`.
- В `.gitignore` добавлена строка `/build/` (веб-билд в репозиторий не коммитим).
- Инструкция сборки/теста — `web/README.md` (в т.ч. запуск dev-proxy без модерации).

## Этап 7. Верификация и итерации

- Godot из контейнера не запускается → статическая проверка `gdparse`/`gdlint` по всем
  скриптам, самопроверка логики моста, коммит в ветку.
- Дальше — цикл с тестами разработчика в dev-proxy: починка UID-заминки автолоада при
  первом открытии; вывод, что SDK онлайн только внутри фрейма Яндекса; переделка резюма
  («Продолжить»); диагностика лидерборда (`setScore` требует авторизации) → отложен;
  дедуп сейва (убрать шум dev-proxy «data does not differ»).

---

### Одной строкой

Сверить API → JS-хелперы (`head_include.html`) ↔ GDScript-сигналы (`yandex_sdk.gd`) с
фолбэком → зарегистрировать автолоад (`project.godot`) → подключить к игре через синглтон
(`settings.gd`, `game.gd`, `main.gd`) → собрать Web-пресет (`export_presets.cfg`) → проверить
статикой и довести по тестам. Ничего стороннего в проект не устанавливалось.
