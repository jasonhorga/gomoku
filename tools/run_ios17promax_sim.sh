#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

SIM_NAME="${SIM_NAME:-iPhone 17 Pro Max}"
BUNDLE_ID="com.jasonhorga.gomoku"
SCHEME="gomoku"
PROJECT="build/ios/gomoku.xcodeproj"
CONFIGURATION="Debug"
GODOT_VERSION="${GODOT_VERSION:-4.5.1}"
SCREENSHOT_DIR="docs/superpowers/progress/ios-ui-screenshots"
LOG_DIR="docs/superpowers/progress"
DERIVED_DATA="build/ios/DerivedData-simulator"
APP_PATH="$DERIVED_DATA/Build/Products/$CONFIGURATION-iphonesimulator/gomoku.app"

mkdir -p "$SCREENSHOT_DIR" "$LOG_DIR"

godot_version() {
  "$1" --version 2>/dev/null | awk '{print $1}' | sed 's/-stable$//'
}

is_wanted_godot() {
  [ "$(godot_version "$1")" = "$GODOT_VERSION" ]
}

download_godot() {
  local cache_root="${GOMOKU_IOS_CACHE_DIR:-$HOME/Library/Caches/gomoku-ios-build}"
  local cache_dir="$cache_root/godot-$GODOT_VERSION"
  local app="$cache_dir/Godot.app/Contents/MacOS/Godot"
  if [ -x "$app" ]; then
    printf '%s\n' "$app"
    return 0
  fi

  mkdir -p "$cache_dir"
  local zip_path="$cache_dir/godot-$GODOT_VERSION.zip"
  local url="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_macos.universal.zip"
  echo "Downloading Godot $GODOT_VERSION to $cache_dir..." >&2
  curl -fL "$url" -o "$zip_path"
  ditto -x -k "$zip_path" "$cache_dir"

  app=$(find "$cache_dir" -maxdepth 4 -path '*/Godot.app/Contents/MacOS/Godot' -type f | head -1)
  if [ -n "$app" ] && [ -x "$app" ]; then
    printf '%s\n' "$app"
    return 0
  fi

  echo "Downloaded Godot $GODOT_VERSION but could not find Godot.app in $cache_dir" >&2
  return 1
}

find_godot() {
  if [ -n "${GODOT_BIN:-}" ]; then
    if [ -x "$GODOT_BIN" ]; then
      printf '%s\n' "$GODOT_BIN"
      return 0
    fi
    echo "GODOT_BIN is set but not executable: $GODOT_BIN" >&2
    return 1
  fi

  local candidate
  local candidates=()
  candidates+=("$(command -v godot 2>/dev/null || true)")
  candidates+=("/Applications/Godot.app/Contents/MacOS/Godot")
  candidates+=("/Applications/Godot_mono.app/Contents/MacOS/Godot")
  candidates+=("/Applications/Godot 4.5.app/Contents/MacOS/Godot")
  candidates+=("/Applications/Godot 4.5.1.app/Contents/MacOS/Godot")
  candidates+=("$HOME/Applications/Godot.app/Contents/MacOS/Godot")
  candidates+=("/opt/homebrew/bin/godot")
  candidates+=("/usr/local/bin/godot")

  while IFS= read -r candidate; do
    candidates+=("$candidate")
  done < <(find /Applications "$HOME/Applications" -maxdepth 3 -path '*Godot*.app/Contents/MacOS/Godot*' -type f 2>/dev/null | sort)

  for candidate in "${candidates[@]}"; do
    if [ -n "$candidate" ] && [ -x "$candidate" ] && is_wanted_godot "$candidate"; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  for candidate in "${candidates[@]}"; do
    if [ -n "$candidate" ] && [ -x "$candidate" ]; then
      echo "Found Godot $(godot_version "$candidate") at $candidate, but CI uses $GODOT_VERSION; downloading matching version." >&2
      break
    fi
  done

  download_godot
}

GODOT_CMD="$(find_godot)"

echo "=== Repo state ==="
git status --short --branch || true
git log --oneline -5 || true

echo "=== Tool versions ==="
xcodebuild -version
xcrun simctl help >/dev/null
echo "Godot: $GODOT_CMD"
"$GODOT_CMD" --version || true

echo "=== Resolve simulator: $SIM_NAME ==="
DEVICE_ID=$(xcrun simctl list devices available | awk -v name="$SIM_NAME" '
  index($0, name " (") {
    if (match($0, /\([0-9A-Fa-f-]{36}\)/)) {
      print substr($0, RSTART + 1, RLENGTH - 2)
      exit
    }
  }
')

if [ -z "${DEVICE_ID:-}" ]; then
  echo "Could not find available simulator named: $SIM_NAME"
  echo "Available iPhone Pro Max simulators:"
  xcrun simctl list devices available | grep -E "iPhone .*Pro Max" || true
  echo "Run with SIM_NAME set to one of the names above, for example:"
  echo "  SIM_NAME='iPhone 16 Pro Max' $0"
  exit 1
fi

echo "Simulator UDID: $DEVICE_ID"

if ! xcrun simctl list devices | grep "$DEVICE_ID" | grep -q Booted; then
  echo "=== Boot simulator ==="
  open -a Simulator
  xcrun simctl boot "$DEVICE_ID" || true
fi

xcrun simctl bootstatus "$DEVICE_ID" -b

echo "=== Build Godot iOS Xcode project ==="
PATH="$(dirname "$GODOT_CMD"):$PATH" GODOT_BIN="$GODOT_CMD" bash ./build_ios.sh

if [ ! -d "$PROJECT" ]; then
  echo "Missing Xcode project: $PROJECT"
  exit 1
fi

echo "=== Build simulator app ==="
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "id=$DEVICE_ID" \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  build | tee "$LOG_DIR/ios17promax-xcodebuild.log"

if [ ! -d "$APP_PATH" ]; then
  echo "Could not find built simulator app at: $APP_PATH"
  echo "Searching DerivedData for gomoku.app:"
  find "$DERIVED_DATA" -name 'gomoku.app' -type d -maxdepth 8 || true
  exit 1
fi

echo "=== Install and launch ==="
xcrun simctl terminate "$DEVICE_ID" "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl uninstall "$DEVICE_ID" "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl install "$DEVICE_ID" "$APP_PATH"
xcrun simctl launch "$DEVICE_ID" "$BUNDLE_ID" | tee "$LOG_DIR/ios17promax-launch.log"

sleep 3

echo "=== Screenshot ==="
SCREENSHOT="$SCREENSHOT_DIR/ios17promax-main-menu.png"
xcrun simctl io "$DEVICE_ID" screenshot "$SCREENSHOT"
file "$SCREENSHOT" || true

echo "=== Recent app logs ==="
xcrun simctl spawn "$DEVICE_ID" log show \
  --style compact \
  --last 2m \
  --predicate 'process CONTAINS "gomoku" OR eventMessage CONTAINS "Gomoku" OR eventMessage CONTAINS "UI-DIAG"' \
  > "$LOG_DIR/ios17promax-recent.log" || true

tail -80 "$LOG_DIR/ios17promax-recent.log" || true

echo "=== Done ==="
echo "App path: $APP_PATH"
echo "Screenshot: $SCREENSHOT"
echo "Build log: $LOG_DIR/ios17promax-xcodebuild.log"
echo "Launch log: $LOG_DIR/ios17promax-launch.log"
echo "Recent app log: $LOG_DIR/ios17promax-recent.log"
echo "If the UI is wrong, add screenshots for other screens under: $SCREENSHOT_DIR"
