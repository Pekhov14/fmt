#!/bin/bash
# Пересобирает AppIcon.appiconset из исходного изображения (по умолчанию app.webp).
# Использование: ./scripts/build-icons.sh [путь к изображению]
set -euo pipefail

cd "$(dirname "$0")/.."

SOURCE="${1:-$PWD/app.webp}"
ICONSET="fmt/Assets.xcassets/AppIcon.appiconset"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/fmt-icons.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

if [ ! -f "$SOURCE" ]; then
  echo "Не найдено исходное изображение: $SOURCE" >&2
  exit 1
fi

echo "Исходник: $SOURCE"

# 1. Приводим изображение к PNG.
PNG="$TMP/source.png"
case "${SOURCE##*.}" in
  webp|WEBP)
    if command -v dwebp >/dev/null 2>&1; then
      dwebp "$SOURCE" -o "$PNG"
    elif command -v ffmpeg >/dev/null 2>&1; then
      ffmpeg -y -loglevel error -i "$SOURCE" "$PNG"
    else
      sips -s format png "$SOURCE" --out "$PNG" >/dev/null
    fi
    ;;
  *)
    sips -s format png "$SOURCE" --out "$PNG" >/dev/null
    ;;
esac

# 2. Обрезаем до квадрата по центру — иконка должна быть квадратной.
W="$(sips -g pixelWidth "$PNG" | awk '/pixelWidth/{print $2}')"
H="$(sips -g pixelHeight "$PNG" | awk '/pixelHeight/{print $2}')"
SIDE=$(( W < H ? W : H ))
SQUARE="$TMP/square.png"
if [ "$W" -eq "$H" ]; then
  cp "$PNG" "$SQUARE"
else
  sips --cropToHeightWidth "$SIDE" "$SIDE" "$PNG" --out "$SQUARE" >/dev/null
fi
if [ "$SIDE" -lt 1024 ]; then
  echo "Внимание: исходник ${SIDE}px — для резкой 1024px иконки лучше взять изображение побольше." >&2
fi

# 3. Готовим все размеры для macOS.
mkdir -p "$ICONSET"
rm -f "$ICONSET"/icon_*.png
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$SQUARE" --out "$ICONSET/icon_${size}.png" >/dev/null
  sips -z "$((size * 2))" "$((size * 2))" "$SQUARE" --out "$ICONSET/icon_${size}@2x.png" >/dev/null
done

cat > "$ICONSET/Contents.json" <<'EOF'
{
  "images" : [
    { "filename" : "icon_16.png", "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
    { "filename" : "icon_16@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
    { "filename" : "icon_32.png", "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
    { "filename" : "icon_32@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
    { "filename" : "icon_128.png", "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
    { "filename" : "icon_128@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
    { "filename" : "icon_256.png", "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
    { "filename" : "icon_256@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
    { "filename" : "icon_512.png", "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
    { "filename" : "icon_512@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
EOF

python3 -m json.tool "$ICONSET/Contents.json" >/dev/null

# 4. Шаблонная иконка для строки меню — из того же исходника.
swift "$(dirname "$0")/render-menubar-icon.swift" "$SQUARE" \
  "$PWD/fmt/Assets.xcassets/MenuBarIcon.imageset"

echo "Иконки обновлены: $ICONSET"
echo "Пересоберите приложение: ./scripts/install.sh"
