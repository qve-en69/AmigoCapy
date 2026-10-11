# AmigoClick

Автокликер для macOS 13+ (Apple Silicon и Intel): интервал в миллисекундах, клик под курсором или в выбранную точку, глобальная клавиша старта и стопа (по умолчанию `6`).

## Как получить AmigoClick.dmg

Собрать приложение для Mac на Windows нельзя, поэтому сборка идёт на macOS-машине GitHub (бесплатно для публичных и приватных репозиториев в пределах лимита).

1. Создай репозиторий на GitHub и залей туда эту папку целиком (вместе с `.github/`).
2. Каждый пуш в `main` запускает сборку: вкладка **Actions** → последний запуск **Build macOS app** → внизу блок **Artifacts** → `AmigoClick` (внутри zip лежит `AmigoClick.dmg`).
3. Чтобы получить постоянную ссылку для друзей, поставь тег версии:
   ```
   git tag v1.0
   git push origin v1.0
   ```
   Тогда `AmigoClick.dmg` появится во вкладке **Releases**, и ссылку можно просто переслать.

Собрать вручную на Mac: `bash scripts/build.sh` (нужны Xcode или Command Line Tools), результат в `dist/`.

## Что сказать друзьям

Инструкция лежит внутри dmg (`Как установить.txt`, исходник в [docs/install-ru.txt](docs/install-ru.txt)). Коротко:

- приложение не подписано сертификатом Apple, поэтому первый запуск через «Конфиденциальность и безопасность → Всё равно открыть» (или `xattr -cr /Applications/AmigoClick.app`);
- нужно включить AmigoClick в «Универсальном доступе», иначе macOS не пропустит клики.

## Устройство

| Файл | Что делает |
| --- | --- |
| `Sources/AmigoClick/ClickEngine.swift` | Таймер на отдельной очереди и отправка кликов через `CGEvent` |
| `Sources/AmigoClick/HotKey.swift` | Глобальная клавиша через Carbon `RegisterEventHotKey` |
| `Sources/AmigoClick/LocationPicker.swift` | Затемнение всех экранов и выбор точки |
| `Sources/AmigoClick/ClickerModel.swift` | Состояние, настройки, права доступа |
| `Sources/AmigoClick/ContentView.swift` | Интерфейс на SwiftUI |
| `scripts/build.sh` | Universal-бинарь, иконка, ad-hoc подпись, dmg |
