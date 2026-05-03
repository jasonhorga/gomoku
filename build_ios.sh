#!/usr/bin/env bash
# Local iOS build. Replicates .github/workflows/ios.yml on your Mac so
# you don't pay for the macos-15 runner. Run from repo root:
#
#   ./build_ios.sh           — build the xcodeproj (then archive in Xcode)
#   ./build_ios.sh --beta    — build + upload to TestFlight via fastlane
#
# Prereqs (one-time):
#   brew install godot scons
#   cd <repo>
#   bundle install            # pulls fastlane + xcodeproj gems
#   python3 -m pip install "torch==2.7.*" coremltools numpy
#   Xcode 26.x installed and `xcode-select -p` pointing at it
#
# If TestFlight upload is wanted, also set env vars ASC_KEY_ID,
# ASC_ISSUER_ID, ASC_PRIVATE_KEY (or ASC_PRIVATE_KEY_PATH),
# MATCH_GIT_URL, MATCH_PASSWORD, MATCH_KEYCHAIN_PASSWORD.

set -euo pipefail
cd "$(dirname "$0")"

GODOT_VERSION="${GODOT_VERSION:-4.5.1}"
RUN_BETA=0
for arg in "$@"; do
	case "$arg" in
		--beta) RUN_BETA=1 ;;
		*) echo "Unknown arg: $arg"; exit 2 ;;
	esac
done

echo "=== Phase 0: sanity ==="
GODOT_CMD="${GODOT_BIN:-$(command -v godot 2>/dev/null || true)}"
if [ -z "$GODOT_CMD" ] || [ ! -x "$GODOT_CMD" ]; then
	echo "godot not found. Install with 'brew install --cask godot' or set GODOT_BIN=/path/to/Godot"
	exit 1
fi
for tool in git xcrun xcodebuild bundle; do
	command -v "$tool" >/dev/null || { echo "Missing required tool: $tool"; exit 1; }
done
if command -v python3.11 >/dev/null 2>&1; then
	BASE_PYTHON="$(command -v python3.11)"
elif [ -x "/opt/homebrew/bin/python3.11" ]; then
	BASE_PYTHON="/opt/homebrew/bin/python3.11"
elif [ -x "/usr/local/bin/python3.11" ]; then
	BASE_PYTHON="/usr/local/bin/python3.11"
elif command -v brew >/dev/null 2>&1; then
	echo "Installing Python 3.11 with Homebrew for PyTorch 2.7 compatibility"
	brew install python@3.11
	BASE_PYTHON="$(brew --prefix python@3.11)/bin/python3.11"
else
	echo "Missing Python 3.11. Install it with: brew install python@3.11"
	exit 1
fi
CACHE_ROOT="${GOMOKU_IOS_CACHE_DIR:-$HOME/Library/Caches/gomoku-ios-build}"
VENV_DIR="$CACHE_ROOT/python-3.11-venv"
PYTHON_VERSION="$($BASE_PYTHON - <<'PY'
import sys
print(f"{sys.version_info.major}.{sys.version_info.minor}")
PY
)"
if [ "$PYTHON_VERSION" != "3.11" ]; then
	echo "Expected Python 3.11, got $PYTHON_VERSION from $BASE_PYTHON"
	exit 1
fi
if [ ! -x "$VENV_DIR/bin/python" ]; then
	echo "Creating Python 3.11 venv outside Google Drive: $VENV_DIR"
	"$BASE_PYTHON" -m venv "$VENV_DIR"
fi
PYTHON_CMD="$VENV_DIR/bin/python"
if [ "$($PYTHON_CMD - <<'PY'
import sys
print(f"{sys.version_info.major}.{sys.version_info.minor}")
PY
)" != "3.11" ]; then
	echo "Recreating stale non-3.11 venv: $VENV_DIR"
	rm -rf "$VENV_DIR"
	"$BASE_PYTHON" -m venv "$VENV_DIR"
fi
if ! "$PYTHON_CMD" - <<'PY' >/dev/null 2>&1
import coremltools, numpy, torch, SCons
PY
then
	echo "Installing Python dependencies into external venv: torch 2.7, coremltools, numpy, scons"
	"$PYTHON_CMD" -m pip install --upgrade 'pip<26'
	"$PYTHON_CMD" -m pip install "torch==2.7.*" coremltools numpy scons
fi
export PATH="$VENV_DIR/bin:$PATH"
if ! bundle check >/dev/null 2>&1; then
	echo "Installing Ruby bundle dependencies"
	bundle install
fi
TEMPLATE_DIR="$HOME/Library/Application Support/Godot/export_templates/${GODOT_VERSION}.stable"
if [ ! -f "$TEMPLATE_DIR/ios.zip" ]; then
	echo "Installing Godot $GODOT_VERSION iOS export templates"
	mkdir -p "$TEMPLATE_DIR" "$CACHE_ROOT"
	TEMPLATE_ZIP="$CACHE_ROOT/Godot_v${GODOT_VERSION}-stable_export_templates.tpz"
	if [ ! -f "$TEMPLATE_ZIP" ]; then
		curl -fL "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_export_templates.tpz" -o "$TEMPLATE_ZIP"
	fi
	TMP_TEMPLATES="$CACHE_ROOT/export_templates_${GODOT_VERSION}"
	rm -rf "$TMP_TEMPLATES"
	mkdir -p "$TMP_TEMPLATES"
	ditto -x -k "$TEMPLATE_ZIP" "$TMP_TEMPLATES"
	if [ ! -f "$TMP_TEMPLATES/templates/ios.zip" ]; then
		echo "Downloaded export templates do not contain templates/ios.zip"
		exit 1
	fi
	cp -R "$TMP_TEMPLATES/templates/"* "$TEMPLATE_DIR/"
fi
xcodebuild -version | head -1
"$GODOT_CMD" --version || true

# --- 1. Build the GomokuNeural xcframework (Swift + Obj-C++) ---
echo ""
echo "=== Phase 1: plugin xcframework ==="
if [ ! -d ios_plugin/godot-cpp/include ]; then
	echo "Cloning godot-cpp (branch 4.5, first run only)…"
	git clone --depth=1 --branch=4.5 \
		https://github.com/godotengine/godot-cpp.git ios_plugin/godot-cpp
fi
(cd ios_plugin && bash ./build.sh)

echo ""
echo "=== Phase 2: stage plugin into addons/ ==="
cp -R ios_plugin/build/libgomoku_neural.ios.template_release.xcframework \
		addons/gomoku_neural/
cp -R ios_plugin/build/libgodot-cpp.ios.template_release.xcframework \
		addons/gomoku_neural/

# --- 3. Convert PyTorch → CoreML (for L6 CNN) ---
echo ""
echo "=== Phase 3: best_model.pt → GomokuNet.mlmodelc ==="
(cd ai_server && "$PYTHON_CMD" export_coreml.py data/weights/best_model.pt \
		--filters 128 --blocks 6 \
		-o /tmp/GomokuNet.mlpackage)
xcrun coremlc compile /tmp/GomokuNet.mlpackage /tmp/
du -sh /tmp/GomokuNet.mlmodelc

# --- 4. Godot import + export ---
echo ""
echo "=== Phase 4: Godot import + iOS export ==="
"$GODOT_CMD" --headless --import --quit || true
mkdir -p build/ios
"$GODOT_CMD" --headless --export-release "iOS" build/ios/gomoku.ipa
if ! unzip -p build/ios/gomoku.ipa Payload/gomoku.app/gomoku.pck | strings | grep -q 'scripts/autoload/build_diagnostics.gdc'; then
	echo "Exported IPA is missing build_diagnostics.gdc in gomoku.pck"
	exit 1
fi
ls -la build/ios/

# --- 5. Inject CoreML model + framework into the Godot-exported project ---
echo ""
echo "=== Phase 5: inject CoreML into xcodeproj ==="
bundle exec ruby ios_plugin/scripts/inject_coreml.rb \
		build/ios/gomoku.xcodeproj /tmp/GomokuNet.mlmodelc

echo ""
echo "✅ Build prep done. Xcode project: build/ios/gomoku.xcodeproj"
echo ""

if [ "$RUN_BETA" -eq 1 ]; then
	echo "=== Phase 6: fastlane beta (TestFlight upload) ==="
	bundle exec fastlane beta
else
	echo "Next steps:"
	echo "  (a) Install on device:  open build/ios/gomoku.xcodeproj"
	echo "      → pick your phone as target → ⌘R (or Product → Archive)"
	echo "  (b) TestFlight:         ./build_ios.sh --beta"
fi
