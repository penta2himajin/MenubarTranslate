#!/usr/bin/env bash
# Build MenubarTranslate.app (ADR 0010). Usage:
#   ./scripts/package-app.sh           # writes dist/MenubarTranslate.app
#   ./scripts/package-app.sh --install # also copies to /Applications and links weights
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$REPO_ROOT/dist"
APP="$DIST/MenubarTranslate.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RES="$CONTENTS/Resources"
INSTALL=0
for arg in "$@"; do
    case "$arg" in
        --install) INSTALL=1 ;;
        *) echo "unknown arg: $arg" >&2; exit 2 ;;
    esac
done

cd "$REPO_ROOT"
swift build -c release --product MenubarTranslateApp
BIN="$(swift build -c release --product MenubarTranslateApp --show-bin-path)/MenubarTranslateApp"

rm -rf "$APP"
mkdir -p "$MACOS" "$RES"
cp "$BIN" "$MACOS/MenubarTranslate"
chmod +x "$MACOS/MenubarTranslate"

BIN_DIR="$(dirname "$BIN")"
if [[ -d "$BIN_DIR/MenubarTranslate_MenubarTranslateApp.bundle" ]]; then
    cp -R "$BIN_DIR/MenubarTranslate_MenubarTranslateApp.bundle" "$MACOS/"
fi
cp "$REPO_ROOT/app/Resources/MenuBarIconTemplate.png" "$RES/"
cp "$REPO_ROOT/app/Info.plist" "$CONTENTS/Info.plist"

ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
SRC="$REPO_ROOT/app/Resources/AppIcon.png"
sips -z 16 16     "$SRC" --out "$ICONSET/icon_16x16.png" >/dev/null
sips -z 32 32     "$SRC" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
sips -z 32 32     "$SRC" --out "$ICONSET/icon_32x32.png" >/dev/null
sips -z 64 64     "$SRC" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
sips -z 128 128   "$SRC" --out "$ICONSET/icon_128x128.png" >/dev/null
sips -z 256 256   "$SRC" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256   "$SRC" --out "$ICONSET/icon_256x256.png" >/dev/null
sips -z 512 512   "$SRC" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512   "$SRC" --out "$ICONSET/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$SRC" --out "$ICONSET/icon_512x512@2x.png" >/dev/null
iconutil -c icns "$ICONSET" -o "$RES/AppIcon.icns"
rm -rf "$(dirname "$ICONSET")"

echo "wrote $APP"

if [[ "$INSTALL" -eq 1 ]]; then
    pkill -x MenubarTranslate 2>/dev/null || true
    pkill -x MenubarTranslateApp 2>/dev/null || true
    ditto "$APP" /Applications/MenubarTranslate.app
    xattr -cr /Applications/MenubarTranslate.app 2>/dev/null || true
    SUPPORT="$HOME/Library/Application Support/MenubarTranslate/models"
    mkdir -p "$SUPPORT"
    WEIGHT="$REPO_ROOT/models/weights/gemma-4-E2B_q4_0-it.gguf"
    if [[ -f "$WEIGHT" && ! -e "$SUPPORT/gemma-4-E2B_q4_0-it.gguf" ]]; then
        ln -s "$WEIGHT" "$SUPPORT/gemma-4-E2B_q4_0-it.gguf"
        echo "linked weights → $SUPPORT/gemma-4-E2B_q4_0-it.gguf"
    fi
    echo "installed /Applications/MenubarTranslate.app"
    open /Applications/MenubarTranslate.app
fi
