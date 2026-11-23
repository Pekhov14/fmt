#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIGURATION="${CONFIGURATION:-Release}"
BUILD_DIR="${BUILD_DIR:-$PWD/.build}"
INSTALL_DIR="${INSTALL_DIR:-$HOME/Applications}"

echo "Сборка fmt.app ($CONFIGURATION)..."
xcodebuild \
  -project fmt.xcodeproj \
  -scheme fmt \
  -configuration "$CONFIGURATION" \
  -destination 'platform=macOS' \
  -derivedDataPath "$BUILD_DIR" \
  -allowProvisioningUpdates \
  build

APP="$BUILD_DIR/Build/Products/$CONFIGURATION/fmt.app"
EXTENSION="$APP/Contents/PlugIns/fmtFinder.appex"

if [ ! -d "$EXTENSION" ]; then
  echo "Расширение не найдено: $EXTENSION" >&2
  exit 1
fi

EXTENSION_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' \
  "$EXTENSION/Contents/Info.plist")"

# xcodebuild регистрирует расширение из папки сборки, а старые копии могли
# остаться в системе. Удаляем все регистрации с этим bundle ID, чтобы
# осталась только установленная копия.
killall fmtFinder 2>/dev/null || true
pluginkit -m -A -v -i "$EXTENSION_ID" | awk -F '\t' 'NF > 1 { print $NF }' | \
sort -u | \
while IFS= read -r registered_path; do
  pluginkit -r "$registered_path" 2>/dev/null || true
done
# Хранилища «всех» и «активных» плагинов могут расходиться: убираем и из второго.
pluginkit -m -v -i "$EXTENSION_ID" | awk -F '\t' 'NF > 1 { print $NF }' | \
sort -u | \
while IFS= read -r registered_path; do
  pluginkit -r "$registered_path" 2>/dev/null || true
done

mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALL_DIR/fmt.app"
# -p сохраняет mtime исполняемого файла — по нему в настройках показывается дата сборки.
cp -Rp "$APP" "$INSTALL_DIR/fmt.app"

# Каталог настроек и перенос файла со старого пути.
mkdir -p /Users/Shared/fmt
if [ ! -f /Users/Shared/fmt/menu-settings.json ] && [ -f /Users/Shared/fmt-menu-settings.json ]; then
  mv /Users/Shared/fmt-menu-settings.json /Users/Shared/fmt/menu-settings.json
fi

echo "Регистрация расширения Finder..."
INSTALLED_PLUGIN="$INSTALL_DIR/fmt.app/Contents/PlugIns/fmtFinder.appex"
for attempt in 1 2 3; do
  pluginkit -a "$INSTALLED_PLUGIN"
  pluginkit -e use -i "$EXTENSION_ID"
  if pluginkit -m -A -v -i "$EXTENSION_ID" | grep -qF "$INSTALLED_PLUGIN"; then
    break
  fi
  sleep 1
done

echo "Перезапуск Finder..."
killall Finder || true

echo "Готово. Если macOS запросит разрешение, включите расширение в"
echo "Системные настройки → Общие → Объекты входа и расширения → Расширения Finder."
